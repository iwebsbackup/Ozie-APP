import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'distributor_order_models.dart';
import 'distributor_service.dart';
import 'distributor_widgets.dart';
import 'order_detail_screen.dart';

/// Distributor -> Pending purchase orders (review queue).
/// Search, date filter, infinite scroll, approve / reject, tap for detail.
class PendingOrdersScreen extends StatefulWidget {
  const PendingOrdersScreen({super.key});

  @override
  State<PendingOrdersScreen> createState() => _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends State<PendingOrdersScreen> {
  static const _limit = 15;

  final _search = TextEditingController();
  final _scroll = ScrollController();

  final List<PendingPo> _items = [];
  int _total = 0;
  int _page = 1;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String _query = '';
  DateTimeRange? _range;

  /// bumped on every fresh load so stale responses are ignored
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
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
      final r = await DistributorService.getPendingOrders(
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
        _total = r.totalPending;
        _page = 1;
        _hasNext = r.page.hasNext;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _gen) return;
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
      final r = await DistributorService.getPendingOrders(
        page: _page + 1,
        limit: _limit,
        search: _query,
        start: _range?.start,
        end: _range?.end,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        final have = _items.map((e) => e.poId).toSet();
        _items.addAll(r.orders.where((e) => !have.contains(e.poId)));
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

  void _removeLocal(int poId) {
    setState(() {
      _items.removeWhere((e) => e.poId == poId);
      if (_total > 0) _total--;
    });
  }

  Future<void> _act(PendingPo po, bool approve) async {
    final r = await runPoAction(context,
        poId: po.poId, poNumber: po.poNumber, approve: approve);
    if (!mounted) return;
    if (r == 'approved' || r == 'rejected') {
      _removeLocal(po.poId);
      _changed = true;
    } else if (r == 'conflict') {
      _load(silent: true); // someone else already handled it
      _changed = true;
    }
  }

  bool _changed = false;

  Future<void> _openDetail(PendingPo po) async {
    final r = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => OrderDetailScreen(id: po.poId, isPo: true),
      ),
    );
    if (!mounted) return;
    if (r == 'approved' || r == 'rejected') {
      _removeLocal(po.poId);
      _changed = true;
    } else if (r == 'conflict') {
      _load(silent: true);
      _changed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Pending Orders'),
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: OrderFilterBar(
              controller: _search,
              hint: 'PO number, retailer or mobile',
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
          Expanded(child: _body()),
        ]),
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
                    icon: Icons.inbox_outlined,
                    text: 'No pending purchase orders.'),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _items.length + 2,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('$_total pending',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted)),
                  );
                }
                if (i == _items.length + 1) {
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
                return _card(_items[i - 1]);
              },
            ),
    );
  }

  Widget _card(PendingPo po) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          onTap: () => _openDetail(po),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(po.poNumber,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                ),
                const StatusPill(label: 'Pending', color: kAmber),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.storefront_outlined,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    po.retailerCity.isEmpty
                        ? po.retailerName
                        : '${po.retailerName} · ${po.retailerCity}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.schedule, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(po.formattedDate,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                ),
                Text('${po.itemCount} item${po.itemCount == 1 ? '' : 's'}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
              const SizedBox(height: 10),
              Text(formatInr(po.totalAmount),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue)),
            ]),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _act(po, false),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dangerText,
                  side: const BorderSide(color: AppColors.dangerText),
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _act(po, true),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Approve'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}