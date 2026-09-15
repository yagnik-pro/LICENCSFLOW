import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets/brand.dart';

/// Totals across every account, then a card per account.
///
/// Figures load when this tab is opened rather than on every OTP refresh —
/// Meesho rate-limits, and the extra calls are not worth a throttle.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _money(num? v) {
    if (v == null) return '—';
    final s = v.round().toString();
    // Indian grouping: 12,34,567
    final buf = StringBuffer();
    final rev = s.split('').reversed.toList();
    for (var i = 0; i < rev.length; i++) {
      if (i == 3 || (i > 3 && (i - 3) % 2 == 0)) buf.write(',');
      buf.write(rev[i]);
    }
    return '₹${buf.toString().split('').reversed.join()}';
  }

  String _count(int? v) => v == null ? '—' : '$v';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final accounts = store.accounts;

        return Column(
          children: [
            FlowHeader(
              title: 'Dashboard',
              subtitle: '${accounts.length} account(s)',
              actions: [
                IconButton(
                  tooltip: 'Reload figures',
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
                        icon: Icons.insights_outlined,
                        title: 'Nothing to show yet',
                        body: 'Add a seller account and the figures will appear here.',
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.blue,
                      onRefresh: () => store.loadSummaries(force: true),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        children: [
                          if (!store.accounts.any((a) => a.summary.fetchedAt != null))
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: AppColors.sky,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.download_rounded,
                                      size: 18, color: AppColors.blueDeep),
                                  const SizedBox(width: 9),
                                  const Expanded(
                                    child: Text(
                                      'Figures are not loaded yet. Tap refresh to fetch them.',
                                      style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: _bigTile(
                                  'Next 7 days',
                                  _money(store.totalUpcomingPayment == 0 ? null : store.totalUpcomingPayment),
                                  Icons.account_balance_wallet_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _bigTile(
                                  'Returns pending',
                                  '${store.totalReturns}',
                                  Icons.assignment_return_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _bigTile(
                                  'OTPs waiting',
                                  '${store.totalOtps}',
                                  Icons.vpn_key_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _bigTile(
                                  'Accounts',
                                  '${store.accounts.length}',
                                  Icons.storefront_outlined,
                                ),
                              ),
                            ],
                          ),
                          if (store.hasOrderCounts) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _bigTile('Pending',
                                      _count(store.totalPendingOrders), Icons.inventory_2_outlined),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _bigTile('Ready to ship',
                                      _count(store.totalReadyToShip), Icons.local_shipping_outlined),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          const Text('By account',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          ...accounts.map((a) {
                            final s = a.summary;
                            return FlowCard(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
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
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.ink2),
                                          ),
                                      ]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _miniStat('Payment',
                                            s.headerAmount ?? _money(s.upcomingPayment)),
                                        _miniStat('Returns', '${a.totalReturns}'),
                                        _miniStat('OTPs', '${a.otps.length}'),
                                        if (s.pendingOrders != null)
                                          _miniStat('Pending', _count(s.pendingOrders)),
                                        if (s.readyToShip != null)
                                          _miniStat('Ready', _count(s.readyToShip)),
                                        if (s.readyToShip != null)
                                          _miniStat('Ready', _count(s.readyToShip)),
                                        if (s.onHold != null)
                                          _miniStat('On hold', _count(s.onHold)),
                                      ],
                                    ),
                                    if (s.ordersNote != null) ...[
                                      const SizedBox(height: 8),
                                      Text(s.ordersNote!,
                                          style: const TextStyle(
                                              fontSize: 11.5, color: AppColors.ink2)),
                                    ],
                                    if (s.error != null) ...[
                                      const SizedBox(height: 8),
                                      Text(s.error!,
                                          style: const TextStyle(
                                              fontSize: 11.8,
                                              color: AppColors.danger,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          const Text(
                            'Figures refresh when you open this tab, and no more than once every '
                            'ten minutes. Pull down to force a reload.',
                            style: TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.4),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'The first load opens your Orders page once to learn how Meesho asks '
                            'for order counts. After that it is a plain API call.',
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

  /// Whatever Meesho said about order counts, rather than a generic line —
  /// that text is what tells us which key to read next.
  String _ordersNote() {
    for (final a in store.accounts) {
      final n = a.summary.ordersNote;
      if (n != null && n.isNotEmpty) return n;
    }
    return 'Order counts show up once Meesho returns them.';
  }

  Widget _bigTile(String label, String value, IconData icon) {
    return FlowCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.blue),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy)),
          ),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.ink2, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.ink2, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
