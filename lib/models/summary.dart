/// What the Dashboard and Payments tabs show for one seller account.
///
/// Everything is optional: Meesho's responses differ between accounts and
/// change shape now and then, so a field we could not read stays null and the
/// UI simply leaves it out rather than showing a wrong zero.
class AccountSummary {
  num? upcomingPayment;
  String? nextPaymentDate;
  num? lastPayment;

  int? pendingOrders;
  int? readyToShip;

  int? fetchedAt;
  String? error;

  AccountSummary({
    this.upcomingPayment,
    this.nextPaymentDate,
    this.lastPayment,
    this.pendingOrders,
    this.readyToShip,
    this.fetchedAt,
    this.error,
  });

  bool get hasAnything =>
      upcomingPayment != null ||
      pendingOrders != null ||
      readyToShip != null ||
      lastPayment != null;

  Map<String, dynamic> toJson() => {
        'upcomingPayment': upcomingPayment,
        'nextPaymentDate': nextPaymentDate,
        'lastPayment': lastPayment,
        'pendingOrders': pendingOrders,
        'readyToShip': readyToShip,
        'fetchedAt': fetchedAt,
      };

  factory AccountSummary.fromJson(Map<String, dynamic> j) => AccountSummary(
        upcomingPayment: j['upcomingPayment'] as num?,
        nextPaymentDate: j['nextPaymentDate'] as String?,
        lastPayment: j['lastPayment'] as num?,
        pendingOrders: j['pendingOrders'] as int?,
        readyToShip: j['readyToShip'] as int?,
        fetchedAt: j['fetchedAt'] as int?,
      );
}
