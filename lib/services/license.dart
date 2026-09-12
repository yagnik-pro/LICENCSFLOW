import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:shared_preferences/shared_preferences.dart';

/// Offline, device-bound licensing.
///
/// A key is a signed statement: "this device may run N accounts". The app only
/// carries the *public* key, so nobody can mint keys by decompiling it — only
/// the holder of the private key (you) can issue them.
///
/// Format:  base64url(payload).base64url(signature)
/// Payload: {"d": deviceId, "n": maxAccounts, "exp": epochSeconds or 0, "iat": epochSeconds}
///
/// Because the device id is inside the signed payload, copying a key to another
/// phone fails: the device id will not match and the signature cannot be
/// rewritten without the private key.
class License {
  static const _kKey = 'otpflow.license.key';

  /// Public half of your signing key. Replace with your own — see
  /// `tool/keygen.dart` or the "Issue license key" GitHub Action.
  static const publicKeyHex =
      'd77683e99d7e1b7d09658a53dc0198b8f4f7415c980f0a69e7d2e0c9962c0dde';

  static String _deviceId = '';
  static String? _activeKey;
  static int _maxAccounts = 0;
  static int _expiry = 0;

  static String get deviceId => _deviceId;

  /// What the customer copies and sends over. It is just the device id wrapped
  /// up, so you can paste it straight into the issuing tool without asking them
  /// for anything else. Nothing secret is inside — it cannot activate anything
  /// on its own, only a key signed by you can.
  static String get requestCode {
    if (_deviceId.isEmpty) return '';
    final raw = 'otpflow|1|$_deviceId';
    return base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  }

  /// Pulls the device id back out of a request code. Returns '' if it is not one.
  static String deviceIdFromRequest(String code) {
    try {
      var v = code.replaceAll(RegExp(r'\s'), '');
      while (v.length % 4 != 0) {
        v += '=';
      }
      final parts = utf8.decode(base64Url.decode(v)).split('|');
      if (parts.length >= 3 && parts.first == 'otpflow') return parts[2];
    } catch (_) {}
    return '';
  }
  static int get maxAccounts => _maxAccounts;
  static bool get isActive => _maxAccounts > 0;

  static String get expiryLabel {
    if (_expiry == 0) return 'No expiry';
    final d = DateTime.fromMillisecondsSinceEpoch(_expiry * 1000);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Valid till ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// The key currently installed, for showing in Settings.
  static String? get activeKey => _activeKey;

  // ------------------------------------------------------------- device id
  /// Stable per phone. Android's `id` changes on factory reset and on a
  /// different signing key, which is exactly the granularity a licence wants.
  static Future<String> loadDeviceId() async {
    if (_deviceId.isNotEmpty) return _deviceId;
    var raw = 'unknown';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      raw = '${info.id}|${info.fingerprint}|${info.model}|${info.device}';
    } catch (_) {}
    final digest = sha256.convert(utf8.encode(raw)).toString();
    final body = digest.substring(0, 10);
    final tail = digest.substring(10, 14);
    _deviceId = 'android_$body-$tail';
    return _deviceId;
  }

  // -------------------------------------------------------------- lifecycle
  /// Reads and re-verifies the saved key. Verification happens on every start,
  /// so a key that was edited on disk stops working.
  static Future<void> load() async {
    await loadDeviceId();
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kKey);
    if (saved == null) return;
    final result = verify(saved);
    if (result.ok) {
      _activeKey = saved;
      _maxAccounts = result.maxAccounts;
      _expiry = result.expiry;
    }
  }

  /// Checks a key and, if good, saves it.
  static Future<LicenseCheck> activate(String key) async {
    final result = verify(key.trim());
    if (!result.ok) return result;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, key.trim());
    _activeKey = key.trim();
    _maxAccounts = result.maxAccounts;
    _expiry = result.expiry;
    return result;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    _activeKey = null;
    _maxAccounts = 0;
    _expiry = 0;
  }

  // ----------------------------------------------------------- verification
  static LicenseCheck verify(String key) {
    final clean = key.replaceAll(RegExp(r'\s'), '');
    if (clean.isEmpty) return LicenseCheck.bad('Enter a license key');

    final parts = clean.split('.');
    if (parts.length != 2) return LicenseCheck.bad('That does not look like a license key');

    Map<String, dynamic> payload;
    List<int> payloadBytes;
    List<int> sig;
    try {
      payloadBytes = _b64dec(parts[0]);
      sig = _b64dec(parts[1]);
      payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
    } catch (_) {
      return LicenseCheck.bad('This key is damaged - check for a missing character');
    }

    try {
      final pub = ed.PublicKey(Uint8List.fromList(_hexDec(publicKeyHex)));
      if (!ed.verify(pub, Uint8List.fromList(payloadBytes), Uint8List.fromList(sig))) {
        return LicenseCheck.bad('This key was not issued for OTP Flow');
      }
    } catch (_) {
      return LicenseCheck.bad('This key could not be checked');
    }

    final forDevice = '${payload['d'] ?? ''}';
    if (forDevice != _deviceId) {
      return LicenseCheck.bad('This key belongs to a different device');
    }

    final exp = (payload['exp'] is int) ? payload['exp'] as int : 0;
    if (exp != 0 && DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp) {
      return LicenseCheck.bad('This key has expired');
    }

    final n = (payload['n'] is int) ? payload['n'] as int : 0;
    if (n <= 0) return LicenseCheck.bad('This key allows no accounts');

    return LicenseCheck(ok: true, maxAccounts: n, expiry: exp);
  }

  // ------------------------------------------------------------- encoding
  static List<int> _b64dec(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    while (v.length % 4 != 0) {
      v += '=';
    }
    return base64.decode(v);
  }

  static List<int> _hexDec(String h) {
    final out = <int>[];
    for (var i = 0; i + 1 < h.length; i += 2) {
      out.add(int.parse(h.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}

/// Result of checking a key.
class LicenseCheck {
  final bool ok;
  final String message;
  final int maxAccounts;
  final int expiry;

  const LicenseCheck({
    required this.ok,
    this.message = '',
    this.maxAccounts = 0,
    this.expiry = 0,
  });

  factory LicenseCheck.bad(String message) => LicenseCheck(ok: false, message: message);
}
