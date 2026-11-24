import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/retailer_service.dart';
import '../../widgets/app_widgets.dart';

class OrdersTab extends StatefulWidget {
  /// Called with the active tab index (0 = Review, 1 = Approved) so the
  /// shell can tint its app bar to match the header colour.
  final ValueChanged<int>? onTabChanged;
  const OrdersTab({super.key, this.onTabChanged});

  static const Color reviewColor = Color(0xFF93C572);
  static const Color approvedColor = Color(0xFF008000);

  /// Active tab (0 = Review, 1 = Approved). Shell app bar listens to this so
  /// its colour always matches the header below.
  static final ValueNotifier<int> activeTab = ValueNotifier<int>(0);

  static Color headerColor(int index) => index == 0 ? reviewColor : approvedColor;

  /// Text/icon colour on the header: dark on yellow, white on green.
  static Color headerForeground(int index) =>
      index == 0 ? AppColors.text : Colors.white;

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _approvedReady = false;
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    OrdersTab.activeTab.value = 0;
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_approvedReady) {
        setState(() => _approvedReady = true);
      } else {
        setState(() {});
      }
      OrdersTab.activeTab.value = _tabs.index;
      if (_tabs.index != _lastIndex) {
        _lastIndex = _tabs.index;
        widget.onTabChanged?.call(_lastIndex);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outer colour fills the area behind the rounded body corners, same as
    // Pending Payments (Scaffold bg = header colour).
    return ColoredBox(
      color: OrdersTab.headerColor(_tabs.index),
      child: Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.35),
              borderRadius: BorderRadius.circular(40),
            ),
            child: TabBar(
              controller: _tabs,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              splashBorderRadius: BorderRadius.circular(40),
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
              ),
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.text.withOpacity(0.6),
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              tabs: const [
                Tab(height: 40, text: 'Review'),
                Tab(height: 40, text: 'Approved'),
              ],
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
                const _ReviewPane(),
                _approvedReady ? const _ApprovedPane() : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _ReviewPane extends StatefulWidget {
  const _ReviewPane();

  @override
  State<_ReviewPane> createState() => _ReviewPaneState();
}

class _ReviewPaneState extends State<_ReviewPane> {
  ReviewOrdersData? _data;
  String? _error;
  bool _loading = true;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await RetailerService.getReviewOrders();
      if (!mounted) return;
      setState(() {
        _data = next;
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

  Future<void> _act(String action, int orderId, {String? reason}) async {
    if (_busy.contains(orderId)) return;
    setState(() => _busy.add(orderId));
    try {
      final msg = await RetailerService.reviewAction(
        action: action,
        orderId: orderId,
        rejectReason: reason,
      );
      if (!mounted) return;
      showStatus(context, msg);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(orderId));
    }
  }

  Future<void> _reject(int orderId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject order'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: inputDecoration(hint: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true) await _act('reject', orderId, reason: reason.isEmpty ? 'No reason provided' : reason);
  }

  Future<void> _confirmDelete(int orderId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete order'),
        content: const Text('This will restore stock and remove the draft.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _act('delete', orderId);
  }

  Future<void> _deleteItem(int orderId, DraftOrderItem item) async {
    if (_busy.contains(orderId)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove product'),
        content: Text('Remove ${item.productName} from this order? Stock will be restored.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(orderId));
    try {
      final msg = await RetailerService.deleteDraftItem(orderId: orderId, detailId: item.id);
      if (!mounted) return;
      showStatus(context, msg);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(orderId));
    }
  }

  Future<void> _saveQuantities(int orderId, Map<int, int> quantities) async {
    if (_busy.contains(orderId) || quantities.isEmpty) return;
    setState(() => _busy.add(orderId));
    try {
      final r = await RetailerService.saveDraftQuantities(orderId: orderId, quantities: quantities);
      if (!mounted) return;
      if (r.stockErrors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Some items capped'),
            content: Text(r.stockErrors.join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      } else {
        showStatus(context, r.message);
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final drafts = _data?.draftOrders ?? const <DraftOrder>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: drafts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Icon(Icons.assignment_outlined, size: 40, color: AppColors.muted),
                SizedBox(height: 12),
                Center(child: Text('No draft orders to review', style: TextStyle(color: AppColors.muted))),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28 + kBottomNavSpace),
              itemCount: drafts.length,
              separatorBuilder: (context, i) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final o = drafts[i];
                return _DraftCard(
                  key: ValueKey('draft-${o.orderId}'),
                  order: o,
                  busy: _busy.contains(o.orderId),
                  onApprove: o.canApprove ? () => _act('approve', o.orderId) : null,
                  onReject: () => _reject(o.orderId),
                  onDelete: () => _confirmDelete(o.orderId),
                  onDeleteItem: (it) => _deleteItem(o.orderId, it),
                  onSave: (q) => _saveQuantities(o.orderId, q),
                );
              },
            ),
    );
  }
}

class _DraftCard extends StatefulWidget {
  final DraftOrder order;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;
  final void Function(DraftOrderItem item) onDeleteItem;
  final void Function(Map<int, int> quantities) onSave;
  const _DraftCard({
    super.key,
    required this.order,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
    required this.onDeleteItem,
    required this.onSave,
  });

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  /// detailId -> qty being edited (only paid lines).
  final Map<int, int> _qty = {};
  final Map<int, ItemPreview> _previews = {};
  final Set<int> _previewing = {};
  final Map<int, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    _resetFrom(widget.order);
  }

  @override
  void didUpdateWidget(covariant _DraftCard old) {
    super.didUpdateWidget(old);
    // Fresh data from server (after save / delete / reload) -> drop local edits.
    if (!identical(old.order, widget.order)) {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
      _previews.clear();
      _previewing.clear();
      _resetFrom(widget.order);
    }
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _resetFrom(DraftOrder o) {
    _qty
      ..clear()
      ..addEntries(
        o.items.where((i) => !i.isFree).map((i) => MapEntry(i.id, i.productQuantity)),
      );
  }

  DraftOrderItem? _itemById(int id) {
    for (final i in widget.order.items) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool get _dirty {
    for (final i in widget.order.items) {
      if (i.isFree) continue;
      if ((_qty[i.id] ?? i.productQuantity) != i.productQuantity) return true;
    }
    return false;
  }

  void _change(DraftOrderItem it, int next) {
    final max = it.maxAllowed > 0 ? it.maxAllowed : 1 << 30;
    if (next < 1) return;
    if (next > max) {
      showStatus(context, 'Only $max available for ${it.productName}.', error: true);
      return;
    }
    setState(() => _qty[it.id] = next);
    _timers[it.id]?.cancel();
    if (next == it.productQuantity) {
      setState(() => _previews.remove(it.id));
      return;
    }
    _timers[it.id] = Timer(const Duration(milliseconds: 400), () => _preview(it.id, next));
  }

  Future<void> _preview(int detailId, int qty) async {
    if (!mounted) return;
    setState(() => _previewing.add(detailId));
    try {
      final p = await RetailerService.previewDraftItem(
        orderId: widget.order.orderId,
        detailId: detailId,
        quantity: qty,
      );
      if (!mounted) return;
      // Ignore stale reply if user changed qty meanwhile.
      if ((_qty[detailId] ?? qty) != qty) return;
      setState(() {
        _previews[detailId] = p;
        if (p.quantity > 0 && p.quantity != qty) _qty[detailId] = p.quantity; // capped by stock
      });
    } on ApiException {
      // preview is best-effort; save will still validate
    } finally {
      if (mounted) setState(() => _previewing.remove(detailId));
    }
  }

  double get _estimatedSubtotal {
    double sum = 0;
    for (final i in widget.order.items) {
      if (i.isFree) continue;
      final q = _qty[i.id] ?? i.productQuantity;
      final p = _previews[i.id];
      sum += (p != null && p.quantity == q) ? p.lineTotal : i.productPrice * q;
    }
    return sum;
  }

  Color _stockColor(String cls) {
    switch (cls) {
      case 'insufficient':
      case 'out_of_stock':
        return AppColors.dangerText;
      case 'low_stock':
        return const Color(0xFFB7791F);
      default:
        return AppColors.successText;
    }
  }

  Widget _stepper(DraftOrderItem it) {
    final q = _qty[it.id] ?? it.productQuantity;
    final locked = widget.busy;
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: onTap == null || locked ? AppColors.muted : AppColors.text),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, q > 1 ? () => _change(it, q - 1) : null),
        SizedBox(
          width: 38,
          child: Center(
            child: Text('$q', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
        btn(Icons.add, () => _change(it, q + 1)),
      ],
    );
  }

  Widget _schemeLines(DraftOrderItem it) {
    final p = _previews[it.id];
    final q = _qty[it.id] ?? it.productQuantity;
    final usePreview = p != null && p.quantity == q;
    final applied = usePreview ? p.appliedSchemes : it.appliedSchemes;
    final unlock = usePreview ? p.unlockableSchemes : it.unlockableSchemes;
    final free = usePreview ? p.expectedFreeQty : 0;
    final lines = <Widget>[];
    for (final s in applied) {
      final t = s.message.isNotEmpty ? s.message : s.title;
      if (t.isEmpty) continue;
      lines.add(Text('✓ $t', style: const TextStyle(fontSize: 11.5, color: AppColors.successText)));
    }
    if (free > 0) {
      lines.add(Text('Free items on save: $free',
          style: const TextStyle(fontSize: 11.5, color: AppColors.successText, fontWeight: FontWeight.w600)));
    }
    for (final s in unlock) {
      final t = s.message.isNotEmpty ? s.message : s.title;
      if (t.isEmpty) continue;
      lines.add(Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.blue)));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  Widget _itemRow(DraftOrderItem it) {
    if (it.isFree) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text('${it.productName} (Free)',
                  style: const TextStyle(fontSize: 13, color: AppColors.successText)),
            ),
            Text('x${it.productQuantity}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(width: 8),
            const Text('FREE',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.successText)),
          ],
        ),
      );
    }
    final q = _qty[it.id] ?? it.productQuantity;
    final p = _previews[it.id];
    final line = (p != null && p.quantity == q) ? p.lineTotal : it.productPrice * q;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(it.productName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove product',
                onPressed: widget.busy ? null : () => widget.onDeleteItem(it),
                icon: const Icon(Icons.close, size: 18, color: AppColors.dangerText),
              ),
            ],
          ),
          Row(
            children: [
              // Wraps to 2 lines on narrow screens instead of overflowing.
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text('${formatInr(it.productPrice)} each',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    if (it.stockLabel.isNotEmpty)
                      Text(it.stockLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _stockColor(it.stockClass))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _stepper(it),
              const SizedBox(width: 10),
              SizedBox(
                width: 78,
                child: _previewing.contains(it.id)
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Text(formatInr(line),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          _schemeLines(it),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final dirty = _dirty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          o.orderNumber.isNotEmpty ? o.orderNumber : '#ORD-${o.orderId}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        subtitle: Text(
          '${o.salesmanName} · ${o.formattedDate ?? formatDate(o.createdAt)} · ${o.totalItems} items',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        trailing: Text(
          formatInr(o.summary.netPayable > 0 ? o.summary.netPayable : o.total),
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        children: [
          if (o.hasOutOfStock)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Some items are out of stock — reduce or remove them to approve.',
                  style: TextStyle(color: AppColors.dangerText, fontSize: 12)),
            ),
          ...o.items.map(_itemRow),
          const Divider(height: 20),
          if (dirty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Estimated subtotal (before schemes)',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                  Text(formatInr(_estimatedSubtotal),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            )
          else ...[
            _sumRow('Total', formatInr(o.summary.totalPrice > 0 ? o.summary.totalPrice : o.total)),
            if (o.summary.totalSavings > 0)
              _sumRow('Savings', '- ${formatInr(o.summary.totalSavings)}', color: AppColors.successText),
            if (o.summary.creditDays > 0) _sumRow('Credit', '${o.summary.creditDays} days'),
            const SizedBox(height: 6),
          ],
          if (widget.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (dirty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => widget.onSave(
                          {for (final e in _qty.entries) if ((_itemById(e.key)?.productQuantity) != e.value) e.key: e.value},
                        ),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save changes'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        for (final t in _timers.values) {
                          t.cancel();
                        }
                        _timers.clear();
                        _previews.clear();
                        _resetFrom(widget.order);
                      }),
                      child: const Text('Undo'),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    // Approve only on saved data, or server approves old qty.
                    onPressed: dirty ? null : widget.onApprove,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.successText),
                    child: Text(dirty ? 'Save first' : 'Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.dangerText),
                    child: const Text('Reject'),
                  ),
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  tooltip: 'Delete order',
                  icon: const Icon(Icons.delete_outline, color: AppColors.dangerText),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
            Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? AppColors.text)),
          ],
        ),
      );
}

class _ApprovedPane extends StatefulWidget {
  const _ApprovedPane();

  @override
  State<_ApprovedPane> createState() => _ApprovedPaneState();
}

class _ApprovedPaneState extends State<_ApprovedPane> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  OrdersPage? _data;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _ymd(DateTime? d) {
    if (d == null) return '';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _pickRange() async {
    final res = await showDialog<_RangeResult>(
      context: context,
      builder: (_) => _DateRangeDialog(start: _start, end: _end),
    );
    if (res == null) return;
    setState(() {
      _start = res.start;
      _end = res.end;
    });
    _load(reset: true);
  }

  Future<void> _load({bool reset = false, int? page}) async {
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _page = page ?? _page;
      setState(() => _loadingMore = true);
    }
    try {
      final next = await RetailerService.getOrders(
        search: _searchCtrl.text.trim(),
        startDate: _ymd(_start),
        endDate: _ymd(_end),
        page: _page,
        limit: 15,
      );
      if (!mounted) return;
      setState(() {
        _data = next;
        _loading = false;
        _loadingMore = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return _ErrorState(message: _error!, onRetry: () => _load(reset: true));
    }
    final d = _data!;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28 + kBottomNavSpace),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(reset: true),
                  decoration: inputDecoration(
                    hint: 'Invoice or customer',
                    suffix: IconButton(
                      icon: const Icon(Icons.search, color: AppColors.muted),
                      onPressed: () => _load(reset: true),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _pickRange,
                tooltip: 'Filter by date',
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFilterMail,
                  color: (_start != null) ? AppColors.blue : AppColors.muted,
                  strokeWidth: 1.5,
                ),
              ),
              if (_start != null)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _start = null;
                      _end = null;
                    });
                    _load(reset: true);
                  },
                  icon: const Icon(Icons.clear, color: AppColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metric('Orders', '${d.summary.totalOrders}')),
              const SizedBox(width: 12),
              Expanded(child: _metric('Value', formatInr(d.summary.totalAmount, decimals: false))),
            ],
          ),
          const SizedBox(height: 16),
          if (d.orders.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('No approved orders', style: TextStyle(color: AppColors.muted))),
            )
          else if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ...d.orders.map(_orderTile),
          if (d.pagination.totalPages > 1) _paginationBar(d.pagination),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
        ],
      ),
    );
  }

  void _goTo(int p) {
    if (_loadingMore || p == _page) return;
    _load(page: p);
  }

  Widget _pageBtn({required Widget child, VoidCallback? onTap, bool active = false, bool disabled = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.blue, AppColors.green],
                )
              : null,
          color: active ? null : (disabled ? AppColors.bg : AppColors.card),
          borderRadius: BorderRadius.circular(10),
          border: active ? null : Border.all(color: AppColors.border),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _paginationBar(PageInfo pg) {
    final total = pg.totalPages;
    final cur = pg.currentPage.clamp(1, total);

    // window of page numbers with ellipsis: 1 ... c-1 c c+1 ... N
    final nums = <int>{1, total, cur - 1, cur, cur + 1}.where((n) => n >= 1 && n <= total).toList()..sort();
    final items = <Widget>[];
    int? prev;
    for (final n in nums) {
      if (prev != null && n - prev > 1) {
        items.add(const Padding(
          padding: EdgeInsets.only(left: 2),
          child: Text('…', style: TextStyle(color: AppColors.muted)),
        ));
      }
      final active = n == cur;
      items.add(_pageBtn(
        active: active,
        onTap: active ? null : () => _goTo(n),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.text,
          ),
        ),
      ));
      prev = n;
    }

    final from = (cur - 1) * pg.limit + 1;
    final to = (cur * pg.limit).clamp(0, pg.totalItems);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pageBtn(
                disabled: !pg.hasPrevPage,
                onTap: pg.hasPrevPage ? () => _goTo(cur - 1) : null,
                child: Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: pg.hasPrevPage ? AppColors.text : AppColors.border,
                ),
              ),
              for (final w in items) ...[const SizedBox(width: 5), w],
              const SizedBox(width: 5),
              _pageBtn(
                disabled: !pg.hasNextPage,
                onTap: pg.hasNextPage ? () => _goTo(cur + 1) : null,
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: pg.hasNextPage ? AppColors.text : AppColors.border,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            pg.totalItems > 0
                ? 'Showing $from - $to of ${pg.totalItems} orders'
                : 'Page $cur of $total',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _orderTile(ApprovedOrder o) {
    final paid = o.isPaid;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.orderNumber.isNotEmpty ? o.orderNumber : 'ORD-${o.id}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
                const SizedBox(height: 3),
                Text(
                  '${o.shippingName} · ${o.formattedDate ?? formatDate(o.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatInr(o.total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _badge(
                    o.invoiceStatus,
                    o.invoiceStatus.toLowerCase() == 'approved' ? const Color(0xFFE0ECFB) : AppColors.bg,
                    o.invoiceStatus.toLowerCase() == 'approved' ? AppColors.blue : AppColors.muted,
                  ),
                  _badge(
                    o.paymentBadge,
                    paid ? AppColors.successBg : AppColors.dangerBg,
                    paid ? AppColors.successText : AppColors.dangerText,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.dangerText)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
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
class _DateRangeDialog extends StatefulWidget {
  final DateTime? start;
  final DateTime? end;
  const _DateRangeDialog({this.start, this.end});

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  late final DateTime _first;
  late final DateTime _last;
  DateTime? _from;
  DateTime? _to;
  bool _pickingFrom = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _last = DateTime(now.year, now.month, now.day);
    _first = DateTime(now.year - 2);
    _from = widget.start;
    _to = widget.end;
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
    final cur = (_pickingFrom ? _from : _to) ?? _from ?? _last;
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