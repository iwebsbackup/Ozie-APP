import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/packing_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/pagination_bar.dart';
import 'invoice_view_screen.dart';

/// Retailer packing: approved orders under packing / packed (not yet
/// dispatched). Search, pagination, progress stepper. Read-only.
/// API: GET v1/retailer/packing-orders.
class PackingScreen extends StatefulWidget {
  const PackingScreen({super.key});

  @override
  State<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends State<PackingScreen> {
  static const Color _header = Color(0xFF1E293B);

  static const int _limit = 6;

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<PackingOrder> _items = [];
  final Set<int> _expanded = {}; // orderIds with full details open
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _pageLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<PackingPage> _fetch(int page) => RetailerService.getPackingOrders(
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

  /// Replace the list with another page.
  Future<void> _goToPage(int p) async {
    if (_pageLoading || _loading || p == _page || p < 1 || p > _totalPages) return;
    setState(() => _pageLoading = true);
    try {
      final r = await _fetch(p);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.orders);
        _total = r.totalOrders;
        _page = r.page;
        _totalPages = r.totalPages;
        _pageLoading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _pageLoading = false);
      showStatus(context, e.message, error: true);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _load);
  }

  void _openInvoice(PackingOrder o) {
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
        title: const Text('Packing'),
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
                Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.muted),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No orders under packing',
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                ),
              ],
            )
          : _list(),
    );
  }

  Widget _list() {
    final showPager = _totalPages > 1;
    final bodyCount = _pageLoading ? 1 : _items.length;
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 1 + bodyCount + (showPager ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, idx) {
        if (idx == 0) return _summary();
        final pos = idx - 1;
        if (pos < bodyCount) {
          if (_pageLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _card(_items[pos]);
        }
        return PaginationBar(
          currentPage: _page,
          totalPages: _totalPages,
          totalItems: _total,
          limit: _limit,
          itemLabel: 'orders',
          onPage: _goToPage,
        );
      },
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppColors.blue),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Orders under processing',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          Text(
            '$_total',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _badge(PackingOrder o) {
    final packed = o.isPacked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: packed ? AppColors.successBg : const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        o.packingStatus,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: packed ? AppColors.successText : const Color(0xFF8A5A00),
        ),
      ),
    );
  }

  Widget _stepper(int step) {
    const labels = ['Packing', 'Packed', 'Dispatched'];
    Widget dot(int i) {
      final done = step >= i + 1;
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? AppColors.green : AppColors.card,
          border: Border.all(color: done ? AppColors.green : AppColors.border, width: 1.5),
        ),
        child: done ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
      );
    }

    Widget line(int i) => Expanded(
          child: Container(
            height: 2,
            color: step >= i + 2 ? AppColors.green : AppColors.border,
          ),
        );

    return Column(
      children: [
        Row(children: [dot(0), line(0), dot(1), line(1), dot(2)]),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < labels.length; i++)
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: step == i + 1 ? FontWeight.w700 : FontWeight.w500,
                  color: step >= i + 1 ? AppColors.text : AppColors.muted,
                ),
              ),
          ],
        ),
      ],
    );
  }

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

  Widget _card(PackingOrder o) {
    final addr = o.shipping.fullAddress;
    final open = _expanded.contains(o.orderId);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? _header.withValues(alpha: 0.35) : AppColors.border),
      ),
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
                      child: Text(
                        o.invoiceNumber,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.blue,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.blue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _badge(o),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (o.customerName.isNotEmpty)
                      Text(
                        o.customerName,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
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
              Material(
                color: open ? _header : _header.withValues(alpha: 0.08),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() {
                    if (!_expanded.remove(o.orderId)) _expanded.add(o.orderId);
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: open ? Colors.white : _header,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubic,
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            alignment: Alignment.topCenter,
            crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                if (o.formattedDate.isNotEmpty)
                  _kv(Icons.event_outlined, 'Ordered: ${o.formattedDate}'),
                if (addr.isNotEmpty) _kv(Icons.location_on_outlined, addr),
                if (o.shipping.hasContact) _kv(Icons.phone_outlined, o.shipping.contact),
                _kv(Icons.warehouse_outlined, 'Warehouse: ${o.logistics.warehouse}'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      o.isCod ? 'Cash on Delivery' : o.paymentStatus,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _stepper(o.progressStep),
              ],
            ),
          ),
        ],
      ),
    );
  }
}