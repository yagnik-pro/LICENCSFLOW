import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

/// Plain HTTP against Meesho's API — no WebView, so a refresh takes about a
/// second instead of loading a whole page.
///
/// Meesho's edge refuses clients that look inconsistent. Sending a full Chrome
/// user-agent with `sec-ch-ua` hints while actually being a Dart HTTP client is
/// exactly the kind of mismatch it rejects, which is what produced the earlier
/// 403s on even the login page. The three headers below are what the panel
/// itself sends, and with a short user-agent the requests go through.
class MeeshoHttp {
  static const base = 'https://supplier.meesho.com';

  /// Short on purpose. A long Chrome string contradicts the TLS fingerprint.
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
  static const _pkgVersion = '1.0.28';

  /// Values Meesho accepts. Anything else answers
  /// `400 {"message":"Bad Request. Invalid client type."}`.
  static const clientTypes = ['d-web', 'web'];
  static String activeClientType = 'd-web';

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

  /// A client seeded with an account's saved cookies. Async because the jar
  /// writes are futures — doing this in a factory left a race where the first
  /// request could go out before the cookies landed.
  static Future<MeeshoHttp> create(
    List<Map<String, String>> cookies, {
    String? token,
  }) async {
    final jar = CookieJar();
    if (cookies.isNotEmpty) {
      final parsed = cookies.map((c) {
        return Cookie(c['name'] ?? '', c['value'] ?? '')
          ..domain = c['domain'] ?? '.meesho.com'
          ..path = c['path'] ?? '/'
          ..secure = c['secure'] != '0'
          ..httpOnly = c['httpOnly'] == '1';
      }).toList();
      await jar.saveFromResponse(Uri.parse(base), parsed);
    }

    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'user-agent': _ua,
        'client-type': activeClientType,
        'client-package-version': _pkgVersion,
        'content-type': 'application/json',
        'accept': 'application/json, text/plain, */*',
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
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
              'secure': c.secure ? '1' : '0',
              'httpOnly': c.httpOnly ? '1' : '0',
            })
        .toList();
  }

  void setIdentifier(String identifier) {
    if (identifier.isEmpty) return;
    _dio.options.headers['identifier'] = identifier;
  }

  // ------------------------------------------------------------------ login
  /// Signs in and returns { token, identifier, supplierId, storeName }.
  Future<Map<String, String>> login(String email, String password) async {
    final log = StringBuffer('POST /api/container/user/v2-login\n');

    for (final ct in [activeClientType, ...clientTypes.where((t) => t != activeClientType)]) {
      _dio.options.headers['client-type'] = ct;
      Response res;
      try {
        res = await _dio.post(
          '/api/container/user/v2-login',
          data: {'email': email.trim(), 'password': password},
        );
      } on DioException catch (e) {
        log.writeln('  ct=$ct -> ${e.message ?? e.type.name}');
        continue;
      }

      final body = _preview(res.data);
      log.writeln('  ct=$ct -> HTTP ${res.statusCode}  $body');

      if (res.statusCode == 400 && '$body'.contains('client type')) continue;

      if (res.statusCode == 401 || res.statusCode == 403) {
        final msg = _dig(res.data, const ['message', 'error', 'detail']);
        _record(log.toString());
        throw MeeshoHttpError(msg ?? 'Wrong email or password');
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

      activeClientType = ct;
      if (token.isNotEmpty) _dio.options.headers['authorization'] = 'Bearer $token';

      final out = <String, String>{
        'token': token,
        'identifier': _dig(res.data, const ['identifier', 'supplier_identifier']) ?? '',
        'supplierId': _dig(res.data, const ['supplier_id', 'supplierId']) ?? '',
        'storeName': _dig(res.data, const ['name', 'supplier_name', 'business_name', 'shop_name']) ?? '',
      };

      // Fill in whatever login did not return.
      if (out['identifier']!.isEmpty || out['supplierId']!.isEmpty || out['storeName']!.isEmpty) {
        try {
          final d = await supplierDetails();
          for (final k in ['identifier', 'supplierId', 'storeName']) {
            if (out[k]!.isEmpty && (d[k] ?? '').isNotEmpty) out[k] = d[k]!;
          }
          log.writeln('  supplier details -> id=${out['supplierId']} '
              'identifier=${out['identifier']} name=${out['storeName']}');
        } catch (e) {
          log.writeln('  supplier details failed: $e');
        }
      }

      _record(log.toString());
      return out;
    }

    _record(log.toString());
    throw MeeshoHttpError('Meesho refused the login - see Settings, Session diagnostics');
  }

  // -------------------------------------------------------- supplier details
  Future<Map<String, String>> supplierDetails() async {
    final res = await _dio.post('/api/container/supplier/getSupplierDetails', data: {});
    if (res.statusCode == 401 || res.statusCode == 403) throw SessionDead();
    if (res.statusCode != 200) throw MeeshoHttpError('Details failed (HTTP ${res.statusCode})');
    return {
      'identifier': _dig(res.data, const ['identifier', 'supplier_identifier']) ?? '',
      'supplierId': _dig(res.data, const ['supplier_id', 'supplierId', 'id']) ?? '',
      'storeName': _dig(res.data,
              const ['name', 'supplier_name', 'business_name', 'shop_name', 'store_name']) ??
          '',
    };
  }

  // --------------------------------------------------------------- the OTPs
  /// The panel sends exactly this body; anything else comes back 500.
  Future<dynamic> fetchOtps({required String supplierId, required String identifier}) async {
    setIdentifier(identifier);
    final body = {
      'supplier_id': int.tryParse(supplierId) ?? supplierId,
      'identifier': identifier,
      'child_supplier_identifier': null,
      'child_supplier_id': null,
    };
    final res = await _dio.post('/api/fulfillment/returnRto/fetchDeliveryOTPs', data: body);
    final preview = _preview(res.data);
    _record('POST /api/fulfillment/returnRto/fetchDeliveryOTPs  '
        'ct=$activeClientType identifier=$identifier\n'
        '  HTTP ${res.statusCode}  $preview');

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

/// Anything the user should read.
class MeeshoHttpError implements Exception {
  final String message;
  MeeshoHttpError(this.message);
  @override
  String toString() => message;
}

/// Cookies are no longer good — the caller should log in again.
class SessionDead implements Exception {
  @override
  String toString() => 'Session expired';
}
