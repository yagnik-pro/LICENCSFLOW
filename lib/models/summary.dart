/// What the Dashboard and Payments tabs show for one seller account.
///
/// Everything is optional: Meesho's responses differ between accounts and
/// change shape now and then, so a field we could not read stays null and the
/// UI simply leaves it out rather than showing a wrong zero.
class AccountSummary {
  num? upcomingPayment;

  /// Meesho's own rounded label, e.g. "₹59.62K".
  String? headerAmount;
  String? nextPaymentDate;
  num? lastPayment;

  /// "Unscheduled Payouts" from Meesho's all-ui-data call.
  num? unscheduledPayout;
  List<PayoutRow> payouts;

  int? pendingOrders;
  int? readyToShip;
  int? onHold;

  /// Why an order count is missing, when it is.
  String? ordersNote;

  int? fetchedAt;
  String? error;

  AccountSummary({
    this.upcomingPayment,
    this.headerAmount,
    this.nextPaymentDate,
    this.lastPayment,
    this.unscheduledPayout,
    List<PayoutRow>? payouts,
    this.pendingOrders,
    this.readyToShip,
    this.onHold,
    this.fetchedAt,
    this.error,
  }) : payouts = payouts ?? [];

  bool get hasAnything =>
      upcomingPayment != null ||
      pendingOrders != null ||
      readyToShip != null ||
      lastPayment != null;

  Map<String, dynamic> toJson() => {
        'upcomingPayment': upcomingPayment,
        'headerAmount': headerAmount,
        'nextPaymentDate': nextPaymentDate,
        'lastPayment': lastPayment,
        'unscheduledPayout': unscheduledPayout,
        'payouts': payouts.map((p) => p.toJson()).toList(),
        'pendingOrders': pendingOrders,
        'readyToShip': readyToShip,
        'onHold': onHold,
        'fetchedAt': fetchedAt,
      };

  factory AccountSummary.fromJson(Map<String, dynamic> j) => AccountSummary(
        upcomingPayment: j['upcomingPayment'] as num?,
        headerAmount: j['headerAmount'] as String?,
        nextPaymentDate: j['nextPaymentDate'] as String?,
        lastPayment: j['lastPayment'] as num?,
        unscheduledPayout: j['unscheduledPayout'] as num?,
        payouts: ((j['payouts'] ?? const []) as List)
            .map((p) => PayoutRow.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
        pendingOrders: j['pendingOrders'] as int?,
        readyToShip: j['readyToShip'] as int?,
        onHold: j['onHold'] as int?,
        fetchedAt: j['fetchedAt'] as int?,
      );
}

/// One line in the Unscheduled Payouts list.
class PayoutRow {
  final String label;
  final num? amount;
  final String? date;

  const PayoutRow({required this.label, this.amount, this.date});

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount, 'date': date};

  factory PayoutRow.fromJson(Map<String, dynamic> j) => PayoutRow(
        label: j['label'] ?? '',
        amount: j['amount'] as num?,
        date: j['date'] as String?,
      );
}
