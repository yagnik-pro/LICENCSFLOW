import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../models/summary.dart';
import '../widgets/brand.dart';

/// Upcoming payouts, account by account.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => store.loadSummaries());
  }

  String _money(num? v) {
    if (v == null) return '—';
    final s = v.round().toString();
    final buf = StringBuffer();
    final rev = s.split('').reversed.toList();
    for (var i = 0; i < rev.length; i++) {
      if (i == 3 || (i > 3 && (i - 3) % 2 == 0)) buf.write(',');
      buf.write(rev[i]);
    }
    return '₹${buf.toString().split('').reversed.join()}';
  }

  /// Meesho calls these "Unscheduled Payouts" — the breakdown that sits under
  /// the seven-day figure.
  Widget _payoutList(List<PayoutRow> rows) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.skyLine, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Unscheduled Payouts',
              style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink2)),
          const SizedBox(height: 8),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.label,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (r.date != null)
                            Text(r.date!,
                                style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
                        ],
                      ),
                    ),
                    Text(
                      _money(r.amount),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: (r.amount ?? 0) < 0 ? AppColors.danger : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final accounts = store.accounts;
        final total = store.totalUpcomingPayment;

        return Column(
          children: [
            FlowHeader(
              title: 'Payments',
              subtitle: total == 0
                  ? '${accounts.length} account(s)'
                  : '${accounts.length} account(s) · ${_money(total)} in 7 days',
              actions: [
                IconButton(
                  tooltip: 'Reload',
                  onPressed: store.busy ? null : () => store.loadSummaries(force: true),
                  icon: store.busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              ],
            ),
            Expanded(
              child: accounts.isEmpty
                  ? const SingleChildScrollView(
                      child: FlowEmpty(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'No accounts yet',
                        body: 'Add a seller account to see what Meesho owes you.',
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.blue,
                      onRefresh: () => store.loadSummaries(force: true),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        children: [
                          FlowCard(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                const Text('Next 7 Days Payouts',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.ink2,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                FittedBox(
                                  child: Text(
                                    _money(total == 0 ? null : total),
                                    style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...accounts.map((a) {
                            final s = a.summary;
                            return FlowCard(
                              child: Column(
                                children: [
                                  Padding(
                                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.sky,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: const Icon(Icons.account_balance_wallet_rounded,
                                          size: 20, color: AppColors.blueDeep),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text.rich(
                                            TextSpan(children: [
                                              TextSpan(
                                                text: a.name,
                                                style: const TextStyle(
                                                    fontSize: 15.5, fontWeight: FontWeight.w800),
                                              ),
                                              if (a.phone.isNotEmpty)
                                                TextSpan(
                                                  text: '  (${a.phone})',
                                                  style: const TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.ink2),
                                                ),
                                            ]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (s.nextPaymentDate != null)
                                            Text('Next: ${s.nextPaymentDate}',
                                                style: const TextStyle(
                                                    fontSize: 11.8, color: AppColors.ink2)),
                                          if (s.error != null)
                                            Text(s.error!,
                                                style: const TextStyle(
                                                    fontSize: 11.5,
                                                    color: AppColors.danger,
                                                    fontWeight: FontWeight.w600),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      s.headerAmount ?? _money(s.upcomingPayment),
                                      style: const TextStyle(
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.blueDeep),
                                    ),
                                  ],
                                ),
                              ),
                                  if (s.payouts.isNotEmpty) _payoutList(s.payouts),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          const Text(
                            'Amounts come straight from your Meesho payouts page. If one shows a '
                            'dash, Meesho did not return a figure for that account.',
                            style: TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.4),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
