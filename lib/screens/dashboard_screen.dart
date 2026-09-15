import 'package:flutter/material.dart';

import '../main.dart';
import '../models/account.dart';
import '../theme.dart';
import '../widgets/brand.dart';

/// Orders grouped the way the panel groups them: On Hold, Pending, Ready to
/// Ship. Each section shows a total, expands to per-account rows, and has its
/// own refresh. Payments live in their own tab.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _open = <String>{'pending'};

  /// Which ready-to-ship account row is expanded, and which label state inside
  /// it is showing its SKUs.
  String? _openRts;
  bool? _skuMode;

  String _count(int? v) => v == null ? '—' : '$v';

  String _ago(int? ms) {
    if (ms == null) return 'not loaded';
    final m = ((DateTime.now().millisecondsSinceEpoch - ms) / 60000).round();
    if (m <= 0) return 'just now';
    if (m < 60) return '$m min ago';
    return '${(m / 60).floor()} hr ago';
  }

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
                  tooltip: 'Reload everything',
                  onPressed: store.busy ? null : () => store.loadSummaries(force: true),
                  icon: store.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
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
                        body: 'Add a seller account and your order figures appear here.',
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.blue,
                      onRefresh: () => store.loadSummaries(force: true),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        children: [
                          if (!accounts.any((a) => a.summary.fetchedAt != null))
                            _hint('Figures are not loaded yet. Tap refresh above.'),
                          _section(
                            id: 'hold',
                            title: 'On Hold',
                            icon: Icons.pause_circle_outline,
                            colour: AppColors.warn,
                            total: store.totalOnHold,
                            valueOf: (a) => a.summary.onHold,
                          ),
                          _section(
                            id: 'pending',
                            title: 'Pending Orders',
                            icon: Icons.more_horiz_rounded,
                            colour: AppColors.mint,
                            total: store.totalPendingOrders,
                            valueOf: (a) => a.summary.pendingOrders,
                          ),
                          _section(
                            id: 'rts',
                            title: 'Ready to Ship',
                            icon: Icons.outbox_rounded,
                            colour: AppColors.blue,
                            total: store.totalReadyToShip,
                            valueOf: (a) => a.summary.readyToShip,
                            extra: _labelTotals(),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Counts come from the same API the panel uses. Tap a section to see '
                            'it account by account.',
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

  Widget _hint(String text) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.download_rounded, size: 18, color: AppColors.blueDeep),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.ink2))),
          ],
        ),
      );

  Widget _section({
    required String id,
    required String title,
    required IconData icon,
    required Color colour,
    required int total,
    required int? Function(Account) valueOf,
    Widget? extra,
  }) {
    final open = _open.contains(id);
    final loaded = store.accounts.any((a) => valueOf(a) != null);

    return FlowCard(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => open ? _open.remove(id) : _open.add(id)),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colour.withOpacity(.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: colour),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                        Text(
                          loaded ? 'Total: $total' : 'Not loaded',
                          style: const TextStyle(
                              fontSize: 12.3, color: AppColors.ink2, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh $title',
                    visualDensity: VisualDensity.compact,
                    onPressed: store.busy ? null : () => store.loadSummaries(force: true),
                    icon: Icon(Icons.refresh_rounded, size: 20, color: colour),
                  ),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: AppColors.ink2),
                ],
              ),
            ),
          ),
          if (open) ...[
            ...store.accounts.map((a) => id == 'rts'
                ? _rtsAccountRow(a, colour)
                : _accountRow(a, valueOf(a), colour)),
            if (extra != null) extra,
          ],
        ],
      ),
    );
  }

  /// Store name, number, email and when it was last read — shared by every row.
  Widget _accountLabel(Account a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: a.name,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            if (a.phone.isNotEmpty)
              TextSpan(
                text: '  (${a.phone})',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2),
              ),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(a.email,
            style: const TextStyle(fontSize: 11.5, color: AppColors.ink2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text('Ref: ${_ago(a.summary.fetchedAt)}',
            style: const TextStyle(fontSize: 10.5, color: AppColors.ink2)),
      ],
    );
  }

  Widget _accountRow(Account a, int? value, Color colour) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.skyLine, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Expanded(child: _accountLabel(a)),
          const SizedBox(width: 8),
          Text(_count(value),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colour)),
          IconButton(
            tooltip: 'Refresh ${a.name}',
            visualDensity: VisualDensity.compact,
            onPressed: store.busy ? null : () => store.refreshSummaryFor(a),
            icon: Icon(Icons.refresh_rounded, size: 18, color: colour),
          ),
        ],
      ),
    );
  }

  /// Ready-to-ship totals for every account, so the section footer still says
  /// what the whole business looks like.
  Widget _labelTotals() {
    final pending = store.totalLabelPending;
    final done = store.totalLabelDone;
    if (pending == 0 && done == 0) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.skyLine, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.blue),
          const SizedBox(width: 9),
          const Expanded(
            child: Text('All accounts',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          _chip('Downloaded', done, AppColors.mint),
          const SizedBox(width: 16),
          _chip('Not downloaded', pending, AppColors.warn),
        ],
      ),
    );
  }

  /// A ready-to-ship row that opens into its own label split, and from there
  /// into the SKUs behind either figure.
  Widget _rtsAccountRow(Account a, Color colour) {
    final open = _openRts == a.id;
    final s = a.summary;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.skyLine, width: 1)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _openRts = open ? null : a.id;
              _skuMode = null;
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Expanded(child: _accountLabel(a)),
                  const SizedBox(width: 8),
                  Text(_count(s.readyToShip),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colour)),
                  IconButton(
                    tooltip: 'Refresh ${a.name}',
                    visualDensity: VisualDensity.compact,
                    onPressed: store.busy ? null : () => store.refreshSummaryFor(a),
                    icon: Icon(Icons.refresh_rounded, size: 18, color: colour),
                  ),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 20, color: AppColors.ink2),
                ],
              ),
            ),
          ),
          if (open) _labelPicker(a),
        ],
      ),
    );
  }

  Widget _labelPicker(Account a) {
    final s = a.summary;
    final done = s.rtsLabelDone ?? 0;
    final pending = s.rtsLabelPending ?? 0;

    return Container(
      color: AppColors.paper,
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _labelButton(a, 'Downloaded', done, AppColors.mint, true)),
              const SizedBox(width: 10),
              Expanded(child: _labelButton(a, 'Not downloaded', pending, AppColors.warn, false)),
            ],
          ),
          if (_skuMode != null && _openRts == a.id) ...[
            const SizedBox(height: 12),
            _skuTable(a, _skuMode!),
          ],
        ],
      ),
    );
  }

  Widget _labelButton(Account a, String label, int value, Color colour, bool downloaded) {
    final active = _openRts == a.id && _skuMode == downloaded;
    return InkWell(
      onTap: value == 0
          ? null
          : () async {
              final want = active ? null : downloaded;
              setState(() => _skuMode = want);
              if (want == null) return;
              final have = downloaded ? a.summary.rtsDoneSkus : a.summary.rtsPendingSkus;
              if (have.isEmpty) await store.loadRtsSkus(a, downloaded: downloaded);
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? colour.withOpacity(.14) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? colour : AppColors.skyLine, width: 1.4),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colour)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.ink2, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _skuTable(Account a, bool downloaded) {
    final skus = downloaded ? a.summary.rtsDoneSkus : a.summary.rtsPendingSkus;

    if (skus.isEmpty) {
      return Text(
        store.busy ? 'Reading SKUs…' : (a.summary.ordersNote ?? 'No SKU lines found'),
        style: const TextStyle(fontSize: 12, color: AppColors.ink2),
      );
    }

    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: Text('SKU',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink2)),
            ),
            Text('Qty',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink2)),
          ],
        ),
        const SizedBox(height: 4),
        ...skus.map((k) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(k.sku,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (k.name.isNotEmpty)
                          Text(k.name,
                              style: const TextStyle(fontSize: 10.5, color: AppColors.ink2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text('${k.qty}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _chip(String label, int value, Color colour) => Column(
        children: [
          Text('$value',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colour)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.ink2, fontWeight: FontWeight.w600)),
        ],
      );
}
