import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/invoice_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import 'invoice_view_screen.dart';

/// Retailer invoices list: search, status + date filter, infinite scroll.
/// Tap a card -> [InvoiceViewScreen].
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  static const int _limit = 15;

  // value sent to API -> label
  static const List<List<String>> _statuses = [
    ['all', 'All'],
    ['paid', 'Paid'],
    ['pending', 'Pending'],
    ['unpaid', 'Overdue'],
    ['partially paid', 'Partial'],
    ['requested', 'Requested'],
  ];
  // Shown in the top strip; the rest live in the filter sheet.
  static const int _stripCount = 4;
  static const List<List<String>> _dates = [
    ['all', 'All time'],
    ['today', 'Today'],
    ['week', '7 days'],
    ['month', '30 days'],
  ];

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  bool _selectAll = false;
  Timer? _debounce;

  final List<InvoiceListItem> _items = [];
  String _status = 'all';
  String _date = 'all';
  int _page = 1;
  int _totalPages = 1;
  int _totalItems = 0;

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
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<InvoicesPage> _fetch(int page) => RetailerService.getInvoices(
        search: _searchCtrl.text.trim(),
        status: _status,
        date: _date,
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
          ..addAll(p.invoices);
        _page = p.page;
        _totalPages = p.totalPages;
        _totalItems = p.totalItems;
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
        _items.addAll(p.invoices);
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

  void _open(InvoiceListItem i) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceViewScreen(invoiceNumber: i.invoiceNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blue,
      appBar: _appBar(),
      body: Column(
        children: [
          _filters(),
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

  bool get _hasActiveFilter =>
      _status != 'all' || _date != 'all' || _searchCtrl.text.trim().isNotEmpty;

  static String _csvCell(String v) {
    final needs = v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    final e = v.replaceAll('"', '""');
    return needs ? '"$e"' : e;
  }

  /// Export CSV: filtered list when any filter/search is on, else all invoices.
  Future<void> _export() async {
    final filtered = _hasActiveFilter;
    final search = filtered ? _searchCtrl.text.trim() : '';
    final status = filtered ? _status : 'all';
    final date = filtered ? _date : 'all';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(filtered ? 'Exporting filtered invoices...' : 'Exporting all invoices...'),
              ),
            ],
          ),
        ),
      ),
    );

    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      final all = <InvoiceListItem>[];
      var page = 1;
      var totalPages = 1;
      do {
        final p = await RetailerService.getInvoices(
          search: search,
          status: status,
          date: date,
          page: page,
          limit: 100,
        );
        all.addAll(p.invoices);
        totalPages = p.totalPages;
        page++;
      } while (page <= totalPages);

      if (!mounted) return;
      if (all.isEmpty) {
        closeDialog();
        showStatus(context, 'No invoices to export', error: true);
        return;
      }

      final b = StringBuffer('\uFEFFInvoice Number,Customer,Amount,Status,Payment Method,Date\n');
      for (final i in all) {
        b.writeln([
          i.invoiceNumber,
          i.customerName,
          i.subtotal.toStringAsFixed(2),
          i.paymentStatus,
          i.paymentMethod ?? '',
          i.createdAt ?? '',
        ].map(_csvCell).join(','));
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = filtered ? 'filtered_invoices_$stamp.csv' : 'all_invoices_$stamp.csv';
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsString(b.toString());

      closeDialog();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: name,
        ),
      );
    } on ApiException catch (e) {
      closeDialog();
      if (mounted) showStatus(context, e.message, error: true);
    } catch (e, st) {
      debugPrint('Invoice export failed: $e\n$st');
      closeDialog();
      if (mounted) showStatus(context, 'Export failed: $e', error: true);
    }
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    final had = _searchCtrl.text.trim().isNotEmpty;
    _debounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() => _searching = false);
    if (had) _load();
  }

  PreferredSizeWidget _appBar() {
    if (_searching) {
      return AppBar(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Close search',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: Colors.white,
            strokeWidth: 1.5,
          ),
          onPressed: _closeSearch,
        ),
        title: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: (v) {
            setState(() {});
            _onSearchChanged(v);
          },
          textInputAction: TextInputAction.search,
          cursorColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search invoice number',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close, size: 20, color: Colors.white),
              onPressed: () {
                _searchCtrl.clear();
                setState(() {});
                _debounce?.cancel();
                _load();
              },
            ),
        ],
      );
    }
    return AppBar(
      title: const Text('Invoices'),
      backgroundColor: AppColors.blue,
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
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            color: Colors.white,
            size: 22,
            strokeWidth: 1.5,
          ),
          onPressed: _openSearch,
        ),
        IconButton(
          tooltip: _hasActiveFilter ? 'Export filtered invoices' : 'Export all invoices',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDownload01,
            color: Colors.white,
            size: 22,
            strokeWidth: 1.5,
          ),
          onPressed: _export,
        ),
      ],
    );
  }

  Widget _statusStrip() {
    final stripIds = _statuses.take(_stripCount).map((e) => e[0]);
    final hasFilter = _date != 'all' || !stripIds.contains(_status);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _stripCount,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final o = _statuses[i];
                return _pill(
                  o[1],
                  _status == o[0],
                  onDark: true,
                  onTap: () {
                    if (_status == o[0]) return;
                    setState(() => _status = o[0]);
                    _load();
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Filters',
              onPressed: _openFilters,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedFilterHorizontal,
                color: Colors.white,
                size: 22,
                strokeWidth: 1.5,
              ),
            ),
            if (hasFilter)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC857),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openFilters() async {
    final res = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InvoiceFilterSheet(
        status: _status,
        date: _date,
        statuses: _statuses,
        dates: _dates,
      ),
    );
    if (res == null || !mounted) return;
    if (res[0] == _status && res[1] == _date) return;
    setState(() {
      _status = res[0];
      _date = res[1];
    });
    _load();
  }

  Widget _filters() {
    return Container(
      color: AppColors.blue,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 18),
      child: _statusStrip(),
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
                Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.muted),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No invoices found',
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _items.length + 1 + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, idx) {
                if (idx == 0) return _countHeader();
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

  Widget _countHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Invoices',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text),
          ),
        ),
        Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _selectAll,
                onChanged: (v) => setState(() => _selectAll = v ?? false),
                activeColor: AppColors.blue,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                side: const BorderSide(color: AppColors.muted, width: 1.6),
              ),
              Text(
                '$_totalItems',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
      ],
    );
  }

  Widget _card(InvoiceListItem i) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(i),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _selectAll ? const Color(0xFFF1F6FD) : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectAll ? AppColors.blue : AppColors.border,
            width: _selectAll ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    i.invoiceNumber,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InvoiceStatusBadge(i.paymentStatus),
              ],
            ),
            if (i.customerName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                i.customerName,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatInr(i.subtotal),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.event_outlined, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                  formatDate(i.createdAt),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
            if (i.paymentMethod != null) ...[
              const SizedBox(height: 4),
              Text(
                i.paymentMethod!,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Bottom sheet: pick status + date, then Apply. Pops [status, date].
class _InvoiceFilterSheet extends StatefulWidget {
  final String status;
  final String date;
  final List<List<String>> statuses;
  final List<List<String>> dates;
  const _InvoiceFilterSheet({
    required this.status,
    required this.date,
    required this.statuses,
    required this.dates,
  });

  @override
  State<_InvoiceFilterSheet> createState() => _InvoiceFilterSheetState();
}

class _InvoiceFilterSheetState extends State<_InvoiceFilterSheet> {
  late String _status = widget.status;
  late String _date = widget.date;

  Widget _section(
    String title,
    List<List<String>> opts,
    String current,
    void Function(String) onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in opts)
              SizedBox(
                height: 36,
                child: _pill(
                  o[1],
                  current == o[0],
                  onTap: () => setState(() => onPick(o[0])),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filters',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _section('Status', widget.statuses, _status, (v) => _status = v),
            const SizedBox(height: 18),
            _section('Date', widget.dates, _date, (v) => _date = v),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _status = 'all';
                      _date = 'all';
                    }),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop([_status, _date]),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill chip: no check icon. Light bg: selected fills blue.
/// [onDark] (on blue header): selected fills white, others translucent.
Widget _pill(
  String label,
  bool selected, {
  required VoidCallback onTap,
  bool onDark = false,
}) {
  final Color bg;
  final Color border;
  final Color fg;
  if (onDark) {
    bg = selected ? Colors.white : Colors.white.withOpacity(0.14);
    border = selected ? Colors.white : Colors.white.withOpacity(0.45);
    fg = selected ? AppColors.blue : Colors.white;
  } else {
    bg = selected ? AppColors.blue : AppColors.card;
    border = selected ? AppColors.blue : AppColors.border;
    fg = selected ? Colors.white : AppColors.text;
  }
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
      ),
    ),
  );
}