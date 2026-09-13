import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

/// Plain HTTP against Meesho's API — no WebView, so a login or a refresh is a
/// single request that comes back in about a second.
///
/// The part that matters is the warm-up: the panel's HTML login page is
/// fetched first. Meesho sits behind Akamai, which hands out a session cookie
/// on that ordinary page request, and the API then accepts the call. Going
/// straight to the API with no such cookie is what produced "Access Denied".
///
/// The headers are deliberately plain — a short user-agent and no `Origin`,
/// `Referer` or `sec-ch-ua`. A navigation GET carrying an Origin header and a
/// JSON content-type is not something a browser ever sends, and claiming to be
/// Chrome while behaving otherwise is exactly what gets a client refused.
class MeeshoHttp {
  static const base = 'https://supplier.meesho.com';
  static const loginPage = '$base/panel/v3/new/root/login';
  static const loginApi = '/api/container/user/v2-login';

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
  static const _pkgVersion = '1.0.28';

  /// Values Meesho accepts for `client-type`.
  static const clientTypes = ['web', 'd-web', 'supplier-web'];

  /// Remembered once we learn which one this account's API answers to.
  static String goodClientType = 'web';

  /// Transcript for Settings → Session diagnostics.
  static String? lastDebug;
  static final List<String> _history = [];

  static void _record(String entry) {
    _history.add(entry.trim());
    while (_history.length > 6) {
      _history.removeAt(0);
    }
    lastDebug = _history.join('\n\n');
  }

  final Dio _dio;
  final CookieJar _jar;
  MeeshoHttp._(this._dio, this._jar);

  static Future<MeeshoHttp> create(
    List<Map<String, String>> cookies, {
    String? token,
    String? identifier,
  }) async {
    final jar = CookieJar();
    if (cookies.isNotEmpty) {
      final parsed = cookies
          .map((c) => Cookie(c['name'] ?? '', c['value'] ?? '')
            ..domain = c['domain'] ?? '.meesho.com'
            ..path = c['path'] ?? '/')
          .toList();
      await jar.saveFromResponse(Uri.parse(base), parsed);
    }

    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'user-agent': _ua,
        'accept-language': 'en-US,en;q=0.9',
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
        if (identifier != null && identifier.isNotEmpty) 'identifier': identifier,
      },
      validateStatus: (s) => s != null && s < 600,
    ));
    dio.interceptors.add(CookieManager(jar));
    return MeeshoHttp._(dio, jar);
  }

  Future<List<Map<String, String>>> cookies() async {
    final list = await _jar.loadForRequest(Uri.parse(base));
    return list
        .map((c) => <String, String>{
              'name': c.name,
              'value': c.value,
              if (c.domain != null) 'domain': c.domain!,
              if (c.path != null) 'path': c.path!,
            })
        .toList();
  }

  /// Headers for an ordinary page request — what a browser sends when you type
  /// the address in. No Origin, no JSON content-type.
  Options get _pageHeaders => Options(
        headers: {
          'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'accept-encoding': 'gzip, deflate',
          'upgrade-insecure-requests': '1',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      );

  /// Headers for an API call.
  Options _apiHeaders(String clientType) => Options(
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-encoding': 'gzip, deflate',
          'content-type': 'application/json',
          'client-type': clientType,
          'client-package-version': _pkgVersion,
        },
      );

  /// Fetches the login page so Akamai hands us its session cookie.
  Future<String> _warmUp() async {
    try {
      final res = await _dio.get(loginPage, options: _pageHeaders);
      final jarCookies = await _jar.loadForRequest(Uri.parse(base));
      final names = jarCookies.map((c) => c.name).join(', ');
      return 'warm-up GET login page -> HTTP ${res.statusCode}, '
          '${jarCookies.length} cookie(s)${names.isEmpty ? '' : ': $names'}';
    } on DioException catch (e) {
      return 'warm-up GET login page -> ${e.response?.statusCode ?? e.type.name}';
    }
  }

  // ------------------------------------------------------------------ login
  Future<Map<String, String>> login(String email, String password) async {
    final log = StringBuffer();
    log.writeln(await _warmUp());
    log.writeln('POST $loginApi');

    for (final ct in [goodClientType, ...clientTypes.where((t) => t != goodClientType)]) {
      Response res;
      try {
        res = await _dio.post(
          loginApi,
          data: {'email': email.trim(), 'password': password},
          options: _apiHeaders(ct),
        );
      } on DioException catch (e) {
        log.writeln('  ct=$ct -> ${e.message ?? e.type.name}');
        continue;
      }

      final body = _preview(res.data);
      log.writeln('  ct=$ct -> HTTP ${res.statusCode}  $body');

      // Both 400 and 403 can mean "not this client-type" - keep trying the
      // others instead of giving up the way an earlier version did.
      if (res.statusCode == 400 || res.statusCode == 403) continue;

      if (res.statusCode == 401) {
        _record(log.toString());
        throw MeeshoHttpError(_dig(res.data, const ['message', 'error']) ?? 'Wrong email or password');
      }
      if (res.statusCode != 200) {
        _record(log.toString());
        throw MeeshoHttpError('Login failed (HTTP ${res.statusCode})');
      }

      final token = _dig(res.data, const ['token', 'access_token', 'accessToken', 'id_token']) ?? '';
      final jarCookies = await _jar.loadForRequest(Uri.parse(base));
      if (token.isEmpty && jarCookies.isEmpty) {
        _record(log.toString());
        throw MeeshoHttpError('Login returned no session');
      }

      goodClientType = ct;
      if (token.isNotEmpty) _dio.options.headers['authorization'] = 'Bearer $token';

      final out = <String, String>{
        'token': token,
        'identifier': _dig(res.data, const ['identifier', 'supplier_identifier']) ?? '',
        'supplierId': _dig(res.data, const ['supplier_id', 'supplierId']) ?? '',
        'storeName': _dig(res.data,
                const ['supplier_name', 'business_name', 'shop_name', 'store_name', 'name']) ??
            '',
      };

      if (out['identifier']!.isEmpty || out['supplierId']!.isEmpty || out['storeName']!.isEmpty) {
        try {
          final d = await supplierDetails();
          for (final k in ['identifier', 'supplierId', 'storeName']) {
            if (out[k]!.isEmpty && (d[k] ?? '').isNotEmpty) out[k] = d[k]!;
          }
          log.writeln('  details -> id=${out['supplierId']} identifier=${out['identifier']}');
        } catch (e) {
          log.writeln('  details failed: $e');
        }
      }

      _record(log.toString());
      return out;
    }

    _record(log.toString());
    throw MeeshoHttpError('Meesho refused the login - see Settings, Session diagnostics');
  }

  // ------------------------------------------------------------ other calls
  Future<Map<String, String>> supplierDetails() async {
    final res = await _dio.post(
      '/api/container/supplier/getSupplierDetails',
      data: {},
      options: _apiHeaders(goodClientType),
    );
    if (res.statusCode == 401 || res.statusCode == 403) throw SessionDead();
    if (res.statusCode != 200) throw MeeshoHttpError('Details failed (HTTP ${res.statusCode})');
    return {
      'identifier': _dig(res.data, const ['identifier', 'supplier_identifier']) ?? '',
      'supplierId': _dig(res.data, const ['supplier_id', 'supplierId', 'id']) ?? '',
      'storeName': _dig(res.data,
              const ['supplier_name', 'business_name', 'shop_name', 'store_name', 'name']) ??
          '',
    };
  }

  /// The panel sends exactly this body; anything else comes back 500.
  Future<dynamic> fetchOtps({required String supplierId, required String identifier}) async {
    _dio.options.headers['identifier'] = identifier;
    final res = await _dio.post(
      '/api/fulfillment/returnRto/fetchDeliveryOTPs',
      data: {
        'supplier_id': int.tryParse(supplierId) ?? supplierId,
        'identifier': identifier,
        'child_supplier_identifier': null,
        'child_supplier_id': null,
      },
      options: _apiHeaders(goodClientType),
    );
    _record('POST fetchDeliveryOTPs ct=$goodClientType identifier=$identifier\n'
        '  HTTP ${res.statusCode}  ${_preview(res.data)}');

    if (res.statusCode == 401 || res.statusCode == 403) throw SessionDead();
    if (res.statusCode != 200) throw MeeshoHttpError('OTP fetch failed (HTTP ${res.statusCode})');
    return res.data;
  }

  // -------------------------------------------------------------- utilities
  static String? _dig(dynamic node, List<String> keys, [int depth = 0]) {
    if (depth > 6 || node == null) return null;
    if (node is List) {
      for (final v in node) {
        final r = _dig(v, keys, depth + 1);
        if (r != null) return r;
      }
      return null;
    }
    if (node is! Map) return null;
    for (final k in keys) {
      for (final e in node.entries) {
        if (e.key.toString().toLowerCase() == k.toLowerCase()) {
          final v = e.value;
          if (v != null && v is! Map && v is! List && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
      }
    }
    for (final v in node.values) {
      final r = _dig(v, keys, depth + 1);
      if (r != null) return r;
    }
    return null;
  }

  static String _preview(dynamic d, [int cap = 400]) {
    try {
      final s = d is String ? d : jsonEncode(d);
      final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      return one.length > cap ? '${one.substring(0, cap)}...' : one;
    } catch (_) {
      return '$d';
    }
  }
}

class MeeshoHttpError implements Exception {
  final String message;
  MeeshoHttpError(this.message);
  @override
  String toString() => message;
}

class SessionDead implements Exception {
  @override
  String toString() => 'Session expired';
}
