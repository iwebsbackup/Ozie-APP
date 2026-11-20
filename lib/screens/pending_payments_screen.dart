import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/pending_payments_models.dart';
import '../core/razorpay_service.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/shining_border_button.dart';

/// Retailer pending payments: summary, search, date filter, infinite scroll,
/// multi-select + "Request Collection".
class PendingPaymentsScreen extends StatefulWidget {
  const PendingPaymentsScreen({super.key});

  @override
  State<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  static const Color _orange = Color(0xFFFF8A00);

  static const int _limit = 15;

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<PendingInvoice> _items = [];
  final Set<int> _selected = {};
  double _totalAmount = 0;
  int _totalCount = 0;
  int _page = 1;
  int _totalPages = 1;

  bool _loading = true;
  bool _pageLoading = false;
  final Map<int, double> _dueById = {};
  bool _submitting = false;
  String? _error;
  DateTimeRange? _range;

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

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<PendingPaymentsPage> _fetch(int page) => RetailerService.getPendingPayments(
        search: _searchCtrl.text.trim(),
        startDate: _range == null ? '' : _ymd(_range!.start),
        endDate: _range == null ? '' : _ymd(_range!.end),
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
        _selected.clear();
        _dueById.clear();
        _totalAmount = p.totalAmount;
        _totalCount = p.totalCount;
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

  /// Replace the list with another page (selection is kept across pages).
  Future<void> _goToPage(int p) async {
    if (_pageLoading || _loading || p == _page || p < 1 || p > _totalPages) return;
    setState(() => _pageLoading = true);
    try {
      final r = await _fetch(p);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.invoices);
        _page = r.page;
        _totalPages = r.totalPages;
        _totalAmount = r.totalAmount;
        _totalCount = r.totalCount;
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

  Future<void> _pickRange() async {
    final res = await showDialog<_RangeResult>(
      context: context,
      builder: (_) => _DueDateRangeDialog(initial: _range),
    );
    if (res == null || !mounted) return;
    setState(() {
      _range = (res.start == null || res.end == null)
          ? null
          : DateTimeRange(start: res.start!, end: res.end!);
    });
    _load();
  }

  void _clearRange() {
    setState(() => _range = null);
    _load();
  }

  double get _selectedDue =>
      _selected.fold<double>(0, (sum, id) => sum + (_dueById[id] ?? 0));

  void _toggle(PendingInvoice i) {
    if (i.isRequested) return;
    setState(() {
      if (_selected.add(i.id)) {
        _dueById[i.id] = i.due;
      } else {
        _selected.remove(i.id);
        _dueById.remove(i.id);
      }
    });
  }

  Future<void> _requestCollection() async {
    if (_selected.isEmpty || _submitting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request collection?'),
        content: Text(
          '${_selected.length} invoice(s), ${formatInr(_selectedDue)} due. '
          'Your salesman will visit to collect payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final msg = await RetailerService.requestCollection(_selected.toList());
      if (!mounted) return;
      showStatus(context, msg);
      setState(() => _submitting = false);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showStatus(context, e.message, error: true);
    }
  }

  Future<void> _payOnline() async {
    if (_selected.isEmpty || _submitting) return;
    final amount = _selectedDue;
    if (amount <= 0) {
      showStatus(context, 'Nothing due on selected invoices.', error: true);
      return;
    }
    final ids = _selected.toList();
    setState(() => _submitting = true);

    final out = await RazorpayService.pay(
      amount: amount,
      description: '${ids.length} invoice(s)',
    );
    if (!mounted) return;
    if (!out.success) {
      setState(() => _submitting = false);
      if (!out.cancelled) showStatus(context, out.error ?? 'Payment failed.', error: true);
      return;
    }

    try {
      final msg = await RetailerService.verifyOnlinePayment(
        orderIds: ids,
        razorpayPaymentId: out.paymentId!,
      );
      if (!mounted) return;
      showStatus(context, msg);
      setState(() => _submitting = false);
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showStatus(
        context,
        'Payment received (ID: ${out.paymentId}) but update failed: ${e.message}. '
        'Contact support with this payment ID.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _orange,
      extendBody: true, // body shows behind the floating action bar
      appBar: AppBar(
        title: const Text('Pending Payments'),
        backgroundColor: _orange,
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
      bottomNavigationBar: _selected.isEmpty ? null : _actionBar(),
    );
  }

  Widget _filters() {
    return Container(
      color: _orange,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: inputDecoration(hint: 'Search invoice number').copyWith(
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Filter by due date',
                onPressed: _pickRange,
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedCalendarRange,
                  color: Colors.white,
                  size: 24,
                  strokeWidth: 1.5,
                ),
              ),
            ],
          ),
          if (_range != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                backgroundColor: Colors.white,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                deleteIconColor: _orange,
                label: Text(
                  'Due ${formatDate(_ymd(_range!.start))} - ${formatDate(_ymd(_range!.end))}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _orange,
                  ),
                ),
                onDeleted: _clearRange,
              ),
            ),
          ],
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
                Icon(Icons.payments_outlined, size: 56, color: AppColors.muted),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No pending payments',
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, _selected.isEmpty ? 24 : 110),
      itemCount: 1 + bodyCount + (showPager ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, idx) {
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
          totalItems: _totalCount,
          limit: _limit,
          itemLabel: 'invoices',
          onPage: _goToPage,
        );
      },
    );
  }

  Widget _summary() {
    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: Colors.white,
    );
    const valueStyle = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.1,
      color: Colors.white,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFAC1C), Color(0xFFFF8A00)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x33FF8A00), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL OUTSTANDING', style: labelStyle),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatInr(_totalAmount), style: valueStyle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('INVOICES PENDING', style: labelStyle),
                const SizedBox(height: 10),
                Text('$_totalCount', style: valueStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(PendingInvoice i) {
    String label;
    Color bg;
    Color fg;
    if (i.isRequested) {
      label = 'Requested';
      bg = const Color(0xFFDCE9FB);
      fg = AppColors.blue;
    } else if (i.isOverdue) {
      label = 'Overdue';
      bg = AppColors.dangerBg;
      fg = AppColors.dangerText;
    } else if (i.isPartial) {
      label = 'Partial';
      bg = const Color(0xFFFFF1D6);
      fg = const Color(0xFF8A5A00);
    } else {
      label = 'Pending';
      bg = const Color(0xFFFFF1D6);
      fg = const Color(0xFF8A5A00);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _amount(String label, double v, {Color? color}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(
              formatInr(v),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.text,
              ),
            ),
          ],
        ),
      );

  Widget _card(PendingInvoice i) {
    final selected = _selected.contains(i.id);
    final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: selected,
                    onChanged: i.isRequested ? null : (_) => _toggle(i),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        i.invoiceNumber,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                _badge(i),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _amount('Total', i.total),
                _amount('Paid', i.paid, color: AppColors.successText),
                _amount('Due', i.due, color: AppColors.dangerText),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.event_outlined, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                  'Due date: ${formatDate(i.dueDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: i.isOverdue && !i.isRequested
                        ? AppColors.dangerText
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        );

    final Widget box = selected
        ? ShiningBorder(
            radius: 12,
            borderWidth: 1.6,
            child: Container(
              padding: const EdgeInsets.all(13.4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10.4),
              ),
              child: content,
            ),
          )
        : Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: content,
          );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: i.isRequested ? null : () => _toggle(i),
      child: box,
    );
  }

  Widget _actionBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.fromLTRB(22, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: const Color(0xFFD5DBE8)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  Text(
                    formatInr(_selectedDue),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: _submitting ? null : _requestCollection,
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              ),
              child: const Text('Collect', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _submitting ? null : _payOnline,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Pay now', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeResult {
  final DateTime? start;
  final DateTime? end;
  const _RangeResult(this.start, this.end);
}

/// Small centered calendar dialog (not full screen). Pick From, then To.
class _DueDateRangeDialog extends StatefulWidget {
  final DateTimeRange? initial;
  const _DueDateRangeDialog({this.initial});

  @override
  State<_DueDateRangeDialog> createState() => _DueDateRangeDialogState();
}

class _DueDateRangeDialogState extends State<_DueDateRangeDialog> {
  late final DateTime _first;
  late final DateTime _last;
  DateTime? _from;
  DateTime? _to;
  bool _pickingFrom = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _first = DateTime(now.year - 3);
    _last = DateTime(now.year + 2, 12, 31);
    _from = widget.initial?.start;
    _to = widget.initial?.end;
  }

  String _fmt(DateTime? d) {
    if (d == null) return '--';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  void _onPick(DateTime d) {
    setState(() {
      if (_pickingFrom) {
        _from = d;
        if (_to != null && _to!.isBefore(d)) _to = null;
        _pickingFrom = false;
      } else {
        if (_from != null && d.isBefore(_from!)) {
          _from = d;
          _to = null;
        } else {
          _to = d;
        }
      }
    });
  }

  Widget _chip(String label, DateTime? v, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE0ECFB) : AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? AppColors.blue : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(_fmt(v), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final cur = (_pickingFrom ? _from : _to) ?? _from ?? DateTime(today.year, today.month, today.day);
    final initial = cur.isAfter(_last) ? _last : (cur.isBefore(_first) ? _first : cur);
    final canApply = _from != null;
    return Dialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    _chip('From', _from, _pickingFrom, () => setState(() => _pickingFrom = true)),
                    const SizedBox(width: 10),
                    _chip('To', _to, !_pickingFrom, () => setState(() => _pickingFrom = false)),
                  ],
                ),
              ),
              CalendarDatePicker(
                key: ValueKey(_pickingFrom),
                initialDate: initial,
                firstDate: _first,
                lastDate: _last,
                onDateChanged: _onPick,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(const _RangeResult(null, null)),
                    child: const Text('Clear'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: canApply
                        ? () => Navigator.of(context).pop(_RangeResult(_from, _to ?? _from))
                        : null,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}