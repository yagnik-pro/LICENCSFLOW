// OTP Flow — license key generator.
//
// You hold the private key; the app only ships the public half. That is what
// stops anyone from minting keys by decompiling the APK.
//
//   One-time, create your keypair:
//     dart pub get
//     dart run tool/keygen.dart genkeys
//
//   Put the printed PUBLIC key into lib/services/license.dart (publicKeyHex)
//   and keep the PRIVATE key somewhere safe — a GitHub Actions secret named
//   LICENSE_PRIVATE_KEY works well.
//
//   Issue a key for a customer:
//     dart run tool/keygen.dart sign --device android_abc123-4567 --accounts 5
//     dart run tool/keygen.dart sign --device ... --accounts 5 --days 365
//
// The device id is inside the signed payload, so a key pasted into a second
// phone is rejected: the id will not match and the signature cannot be redone.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

void main(List<String> args) {
  if (args.isEmpty) {
    _usage();
    exit(1);
  }

  switch (args.first) {
    case 'genkeys':
      _genkeys();
      break;
    case 'sign':
      _sign(args.sublist(1));
      break;
    default:
      _usage();
      exit(1);
  }
}

void _usage() {
  stdout.writeln('''
OTP Flow license tool

  dart run tool/keygen.dart genkeys
  dart run tool/keygen.dart sign --device <deviceId> --accounts <n> [--days <n>] [--key <privateHex>]

--key may be omitted if LICENSE_PRIVATE_KEY is set in the environment.
''');
}

void _genkeys() {
  final pair = ed.generateKey();
  stdout.writeln('PRIVATE KEY (keep secret, never ship this):');
  stdout.writeln(_hex(pair.privateKey.bytes));
  stdout.writeln('');
  stdout.writeln('PUBLIC KEY (paste into lib/services/license.dart):');
  stdout.writeln(_hex(pair.publicKey.bytes));
}

void _sign(List<String> args) {
  final opts = _parse(args);
  final device = opts['device'];
  final accounts = int.tryParse(opts['accounts'] ?? '');
  final days = int.tryParse(opts['days'] ?? '0') ?? 0;
  final privHex = opts['key'] ?? Platform.environment['LICENSE_PRIVATE_KEY'] ?? '';

  if (device == null || device.isEmpty) {
    stderr.writeln('Missing --device');
    exit(1);
  }
  if (accounts == null || accounts <= 0) {
    stderr.writeln('Missing or invalid --accounts');
    exit(1);
  }
  if (privHex.isEmpty) {
    stderr.writeln('No private key. Pass --key or set LICENSE_PRIVATE_KEY.');
    exit(1);
  }

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final payload = <String, dynamic>{
    'd': device,
    'n': accounts,
    'exp': days > 0 ? now + days * 86400 : 0,
    'iat': now,
  };

  final payloadBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  final priv = ed.PrivateKey(Uint8List.fromList(_unhex(privHex)));
  final sig = ed.sign(priv, payloadBytes);

  final key = '${_b64(payloadBytes)}.${_b64(sig)}';

  stdout.writeln('Device    : $device');
  stdout.writeln('Accounts  : $accounts');
  stdout.writeln('Expires   : ${days > 0 ? 'in $days day(s)' : 'never'}');
  stdout.writeln('');
  stdout.writeln('LICENSE KEY:');
  stdout.writeln(key);
}

Map<String, String> _parse(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final name = a.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[name] = args[i + 1];
      i++;
    } else {
      out[name] = 'true';
    }
  }
  return out;
}

String _b64(List<int> bytes) =>
    base64.encode(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String h) {
  final clean = h.replaceAll(RegExp(r'\s'), '');
  final out = <int>[];
  for (var i = 0; i + 1 < clean.length; i += 2) {
    out.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }
  return out;
}
