import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/summary.dart';
import 'meesho_api.dart';
import 'web_session.dart';
import 'notifier.dart';
import 'license.dart';

/// Single source of truth for the whole app.
class AppStore extends ChangeNotifier {
  static const _kAccounts = 'otpflow.accounts';
  static const _kInterval = 'otpflow.intervalMin';
  static const _kNotify = 'otpflow.notify';
  static const _kBg = 'otpflow.background';
  static const _kClientType = 'otpflow.clientType';

  final List<Account> accounts = [];
  /// 0 = only when the app opens or you tap refresh.
  int intervalMin = 0;
  bool notifyOnNew = true;
  bool backgroundEnabled = true;


  bool busy = false;
  String? busyLabel;
  Timer? _timer;

  // ------------------------------------------------------------ lifecycle
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAccounts);
    if (raw != null) {
      try {
        accounts
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => Account.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
    intervalMin = p.getInt(_kInterval) ?? 0;
    notifyOnNew = p.getBool(_kNotify) ?? true;
    backgroundEnabled = p.getBool(_kBg) ?? true;
    final ct = p.getString(_kClientType);
    if (ct != null && ct.isNotEmpty) WebSession.goodClientType = ct;
    for (final a in accounts) {
      // Saved OTPs are shown straight away; the silent refresh below only
      // updates them.
      a.status = a.cookies.isNotEmpty ? AccStatus.ok : AccStatus.needsLogin;
      a.lastError = null;
    }
    notifyListeners();
    _restartTimer();
    if (accounts.isNotEmpty) {
      unawaited(WebSession.warmUp());
      refreshAll(silent: true);
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccounts, jsonEncode(accounts.map((a) => a.toJson()).toList()));
    await p.setString(_kClientType, WebSession.goodClientType);
  }

  Future<void> setInterval(int m) async {
    intervalMin = m;
    (await SharedPreferences.getInstance()).setInt(_kInterval, m);
    _restartTimer();
    notifyListeners();
  }

  Future<void> setNotify(bool v) async {
    notifyOnNew = v;
    (await SharedPreferences.getInstance()).setBool(_kNotify, v);
    notifyListeners();
  }

  Future<void> setBackground(bool v) async {
    backgroundEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kBg, v);
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (intervalMin > 0) {
      _timer = Timer.periodic(Duration(minutes: intervalMin), (_) {
        if (!busy) refreshAll(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------- accounts
  Future<String?> addAccount(String email, String password, {String? name}) async {
    if (!License.isActive) return 'This device is not activated';
    if (accounts.length >= License.maxAccounts) {
      return 'Your license covers ${License.maxAccounts} account(s). '
          'Remove one, or ask for a key with a higher limit.';
    }
    if (accounts.any((a) => a.email.toLowerCase() == email.trim().toLowerCase())) {
      return 'This email is already added';
    }
    final acc = Account(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      email: email.trim(),
      password: password,
      name: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
      autoName: name == null || name.trim().isEmpty,
    );
    accounts.add(acc);
    await _save();
    notifyListeners();
    final err = await _loginOne(acc);
    if (err == null) await _fetchOne(acc, allowRelogin: false);
    await _save();
    notifyListeners();
    return err;
  }

  Future<void> removeAccount(Account a) async {
    a.cookies = [];
    accounts.removeWhere((x) => x.id == a.id);
    await _save();
    notifyListeners();
  }

  Future<void> renameAccount(Account a, String name) async {
    final v = name.trim();
    if (v.isEmpty) {
      // Cleared on purpose - fall back to the email prefix and let the next
      // refresh pick the real name up off the panel again.
      a.autoName = true;
      a.name = a.email.split('@').first;
    } else {
      a.autoName = false;
      a.name = v;
    }
    await _save();
    notifyListeners();
  }

  // --------------------------------------------------------------- actions
  /// Re-login the given accounts (or all) and fetch their OTPs.
  Future<void> reloginAll(List<Account> targets) async {
    if (busy) return;
    busy = true;
    busyLabel = 'Logging in…';
    notifyListeners();
    await _parallel(targets, (a) async {
      final err = await _loginOne(a);
      if (err == null) await _fetchOne(a, allowRelogin: false);
    });
    await _save();
    busy = false;
    busyLabel = null;
    notifyListeners();
  }

  /// Fetch OTPs for every account (auto re-login if the session died).
  /// Fetches every account once. Waits briefly if a pass is already running,
  /// so a tap right after opening the app isn't silently swallowed.
  Future<void> refreshAll({bool silent = false}) async {
    if (accounts.isEmpty) return;
    for (var i = 0; i < 60 && busy; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (busy) return;
    busy = true;
    busyLabel = 'Refreshing…';
    if (!silent) notifyListeners();
    final before = {for (final a in accounts) a.id: a.otps.map((o) => o.key).toSet()};
    try {
      await _parallel(List.of(accounts), (a) => _fetchOne(a));
      await _save();
    } finally {
      busy = false;
      busyLabel = null;
      _settleStuck();
      notifyListeners();
    }
    if (notifyOnNew) _notifyNew(before);
  }

  /// Nothing should be left spinning once a pass is over.
  void _settleStuck() {
    for (final a in accounts) {
      if (a.status == AccStatus.working) {
        a.status = a.otps.isNotEmpty ? AccStatus.ok : AccStatus.error;
        a.lastError ??= 'Timed out - tap refresh to try again';
      }
    }
  }

  Future<void> refreshOne(Account a) async {
    // Wait for an in-flight sweep instead of silently doing nothing - a tap
    // that appears to do nothing is worse than a short wait.
    for (var i = 0; i < 60 && busy; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (busy) return;
    busy = true;
    busyLabel = 'Refreshing ${a.name}…';
    notifyListeners();
    final before = {a.id: a.otps.map((o) => o.key).toSet()};
    try {
      await _fetchOne(a);
      await _save();
    } finally {
      busy = false;
      busyLabel = null;
      _settleStuck();
      notifyListeners();
    }
    if (notifyOnNew) _notifyNew(before);
  }

  /// Runs [fn] over [items] with a small concurrency window — this is what
  /// makes a 5-account refresh finish in a couple of seconds.
  Future<void> _parallel(List<Account> items, Future<void> Function(Account) fn, {int width = 4}) async {
    final queue = List.of(items);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final a = queue.removeAt(0);
        try {
          await fn(a);
        } catch (e) {
          a.lastError = e.toString().replaceFirst('Exception: ', '');
        } finally {
          // A row stuck on "working" spins forever; make sure it always lands.
          if (a.status == AccStatus.working) {
            a.status = a.lastError == null ? AccStatus.ok : AccStatus.error;
          }
        }
        notifyListeners();
      }
    }
    await Future.wait(List.generate(width.clamp(1, 6), (_) => worker()));
  }

  /// Signs in through a real WebView.
  ///
  /// Plain HTTP was tried and does not work: Meesho's edge answers even a
  /// simple GET of the login page with "Access Denied" and no cookies, so
  /// there is nothing a set of headers can fix. Attempting it first only added
  /// three wasted requests to every login.
  Future<String?> _loginOne(Account a) async {
    a.status = AccStatus.working;
    a.lastError = null;
    notifyListeners();
    try {
      final r = await WebSession.login(email: a.email, password: a.password);
      a.cookies = r.cookies;
      if (r.identifier.isNotEmpty) a.identifier = r.identifier;
      if (r.storage.isNotEmpty) a.storage = r.storage;
      if (r.supplierId.isNotEmpty) a.supplierId = r.supplierId;
      if (r.phone.isNotEmpty) a.phone = r.phone;
      if (r.storeName.isNotEmpty && a.autoName) a.name = r.storeName;
      a.lastLogin = DateTime.now().millisecondsSinceEpoch;
      a.apiFailures = 0;
      a.status = AccStatus.ok;
      return null;
    } catch (e) {
      a.status = AccStatus.error;
      a.lastError = e.toString().replaceFirst('Exception: ', '');
      return a.lastError;
    }
  }

  Future<void> _fetchOne(Account a, {bool allowRelogin = true}) {
    // A hung WebView used to leave the account spinning forever and, because
    // the shared lock never released, block every other account too.
    return _fetchOneInner(a, allowRelogin: allowRelogin)
        .timeout(const Duration(seconds: 45), onTimeout: () {
      a.status = AccStatus.error;
      a.lastError = 'Timed out - tap refresh to try again';
    });
  }

  Future<void> _fetchOneInner(Account a, {bool allowRelogin = true}) async {
    a.status = AccStatus.working;
    notifyListeners();
    try {
      if (a.cookies.isEmpty) throw SessionExpired();

      // Older builds could save junk like "..." as the store name.
      if (a.autoName && !WebSession.looksLikeStoreName(a.name)) {
        a.name = a.email.split('@').first;
      }

      // Meesho answers 403 / errorCode 1001 without the identifier. Accounts
      // saved before we started capturing it get it recovered here.
      if (a.identifier.isEmpty) {
        a.identifier = await WebSession.discoverIdentifier(a.cookies);
        if (a.identifier.isEmpty) throw SessionExpired();
      }

      // Requests are made from inside the WebView, so they carry the Akamai
      // cookie the bot manager insists on. A fetch() is just an XHR — no page
      // render — so this stays quick.
      dynamic data;
      var gotQuick = false;
      var pageReady = false;

      // supplier_id is what unlocks the one-request path. It is usually sitting
      // in the storage we already saved at login; only ask the API if it isn't.
      if (a.supplierId.isEmpty) {
        a.supplierId = WebSession.supplierIdFromStorage(a.storage);
      }
      if (a.phone.isEmpty) {
        a.phone = WebSession.phoneFromStorage(a.storage);
      }
      if ((a.supplierId.isEmpty || a.phone.isEmpty) && a.apiFailures < 3) {
        await _fetchDetails(a);
      }

      // A run of failures for this account means the quick route is not working
      // for it, so stop paying for the attempt. It is per account on purpose:
      // one account having a bad moment used to push every other account onto
      // the slow page route.
      if (a.apiFailures < 3 && a.supplierId.isNotEmpty) {
        try {
          data = await WebSession.apiCall(
            a.cookies,
            '/api/fulfillment/returnRto/fetchDeliveryOTPs',
            identifier: a.identifier,
            storage: a.storage,
            onCookies: (c) {
              if (c.isNotEmpty) a.cookies = c;
            },
            onStorage: (m) {
              if (m.isNotEmpty) a.storage = m;
            },
            body: {
              'supplier_id': int.tryParse(a.supplierId) ?? a.supplierId,
              'identifier': a.identifier,
              'child_supplier_identifier': null,
              'child_supplier_id': null,
            },
          );
          gotQuick = true;
          a.apiFailures = 0;
        } on SessionExpired {
          rethrow;
        } on TooManyRequests {
          // Opening the Returns page now would mean even more requests, which
          // is the opposite of what a rate limit is asking for.
          a.status = AccStatus.error;
          a.lastError = 'Too many requests - wait a minute, then refresh';
          return;
        } catch (_) {
          a.apiFailures++;
        }
      }

      if (!gotQuick) {
        // First run for this account, or the API refused us: open the Returns
        // page. That pass also hands back supplier_id and the store name, so
        // later refreshes can take the quick route.
        final panel = await WebSession.fetchOtpsViaPanel(
          a.cookies,
          a.identifier,
          storage: a.storage,
          onCookies: (c) {
            if (c.isNotEmpty) a.cookies = c;
          },
        );
        data = panel.otpData;
        pageReady = panel.pageReady;
        if (panel.supplierId.isNotEmpty) a.supplierId = panel.supplierId;
        if (panel.storeName.isNotEmpty && a.autoName) a.name = panel.storeName;
      }

      a.otps = MeeshoApi.parseOtps(data);
      a.fetchedAt = DateTime.now().millisecondsSinceEpoch;
      a.status = AccStatus.ok;
      // An empty list from a page that rendered fine just means nothing is
      // pending right now — that is an answer, not a failure.
      a.lastError = null;
      if (a.otps.isEmpty && !gotQuick && !pageReady) {
        MeeshoApi.lastRawResponse = WebSession.lastDebug;
        a.lastError = 'Could not read the Returns page - see Settings, Session diagnostics';
      }

      if (a.autoName && a.name.contains('@')) {
        unawaited(_fetchDetails(a));
      }
    } on SessionExpired {
      if (allowRelogin) {
        final err = await _loginOne(a);
        if (err == null) {
          // Inner, not the wrapper - the outer timeout already covers this.
          await _fetchOneInner(a, allowRelogin: false);
          return;
        }
        a.status = AccStatus.needsLogin;
      } else {
        a.status = AccStatus.needsLogin;
        a.lastError = 'Session expired - tap relogin';
      }
    } catch (e) {
      a.status = AccStatus.error;
      a.lastError = e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// Store name and supplier id — nice to have, never fatal.
  Future<void> _fetchDetails(Account a) async {
    try {
      final d = await WebSession.apiCall(
        a.cookies,
        '/api/container/supplier/getSupplierDetails',
        identifier: a.identifier,
        storage: a.storage,
        onCookies: (c) {
          if (c.isNotEmpty) a.cookies = c;
        },
      );

      // Only take a plain numeric id — a bare "id" key can belong to anything
      // in the response.
      final id = MeeshoApi.digInto(d, const ['supplier_id', 'supplierId']) ??
          MeeshoApi.digInto(d, const ['id']);
      if (id != null && RegExp(r'^\d{4,10}$').hasMatch(id)) a.supplierId = id;

      final nm = MeeshoApi.digInto(d, const [
        'supplier_name', 'business_name', 'shop_name', 'store_name', 'display_name', 'name',
      ]);
      if (nm != null && a.autoName && WebSession.looksLikeStoreName(nm)) {
        a.name = WebSession.cleanStoreName(nm);
      }

      if (a.phone.isEmpty) {
        final ph = MeeshoApi.digInto(d, const ['phone', 'mobile', 'phone_number', 'mobile_number']);
        if (ph != null && RegExp(r'^[6-9]\d{9}$').hasMatch(ph.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91'), ''))) {
          a.phone = ph.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91'), '');
        }
      }
      notifyListeners();
    } catch (_) {
      // The page fallback will pick these up instead.
    }
  }

  // ============================================ dashboard and payment figures
  /// Loads the Dashboard and Payments numbers for one account.
  ///
  /// Called only when those tabs are opened, never as part of an OTP refresh.
  /// Meesho rate-limits, and an earlier version that fired extra calls on every
  /// refresh is what got this app throttled.
  Future<void> _loadSummary(Account a) async {
    if (a.cookies.isEmpty || a.identifier.isEmpty) return;
    final body = {
      if (a.supplierId.isNotEmpty) 'supplier_id': int.tryParse(a.supplierId) ?? a.supplierId,
      'identifier': a.identifier,
      'child_supplier_identifier': null,
      'child_supplier_id': null,
    };

    final s = a.summary;
    s.error = null;

    try {
      final pay = await WebSession.apiCall(
        a.cookies,
        '/api/payouts/payments/upcoming-total-amount',
        identifier: a.identifier,
        storage: a.storage,
        body: body,
        onCookies: (c) {
          if (c.isNotEmpty) a.cookies = c;
        },
      );
      // Meesho answers {"headerAmount":"₹59.62K","netAmount":59625.66} — the
      // rounded header string is for display, netAmount is the real figure.
      s.upcomingPayment = _num(pay, const [
        'netAmount', 'net_amount', 'upcoming_total_amount', 'total_amount', 'amount',
      ]);
      s.headerAmount = MeeshoApi.digInto(pay, const ['headerAmount', 'header_amount']);
      s.nextPaymentDate = MeeshoApi.digInto(pay, const [
        'next_payment_date', 'payment_date', 'nextPaymentDate',
      ]);
    } on TooManyRequests {
      s.error = 'Too many requests - wait a minute, then refresh';
    } catch (e) {
      s.error = e.toString().replaceFirst('Exception: ', '');
    }

    // Unscheduled payouts. The same body that suits the 7-day call gets a 500
    // here, so an empty one is tried as well before giving up — this endpoint
    // takes its context from the session, not the payload.
    for (final payload in [body, const <String, dynamic>{}]) {
      try {
        final ui = await WebSession.apiCall(
          a.cookies,
          '/api/payouts/payments/all-ui-data',
          identifier: a.identifier,
          storage: a.storage,
          body: payload,
          onCookies: (c) {
            if (c.isNotEmpty) a.cookies = c;
          },
        );
        final rows = _payoutRows(ui);
        if (rows.isNotEmpty) s.payouts = rows;
        s.unscheduledPayout = _num(ui, const [
          'netAmount', 'net_amount', 'total_amount', 'totalAmount', 'amount',
        ]);
        break;
      } on TooManyRequests {
        s.error ??= 'Too many requests - wait a minute, then refresh';
        break;
      } catch (_) {
        // try the next shape; the 7-day figure above is the important one
      }
    }

    await _loadOrderCounts(a);

    s.fetchedAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    notifyListeners();
  }

  /// Turns Meesho's payoutUIList / payoutList into rows we can show. The shape
  /// varies, so each entry is searched for a label, an amount and a date rather
  /// than assuming fixed keys.
  static List<PayoutRow> _payoutRows(dynamic data) {
    final out = <PayoutRow>[];

    void collect(dynamic node, int depth) {
      if (depth > 6 || node == null) return;
      if (node is List) {
        for (final v in node) {
          collect(v, depth + 1);
        }
        return;
      }
      if (node is! Map) return;
      final map = node.map((k, v) => MapEntry(k.toString(), v));

      final amount = _num(map, const [
        'netAmount', 'net_amount', 'amount', 'total_amount', 'totalAmount', 'value',
      ]);
      final label = MeeshoApi.digInto(map, const [
        'title', 'label', 'name', 'heading', 'type', 'payout_type',
      ]);
      if (amount != null && label != null && label.length < 60) {
        final date = MeeshoApi.digInto(map, const [
          'date', 'payment_date', 'payout_date', 'settlement_date', 'subtitle',
        ]);
        final already = out.any((r) => r.label == label && r.amount == amount);
        if (!already) out.add(PayoutRow(label: label, amount: amount, date: date));
      }

      for (final v in map.values) {
        collect(v, depth + 1);
      }
    }

    // Prefer the lists Meesho names explicitly.
    if (data is Map) {
      for (final key in const ['payoutUIList', 'payout_ui_list', 'payoutList', 'payout_list']) {
        final v = data[key];
        if (v != null) {
          collect(v, 0);
          if (out.isNotEmpty) return out;
        }
      }
    }
    collect(data, 0);
    return out;
  }

  /// Order counts, straight from the API — no page visit.
  ///
  /// The type/status pairs below came off the panel's own requests:
  /// hold = 0, pending = 1, ready-to-ship = 3. They are not guessable — `hold`
  /// is not `on_hold`, and `ready-to-ship` uses hyphens — and a wrong pair is
  /// answered with a 500.
  ///
  /// One request per tab returns `total_count`, and for ready-to-ship also
  /// `label_not_downloaded_count`, which gives the downloaded split for free.
  Future<void> _loadOrderCounts(Account a) async {
    if (a.supplierId.isEmpty || a.identifier.isEmpty) return;
    final s = a.summary;
    final id = int.tryParse(a.supplierId) ?? a.supplierId;

    Future<Map<String, int>?> countFor(String type, int status) async {
      try {
        final res = await WebSession.apiCall(
          a.cookies,
          '/api/fulfillment/orders',
          identifier: a.identifier,
          storage: a.storage,
          body: {
            'enable_hold': true,
            'supplier_details': {
              'id': id,
              'identifier': a.identifier,
              'name': a.name,
            },
            'cursor': null,
            // One row is plenty; we only read the totals.
            'limit': 1,
            'status': status,
            'type': type,
            'identifier': a.identifier,
            'child_supplier_identifier': null,
            'child_supplier_id': null,
          },
          onCookies: (c) {
            if (c.isNotEmpty) a.cookies = c;
          },
        );
        final total = _int(res, const ['total_count', 'totalCount']);
        if (total == null) {
          s.ordersNote = 'No count returned for "$type"';
          return null;
        }
        final notDownloaded =
            _int(res, const ['label_not_downloaded_count', 'labelNotDownloadedCount']);
        return {
          'total': total,
          if (notDownloaded != null) 'notDownloaded': notDownloaded,
        };
      } on TooManyRequests {
        rethrow;
      } catch (e) {
        s.ordersNote = 'Orders ($type): ${e.toString().replaceFirst('Exception: ', '')}';
        return null;
      }
    }

    try {
      final hold = await countFor('hold', 0);
      if (hold != null) s.onHold = hold['total'];

      final pending = await countFor('pending', 1);
      if (pending != null) s.pendingOrders = pending['total'];

      final rts = await countFor('ready-to-ship', 3);
      if (rts != null) {
        s.readyToShip = rts['total'];
        final pendingLabel = rts['notDownloaded'];
        if (pendingLabel != null) {
          s.rtsLabelPending = pendingLabel;
          s.rtsLabelDone = (rts['total']! - pendingLabel).clamp(0, rts['total']!);
        }
      }

      if (s.onHold != null || s.pendingOrders != null || s.readyToShip != null) {
        s.ordersNote = null;
      }
    } on TooManyRequests {
      s.error ??= 'Too many requests - wait a minute, then refresh';
    }
  }

  /// Refreshes one account's figures, for the per-row refresh buttons.
  Future<void> refreshSummaryFor(Account a) async {
    if (busy) return;
    busy = true;
    busyLabel = 'Loading ${a.name}…';
    notifyListeners();
    try {
      await _loadSummary(a).timeout(const Duration(seconds: 40), onTimeout: () {
        a.summary.error = 'Timed out';
      });
    } finally {
      busy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  /// SKU lines behind one of the ready-to-ship label states.
  ///
  /// The same orders endpoint carries them — a count asks for one row, this
  /// asks for a page and keeps the groups in the state we want.
  Future<void> loadRtsSkus(Account a, {required bool downloaded}) async {
    if (a.supplierId.isEmpty || a.identifier.isEmpty || busy) return;
    busy = true;
    busyLabel = 'Reading SKUs…';
    notifyListeners();
    try {
      final res = await WebSession.apiCall(
        a.cookies,
        '/api/fulfillment/orders',
        identifier: a.identifier,
        storage: a.storage,
        body: {
          'enable_hold': true,
          'supplier_details': {
            'id': int.tryParse(a.supplierId) ?? a.supplierId,
            'identifier': a.identifier,
            'name': a.name,
          },
          'cursor': null,
          'limit': 50,
          'status': 3,
          'type': 'ready-to-ship',
          'identifier': a.identifier,
          'child_supplier_identifier': null,
          'child_supplier_id': null,
        },
        onCookies: (c) {
          if (c.isNotEmpty) a.cookies = c;
        },
      );
      final lines = _skusByLabelState(res, downloaded);
      if (downloaded) {
        a.summary.rtsDoneSkus = lines;
      } else {
        a.summary.rtsPendingSkus = lines;
      }
      if (lines.isEmpty) {
        a.summary.ordersNote =
            'No SKU lines came back for ${downloaded ? "downloaded" : "pending"} labels';
      } else {
        a.summary.ordersNote = null;
      }
      await _save();
    } on TooManyRequests {
      a.summary.error = 'Too many requests - wait a minute, then refresh';
    } catch (e) {
      a.summary.ordersNote = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  /// Walks `data.groups` and totals each SKU in the wanted label state.
  ///
  /// The SKU lives in `product_sku` — not `sku`, which is why an earlier
  /// version found nothing. The label state is on the sub-order itself as
  /// "Downloaded" / "Not Downloaded"; the group flag is only a fallback.
  static List<SkuLine> _skusByLabelState(dynamic data, bool downloaded) {
    final totals = <String, SkuLine>{};

    void addSub(dynamic sub, bool groupDownloaded) {
      if (sub is! Map) return;
      final m = sub.map((k, v) => MapEntry(k.toString(), v));

      final label = '${m['label'] ?? ''}'.toLowerCase();
      final isDownloaded = label.isEmpty
          ? groupDownloaded
          : (label.contains('not') ? false : label.contains('download'));
      if (isDownloaded != downloaded) return;

      final sku = MeeshoApi.digInto(m, const [
        'product_sku', 'sku', 'sku_id', 'skuId', 'seller_sku', 'supplier_sku',
      ]) ?? '';
      if (sku.isEmpty) return;

      final name = MeeshoApi.digInto(m, const ['name', 'product_name', 'title']) ?? '';
      final qty = _int(m, const ['quantity', 'qty', 'count']) ?? 1;
      final prev = totals[sku];
      totals[sku] = SkuLine(
        sku: sku,
        name: (prev != null && prev.name.isNotEmpty) ? prev.name : name,
        qty: (prev?.qty ?? 0) + qty,
      );
    }

    void walkGroup(dynamic g) {
      if (g is! Map) return;
      final m = g.map((k, v) => MapEntry(k.toString(), v));
      final groupDownloaded =
          m['label_downloaded'] == true || m['downloaded'] == true;
      final orders = m['orders'];
      if (orders is! List) return;
      for (final o in orders) {
        if (o is! Map) continue;
        final subs = o['sub_orders'];
        if (subs is List) {
          for (final sb in subs) {
            addSub(sb, groupDownloaded);
          }
        } else {
          addSub(o, groupDownloaded);
        }
      }
    }

    void find(dynamic node, int depth) {
      if (depth > 6 || node == null) return;
      if (node is List) {
        for (final v in node) {
          find(v, depth + 1);
        }
        return;
      }
      if (node is! Map) return;
      final groups = node['groups'];
      if (groups is List) {
        for (final g in groups) {
          walkGroup(g);
        }
      }
      for (final v in node.values) {
        find(v, depth + 1);
      }
    }

    find(data, 0);
    return totals.values.toList()..sort((x, y) => y.qty.compareTo(x.qty));
  }

  /// Loads figures for every account, one at a time.
  Future<void> loadSummaries({bool force = false}) async {
    if (busy || accounts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final targets = accounts.where((a) {
      if (force) return true;
      final at = a.summary.fetchedAt;
      // Re-reading figures that are minutes old is not worth a request.
      return at == null || now - at > 10 * 60 * 1000;
    }).toList();
    if (targets.isEmpty) return;

    busy = true;
    busyLabel = 'Loading figures…';
    notifyListeners();
    try {
      for (final a in targets) {
        await _loadSummary(a).timeout(const Duration(seconds: 40), onTimeout: () {
          a.summary.error = 'Timed out';
        });
      }
    } finally {
      busy = false;
      busyLabel = null;
      notifyListeners();
    }
  }

  static num? _num(dynamic data, List<String> keys) {
    final v = MeeshoApi.digInto(data, keys);
    if (v == null) return null;
    return num.tryParse(v.replaceAll(RegExp(r'[^\d.\-]'), ''));
  }

  static int? _int(dynamic data, List<String> keys) {
    final v = _num(data, keys);
    return v?.round();
  }

  /// Totals across every account, for the Dashboard header.
  num get totalUpcomingPayment =>
      accounts.fold<num>(0, (t, a) => t + (a.summary.upcomingPayment ?? 0));
  int get totalPendingOrders =>
      accounts.fold<int>(0, (t, a) => t + (a.summary.pendingOrders ?? 0));
  int get totalReadyToShip =>
      accounts.fold<int>(0, (t, a) => t + (a.summary.readyToShip ?? 0));

  int get totalOnHold => accounts.fold<int>(0, (t, a) => t + (a.summary.onHold ?? 0));

  /// True once at least one account reported an order count. Until then the
  /// Dashboard hides those tiles rather than showing a misleading zero.
  int get totalLabelPending =>
      accounts.fold<int>(0, (t, a) => t + (a.summary.rtsLabelPending ?? 0));
  int get totalLabelDone =>
      accounts.fold<int>(0, (t, a) => t + (a.summary.rtsLabelDone ?? 0));

  bool get hasOrderCounts => accounts.any((a) =>
      a.summary.pendingOrders != null ||
      a.summary.readyToShip != null ||
      a.summary.onHold != null);

  void _notifyNew(Map<String, Set<String>> before) {
    for (final a in accounts) {
      final old = before[a.id] ?? {};
      final fresh = a.otps.where((o) => !old.contains(o.key)).toList();
      for (final o in fresh) {
        Notifier.show(
          title: '${o.carrier} · ${o.otp}',
          body: '${a.name} · ${o.count} parcel(s) ready for handover',
        );
      }
    }
  }

  // --------------------------------------------------------------- getters
  int get totalReturns => accounts.fold(0, (s, a) => s + a.totalReturns);
  int get totalOtps => accounts.fold(0, (s, a) => s + a.otps.length);

  List<CarrierGroup> get byCarrier {
    final map = <String, CarrierGroup>{};
    for (final a in accounts) {
      for (final o in a.otps) {
        final g = map.putIfAbsent(o.carrier, () => CarrierGroup(o.carrier));
        g.total += o.count;
        g.rows.add(CarrierRow(
          accountId: a.id, accountName: a.name, otp: o.otp, count: o.count, time: o.time,
        ));
      }
    }
    final list = map.values.toList()..sort((x, y) => y.total.compareTo(x.total));
    for (final g in list) { g.rows.sort((x, y) => y.count.compareTo(x.count)); }
    return list;
  }
}
