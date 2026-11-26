import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/dispatch_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import 'invoice_view_screen.dart';
import '../widgets/invoice_link.dart';

/// Retailer dispatch history: Orders / Schemes tabs, search, infinite scroll,
/// "Mark as Received" (delivery confirmation).
/// API: GET/POST v1/retailer/dispatch-history.
class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen>
    with SingleTickerProviderStateMixin {
  static const Color _header = Color(0xFF0D9488); // top header (change here)
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';
  int _ordersCount = 0;
  int _schemesCount = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _search = v.trim());
    });
  }

  void _onCounts(int orders, int schemes) {
    if (orders == _ordersCount && schemes == _schemesCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _ordersCount = orders;
        _schemesCount = schemes;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _header,
      appBar: AppBar(
        title: const Text('Dispatch'),
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
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(text: 'Orders ($_ordersCount)'),
            Tab(text: 'Schemes ($_schemesCount)'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            color: _header,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
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
              child: TabBarView(
                controller: _tabs,
                children: [
                  _DispatchList(
                    key: ValueKey('orders|$_search'),
                    tab: 'orders',
                    search: _search,
                    onCounts: _onCounts,
                  ),
                  _DispatchList(
                    key: ValueKey('schemes|$_search'),
                    tab: 'schemes',
                    search: _search,
                    onCounts: _onCounts,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DispatchList extends StatefulWidget {
  final String tab;
  final String search;
  final void Function(int orders, int schemes) onCounts;

  const _DispatchList({
    super.key,
    required this.tab,
    required this.search,
    required this.onCounts,
  });

  @override
  State<_DispatchList> createState() => _DispatchListState();
}

class _DispatchListState extends State<_DispatchList>
    with AutomaticKeepAliveClientMixin {
  static const int _limit = 15;
  static const Color _accent = Color(0xFF0D9488);

  final _scroll = ScrollController();
  final List<DispatchItem> _items = [];
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<int> _receiving = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<DispatchPage> _fetch(int page) => RetailerService.getDispatchHistory(
        tab: widget.tab,
        search: widget.search,
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
          ..addAll(p.items);
        _page = p.page;
        _totalPages = p.totalPages;
        _loading = false;
      });
      widget.onCounts(p.totalOrdersGlobal, p.totalSchemesGlobal);
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
        _items.addAll(p.items);
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

  Future<void> _markReceived(DispatchItem it) async {
    if (_receiving.contains(it.orderId)) return;
    var accepted = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Mark as received?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InvoiceLink(it.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: accepted,
                onChanged: (v) => setD(() => accepted = v ?? false),
                title: const Text(
                  'I confirm goods were received in good condition.',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: accepted ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _receiving.add(it.orderId));
    try {
      final msg = await RetailerService.markDispatchReceived(it.orderId);
      if (!mounted) return;
      setState(() {
        _receiving.remove(it.orderId);
        final idx = _items.indexWhere((e) => e.orderId == it.orderId);
        if (idx >= 0) _items[idx] = _items[idx].copyAsReceived();
      });
      showStatus(context, msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _receiving.remove(it.orderId));
      showStatus(context, e.message, error: true);
    }
  }

  void _openInvoice(DispatchItem it) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceViewScreen(invoiceNumber: it.invoiceNumber),
      ),
    );
  }

  Future<void> _openPdf(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showStatus(context, 'Could not open invoice PDF.', error: true);
    } catch (_) {
      if (mounted) showStatus(context, 'Could not open invoice PDF.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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

    final isSchemes = widget.tab == 'schemes';
    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(
                  isSchemes ? Icons.local_offer_outlined : Icons.local_shipping_outlined,
                  size: 56,
                  color: AppColors.muted,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    isSchemes ? 'No dispatched schemes' : 'No dispatched orders',
                    style: const TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _items.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, idx) {
                if (idx >= _items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return _card(_items[idx]);
              },
            ),
    );
  }

  Widget _badge(DispatchItem it) {
    final received = it.isReceived;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: received ? AppColors.successBg : const Color(0xFFCCF2EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        received ? 'Received' : 'Dispatched',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: received ? AppColors.successText : const Color(0xFF0B6B62),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  Widget _card(DispatchItem it) {
    final busy = _receiving.contains(it.orderId);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0F1E2A3B), blurRadius: 10, offset: Offset(0, 3)),
        ],
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
                    onTap: () => _openInvoice(it),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        it.invoiceNumber,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                          decoration: TextDecoration.underline,
                          decorationColor: _accent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _badge(it),
            ],
          ),
          const SizedBox(height: 10),
          if (it.customerName.isNotEmpty) ...[
            Text(
              it.customerName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (it.city.isNotEmpty && it.city != 'N/A')
                _meta(Icons.location_on_outlined, it.city),
              _meta(Icons.event_outlined, 'Dispatched: ${it.dispatchDate ?? '-'}'),
              if (it.isScheme)
                _meta(Icons.card_giftcard_outlined,
                    '${it.giftCount} gift${it.giftCount == 1 ? '' : 's'}'),
              if (it.trackingInfo != null)
                _meta(Icons.local_shipping_outlined, it.trackingInfo!),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(
                      formatInr(it.totalAmount),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (it.paymentStatus.isNotEmpty)
                Text(
                  it.paymentStatus,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: it.paymentStatus.toLowerCase() == 'paid'
                        ? AppColors.successText
                        : const Color(0xFF8A5A00),
                  ),
                ),
            ],
          ),
          if (it.invoicePdfUrl != null || it.canReceive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (it.invoicePdfUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _openPdf(it.invoicePdfUrl!),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Invoice'),
                  ),
                const Spacer(),
                if (it.canReceive)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: busy ? null : () => _markReceived(it),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Mark Received'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}