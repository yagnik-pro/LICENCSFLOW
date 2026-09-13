import 'otp_entry.dart';

enum AccStatus { idle, working, ok, needsLogin, error }

class Account {
  String id;
  String email;
  String password;
  String name;          // shown in lists
  bool autoName;        // name came from Meesho, overwrite on refresh
  String supplierId;

  /// Registered mobile, shown beside the store name the way the panel does.
  String phone;
  String identifier;

  /// Consecutive quick-route failures. A few in a row and this account falls
  /// back to the page route until it succeeds again.
  int apiFailures;
  String token;
  List<Map<String, String>> cookies;
  Map<String, String> storage;

  // runtime / cached
  AccStatus status;
  String? lastError;
  int? lastLogin;
  int? fetchedAt;
  List<OtpEntry> otps;
  num? upcomingPayment;

  Account({
    required this.id,
    required this.email,
    required this.password,
    String? name,
    this.autoName = true,
    this.supplierId = '',
    this.phone = '',
    this.identifier = '',
    this.apiFailures = 0,
    this.token = '',
    List<Map<String, String>>? cookies,
    Map<String, String>? storage,
    this.status = AccStatus.idle,
    this.lastError,
    this.lastLogin,
    this.fetchedAt,
    List<OtpEntry>? otps,
    this.upcomingPayment,
  })  : name = name ?? email.split('@').first,
        cookies = cookies ?? [],
        storage = storage ?? {},
        otps = otps ?? [];

  int get totalReturns => otps.fold(0, (s, o) => s + o.count);

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'password': password,
        'name': name,
        'autoName': autoName,
        'supplierId': supplierId,
        'phone': phone,
        'identifier': identifier,
        'token': token,
        'cookies': cookies,
        'storage': storage,
        'lastLogin': lastLogin,
        'fetchedAt': fetchedAt,
        'otps': otps.map((o) => o.toJson()).toList(),
        'upcomingPayment': upcomingPayment,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'],
        email: j['email'] ?? '',
        password: j['password'] ?? '',
        name: j['name'],
        autoName: j['autoName'] ?? true,
        supplierId: j['supplierId'] ?? '',
        phone: j['phone'] ?? '',
        identifier: j['identifier'] ?? '',
        token: j['token'] ?? '',
        cookies: ((j['cookies'] ?? []) as List)
            .map((c) => Map<String, String>.from(c as Map))
            .toList(),
        storage: Map<String, String>.from(
            (j['storage'] ?? const <String, String>{}) as Map),
        lastLogin: j['lastLogin'],
        fetchedAt: j['fetchedAt'],
        otps: ((j['otps'] ?? []) as List).map((o) => OtpEntry.fromJson(Map<String, dynamic>.from(o))).toList(),
        upcomingPayment: j['upcomingPayment'],
      );
}

class CarrierGroup {
  final String carrier;
  int total = 0;
  final List<CarrierRow> rows = [];
  CarrierGroup(this.carrier);
}

class CarrierRow {
  final String accountId, accountName, otp, time;
  final int count;
  CarrierRow({
    required this.accountId,
    required this.accountName,
    required this.otp,
    required this.count,
    required this.time,
  });
}
