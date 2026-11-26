import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/received_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import 'invoice_view_screen.dart';
import '../widgets/invoice_link.dart';

/// Retailer received orders (delivered history). Search, infinite scroll.
/// Read-only. API: GET v1/retailer/received-history.
class ReceivedScreen extends StatefulWidget {
  const ReceivedScreen({super.key});

  @override
  State<ReceivedScreen> createState() => _ReceivedScreenState();
}

class _ReceivedScreenState extends State<ReceivedScreen> {
  static const int _limit = 15;
  static const Color _header = Color(0xFF059669); // top header (change here)

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<ReceivedOrder> _items = [];
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<ReceivedPage> _fetch(int page) => RetailerService.getReceivedHistory(
        search: _searchCtrl.text.trim(),
        page: page,
        limit: _limit,
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(p.orders);
        _total = p.totalOrders;
        _page = p.page;
        _totalPages = p.totalPages;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    try {
      final p = await _fetch(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(p.orders);
        _page = p.page;
        _totalPages = p.totalPages;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showStatus(context, e.message, error: true);
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _load);
  }

  void _openInvoice(ReceivedOrder o) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceViewScreen(invoiceNumber: o.invoiceNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _header,
      appBar: AppBar(
        title: const Text('Received Orders'),
        backgroundColor: _header,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: Colors.white,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: _header,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: inputDecoration(hint: 'Search invoice, name or city').copyWith(
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.dangerText),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Icon(Icons.move_to_inbox_outlined, size: 56, color: AppColors.muted),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No received orders',
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              itemCount: _items.length + 1 + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, idx) {
                if (idx == 0) return _summary();
                final pos = idx - 1;
                if (pos >= _items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return _card(_items[pos]);
              },
            ),
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _header.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.move_to_inbox_outlined, color: _header, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total received orders',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          Text(
            '$_total',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 13, color: AppColors.successText),
          SizedBox(width: 4),
          Text(
            'Received',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.successText,
            ),
          ),
        ],
      ),
    );
  }

  bool _has(String s) => s.isNotEmpty && s != 'N/A';

  Widget _step(IconData icon, String label, String date) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 18, color: date.isEmpty ? AppColors.border : _header),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(
              date.isEmpty ? '-' : date,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      );

  Widget _timeline(ReceivedOrder o) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _step(Icons.shopping_bag_outlined, 'Ordered', o.orderDate),
            _step(Icons.local_shipping_outlined, 'Dispatched', o.dispatchedDate),
            _step(Icons.check_circle_outline, 'Received', o.receivedDate),
          ],
        ),
      );

  Widget _kv(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );

  Widget _card(ReceivedOrder o) {
    final t = o.tracking;
    final hasLogistics = _has(t.warehouse) || _has(t.carrier) || _has(t.trackingNo);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0F1E2A3B), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () => _openInvoice(o),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: InvoiceLink(
                              o.invoiceNumber,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _header,
                                decoration: TextDecoration.underline,
                                decorationColor: _header,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _badge(),
                  ],
                ),
                if (o.customerName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    o.customerName,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (_has(o.city)) ...[
                  const SizedBox(height: 4),
                  _kv(Icons.location_on_outlined, o.city),
                ],
                const SizedBox(height: 8),
                _timeline(o),
                if (hasLogistics) ...[
                  const SizedBox(height: 10),
                  if (_has(t.warehouse)) _kv(Icons.warehouse_outlined, 'Warehouse: ${t.warehouse}'),
                  if (_has(t.carrier)) _kv(Icons.local_shipping_outlined, 'Carrier: ${t.carrier}'),
                  if (_has(t.trackingNo)) _kv(Icons.qr_code_2_outlined, 'Tracking: ${t.trackingNo}'),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F8F5),
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total',
                          style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        formatInr(o.totalAmount),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_has(o.paymentMethod))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      o.paymentMethod,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}