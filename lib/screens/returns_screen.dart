import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/retailer_service.dart';
import '../core/returns_models.dart';
import '../widgets/app_widgets.dart';
import 'cart_screen.dart';
import 'return_form_screen.dart';
import '../widgets/invoice_link.dart';

/// Retailer returns: history with status filter + search, claim approved
/// returns, and start a new return request.
/// API: GET/POST v1/retailer/returns.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  static const int _limit = 15;
  static const Color _header = Color(0xFF7C3AED); // top header (change here)
  static const List<String> _filters = [
    'All',
    'Pending',
    'Approved',
    'Claimed',
    'Rejected',
  ];

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<ReturnRecord> _items = [];
  String _filter = 'All';
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<int> _claiming = {};

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

  Future<ReturnsPage> _fetch(int page) => RetailerService.getReturns(
        status: _filter == 'All' ? '' : _filter,
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
          ..addAll(p.returns);
        _total = p.totalReturns;
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
        _items.addAll(p.returns);
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

  Future<void> _newReturn() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ReturnFormScreen()),
    );
    if (created == true && mounted) _load();
  }

  Future<void> _claim(ReturnRecord r) async {
    final isRepl = r.isReplacement;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRepl ? 'Claim replacement?' : 'Claim credit note?'),
        content: Text(isRepl
            ? 'Replacement products will be added to your cart at ₹0.'
            : '${formatInr(r.creditAmount)} will be added to your credit limit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Claim'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _claiming.add(r.id));
    try {
      final res = await RetailerService.claimReturn(r.id);
      if (!mounted) return;
      setState(() => _claiming.remove(r.id));
      showStatus(context, res.message);
      await _load();
      if (res.goToCart && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CartScreen()),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _claiming.remove(r.id));
      showStatus(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _header,
      appBar: AppBar(
        title: const Text('My Returns'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newReturn,
        backgroundColor: _header,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Return'),
      ),
      body: Column(
        children: [
          Container(
            color: _header,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: inputDecoration(hint: 'Search invoice or reason').copyWith(
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
              ),
            ),
          ),
          Container(
            color: _header,
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final sel = _filter == f;
                return GestureDetector(
                  onTap: () {
                    if (_filter == f) return;
                    setState(() => _filter = f);
                    _load();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? _header : Colors.white,
                      ),
                    ),
                  ),
                );
              },
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
                Icon(Icons.assignment_return_outlined,
                    size: 56, color: AppColors.muted),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No returns found',
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
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
            child: const Icon(Icons.assignment_return_outlined, color: _header, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total returns',
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

  ({Color bg, Color fg}) _statusColors(ReturnRecord r) {
    final s = r.status.toLowerCase();
    if (s == 'approved') return (bg: AppColors.successBg, fg: AppColors.successText);
    if (s == 'claimed') return (bg: const Color(0xFFEDE5FD), fg: const Color(0xFF5B21B6));
    if (r.isRejected) return (bg: AppColors.dangerBg, fg: AppColors.dangerText);
    return (bg: const Color(0xFFFFF1D6), fg: const Color(0xFF8A5A00));
  }

  Widget _badge(ReturnRecord r) {
    final c = _statusColors(r);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        r.status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.fg),
      ),
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

  Widget _card(ReturnRecord r) {
    final busy = _claiming.contains(r.id);
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InvoiceLink(
                        r.invoiceNumber,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _badge(r),
                  ],
                ),
                const SizedBox(height: 8),
                if (r.reason.isNotEmpty) _kv(Icons.report_gmailerrorred_outlined, r.reason),
                if (r.formattedDate.isNotEmpty) _kv(Icons.event_outlined, r.formattedDate),
                _kv(
                  r.isReplacement ? Icons.swap_horiz : Icons.account_balance_wallet_outlined,
                  r.resolutionType,
                ),
                if (r.items.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        for (final it in r.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    it.productName,
                                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '× ${it.quantity}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _header,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F2FE),
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Credit amount',
                          style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        formatInr(r.creditAmount),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (r.isClaimable)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _header),
                    onPressed: busy ? null : () => _claim(r),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.redeem, size: 18),
                    label: const Text('Claim'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}