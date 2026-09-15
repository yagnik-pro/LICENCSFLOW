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

  /// Ready-to-ship split by label state. Meesho returns
  /// `label_not_downloaded_count` alongside the total, so both come from the
  /// same request.
  int? rtsLabelPending;
  int? rtsLabelDone;

  /// SKU lines behind each label state. Loaded only when that number is
  /// tapped — they need a bigger page of orders than a count does.
  List<SkuLine> rtsPendingSkus;
  List<SkuLine> rtsDoneSkus;

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
    this.rtsLabelPending,
    this.rtsLabelDone,
    List<SkuLine>? rtsPendingSkus,
    List<SkuLine>? rtsDoneSkus,
    this.fetchedAt,
    this.error,
  })  : payouts = payouts ?? [],
        rtsPendingSkus = rtsPendingSkus ?? [],
        rtsDoneSkus = rtsDoneSkus ?? [];

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
        'rtsLabelPending': rtsLabelPending,
        'rtsLabelDone': rtsLabelDone,
        'rtsPendingSkus': rtsPendingSkus.map((e) => e.toJson()).toList(),
        'rtsDoneSkus': rtsDoneSkus.map((e) => e.toJson()).toList(),
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
        rtsLabelPending: j['rtsLabelPending'] as int?,
        rtsLabelDone: j['rtsLabelDone'] as int?,
        rtsPendingSkus: ((j['rtsPendingSkus'] ?? const []) as List)
            .map((e) => SkuLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        rtsDoneSkus: ((j['rtsDoneSkus'] ?? const []) as List)
            .map((e) => SkuLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
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

/// One SKU line inside an order group.
class SkuLine {
  final String sku;
  final String name;
  final int qty;

  const SkuLine({required this.sku, this.name = '', this.qty = 0});

  Map<String, dynamic> toJson() => {'sku': sku, 'name': name, 'qty': qty};

  factory SkuLine.fromJson(Map<String, dynamic> j) => SkuLine(
        sku: j['sku'] ?? '',
        name: j['name'] ?? '',
        qty: j['qty'] ?? 0,
      );
}

/// One order found by scanning or typing an AWB.
class OrderHit {
  final String accountName;
  final String image;
  final String sku;
  final String productName;
  final String subOrderNum;
  final String awb;
  final String slaStatus;
  final String label;
  final int qty;

  const OrderHit({
    this.accountName = '',
    this.image = '',
    this.sku = '',
    this.productName = '',
    this.subOrderNum = '',
    this.awb = '',
    this.slaStatus = '',
    this.label = '',
    this.qty = 0,
  });
}
