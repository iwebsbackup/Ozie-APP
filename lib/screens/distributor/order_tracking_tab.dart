import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'distributor_order_models.dart';
import 'distributor_service.dart';
import 'distributor_widgets.dart';
import 'order_detail_screen.dart';

/// Distributor -> Dispatch tab: approved + dispatched order tracker.
/// Filter chips (All / Approved / Dispatched) with counts, search, date range,
/// infinite scroll. Tap an order for full detail.
class OrderTrackingTab extends StatefulWidget {
  final String initialTab;
  const OrderTrackingTab({super.key, this.initialTab = 'all'});

  @override
  State<OrderTrackingTab> createState() => OrderTrackingTabState();
}

class OrderTrackingTabState extends State<OrderTrackingTab> {
  static const _limit = 15;

  final _search = TextEditingController();
  final _scroll = ScrollController();

  final List<TrackedOrder> _items = [];
  int _page = 1;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String _tab = 'all';
  String _query = '';
  DateTimeRange? _range;
  int _cAll = 0, _cApproved = 0, _cDispatched = 0;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Called by the shell (switch filter chip from Home cards).
  void setTab(String tab) {
    if (tab == _tab) {
      _load(silent: true);
      return;
    }
    setState(() => _tab = tab);
    _load();
  }

  /// Called by the shell when the tab is opened again.
  void refresh() => _load(silent: true);

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load({bool silent = false}) async {
    final gen = ++_gen;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await DistributorService.getOrderTracking(
        tab: _tab,
        page: 1,
        limit: _limit,
        search: _query,
        start: _range?.start,
        end: _range?.end,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.orders);
        _cAll = r.all;
        _cApproved = r.approved;
        _cDispatched = r.dispatched;
        _page = 1;
        _hasNext = r.page.hasNext;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _gen) return;
      if (silent && _items.isNotEmpty) return; // keep old data on silent fail
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final r = await DistributorService.getOrderTracking(
        tab: _tab,
        page: _page + 1,
        limit: _limit,
        search: _query,
        start: _range?.start,
        end: _range?.end,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        final have = _items.map((e) => e.orderId).toSet();
        _items.addAll(r.orders.where((e) => !have.contains(e.orderId)));
        _page = _page + 1;
        _hasNext = r.page.hasNext;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _loadingMore = false);
      showStatus(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: OrderFilterBar(
          controller: _search,
          hint: 'Invoice, retailer or city',
          range: _range,
          onSearch: (q) {
            _query = q.trim();
            _load();
          },
          onRange: (r) {
            _range = r;
            _load();
          },
        ),
      ),
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip('all', 'All', _cAll),
            _chip('approved', 'Approved', _cApproved),
            _chip('dispatched', 'Dispatched', _cDispatched),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(child: _body()),
    ]);
  }

  Widget _chip(String key, String label, int count) {
    final sel = _tab == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: sel,
        showCheckmark: false,
        onSelected: (_) {
          if (sel) return;
          setState(() => _tab = key);
          _load();
        },
        selectedColor: AppColors.blue,
        backgroundColor: AppColors.card,
        side: BorderSide(color: sel ? AppColors.blue : AppColors.border),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: sel ? Colors.white : AppColors.text,
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EmptyView(
                    icon: Icons.local_shipping_outlined,
                    text: 'No orders found.'),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _items.length + 1,
              itemBuilder: (_, i) {
                if (i == _items.length) {
                  return _loadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))),
                        )
                      : const SizedBox.shrink();
                }
                return _card(_items[i]);
              },
            ),
    );
  }

  Widget _card(TrackedOrder o) {
    final sc = stageColor(o.stageStep);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => OrderDetailScreen(id: o.orderId, isPo: false)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(o.invoiceNumber,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              StatusPill(label: o.stageLabel, color: sc),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.storefront_outlined,
                  size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  o.city.isEmpty || o.city == 'N/A'
                      ? o.retailerName
                      : '${o.retailerName} · ${o.city}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
            ]),
            if (o.salesmanName != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.badge_outlined,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Salesman: ${o.salesmanName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            _StageBar(step: o.stageStep, color: sc),
            const SizedBox(height: 12),
            Row(children: [
              Text(formatInr(o.totalAmount),
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue)),
              const Spacer(),
              StatusPill(
                  label: o.paymentLabel, color: paymentColor(o.paymentColor)),
            ]),
            const SizedBox(height: 8),
            Text(
              o.dispatchDate != null
                  ? 'Ordered ${o.orderDate}  ·  Dispatched ${o.dispatchDate}'
                  : 'Ordered ${o.orderDate}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 4-step progress bar: Pending > Processing > Dispatched > Delivered.
class _StageBar extends StatelessWidget {
  final int step;
  final Color color;
  const _StageBar({required this.step, required this.color});

  static const _labels = ['Pending', 'Processing', 'Dispatched', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        for (var i = 1; i <= 4; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? color : AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (i < 4) const SizedBox(width: 4),
        ],
      ]),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Text(
              _labels[i],
              textAlign: i == 0
                  ? TextAlign.left
                  : i == 3
                      ? TextAlign.right
                      : TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: (i + 1) == step ? FontWeight.w700 : FontWeight.w400,
                color: (i + 1) <= step ? color : AppColors.muted,
              ),
            ),
          ),
      ]),
    ]);
  }
}