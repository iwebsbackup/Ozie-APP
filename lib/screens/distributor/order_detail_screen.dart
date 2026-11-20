import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'distributor_order_models.dart';
import 'distributor_service.dart';
import 'distributor_widgets.dart';

/// Full detail of one order.
///  isPo = true  -> id is PO id (type=po). Pending PO shows Approve / Reject.
///  isPo = false -> id is order id (type=retailer): invoice, timeline, items.
///
/// Pops with `approved` / `rejected` / `conflict` when a PO action happened.
class OrderDetailScreen extends StatefulWidget {
  final int id;
  final bool isPo;
  const OrderDetailScreen({super.key, required this.id, required this.isPo});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderDetail? _d;
  bool _loading = true;
  String? _error;

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
      final d =
          await DistributorService.getOrderDetail(widget.id, isPo: widget.isPo);
      if (!mounted) return;
      setState(() {
        _d = d;
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

  Future<void> _act(bool approve) async {
    final d = _d!;
    final r = await runPoAction(context,
        poId: d.id, poNumber: d.number, approve: approve);
    if (!mounted || r == null) return;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.isPo ? 'Purchase Order' : 'Order Detail'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || d == null
              ? ErrorView(message: _error ?? 'Failed to load.', onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _header(d),
                      if (d.timeline.isNotEmpty) _timeline(d),
                      _partyCard('Retailer', Icons.storefront_outlined,
                          d.retailer),
                      if (!d.salesman.isEmpty)
                        _partyCard('Salesman', Icons.badge_outlined, d.salesman,
                            showAddress: false),
                      _items(d),
                      _totals(d),
                      if (!d.isPo && !d.shipping.isEmpty) _shipping(d),
                      if (!d.isPo) _invoice(d),
                      if (d.notes != null) _notes(d.notes!),
                    ],
                  ),
                ),
      bottomNavigationBar: d != null && d.isPendingPo
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _act(false),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dangerText,
                        side: const BorderSide(color: AppColors.dangerText),
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _act(true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ]),
              ),
            )
          : null,
    );
  }

  // ───────────────────────── sections ─────────────────────────

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _title(String t, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.blue),
            const SizedBox(width: 8),
          ],
          Text(t,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
        ]),
      );

  Widget _kv(String k, String? v, {bool bold = false, Color? color}) {
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(k,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
        Expanded(
          child: Text(v,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? AppColors.text)),
        ),
      ]),
    );
  }

  Widget _header(OrderDetail d) {
    late final String label;
    late final Color color;
    if (d.isPo) {
      label = d.status.isEmpty
          ? 'Pending'
          : '${d.status[0].toUpperCase()}${d.status.substring(1)}';
      color = poStatusColor(d.status);
    } else {
      final st = d.dispatchStatus;
      if (st == 'Received') {
        label = 'Delivered';
        color = stageColor(4);
      } else if (st == 'Dispatched') {
        label = 'Dispatched';
        color = stageColor(3);
      } else if (d.invoiceStatus == 'Approved') {
        label = 'Processing';
        color = stageColor(2);
      } else {
        label = 'Pending';
        color = stageColor(1);
      }
    }
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(d.number,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
          ),
          StatusPill(label: label, color: color),
        ]),
        const SizedBox(height: 4),
        Text(d.orderDate,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 10),
        Text(formatInr(d.total),
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.blue)),
      ]),
    );
  }

  Widget _timeline(OrderDetail d) {
    final steps = d.timeline;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Order Tracking', icon: Icons.local_shipping_outlined),
        for (var i = 0; i < steps.length; i++)
          _timelineRow(steps[i], last: i == steps.length - 1),
        if (d.trackingNumber != null) ...[
          const SizedBox(height: 6),
          _kv('Tracking no.', d.trackingNumber, bold: true),
        ],
      ]),
    );
  }

  Widget _timelineRow(TimelineStep s, {required bool last}) {
    final c = s.done ? AppColors.green : AppColors.border;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 26,
          child: Column(children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: s.done ? c : AppColors.card,
                  border: Border.all(color: c, width: 2)),
              child: s.done
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (!last) Expanded(child: Container(width: 2, color: c)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14),
            child: Row(children: [
              Expanded(
                child: Text(s.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: s.done ? FontWeight.w600 : FontWeight.w400,
                        color: s.done ? AppColors.text : AppColors.muted)),
              ),
              Text(s.date ?? '-',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _partyCard(String title, IconData icon, PartyInfo p,
      {bool showAddress = true}) {
    final addr = p.fullAddress;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(title, icon: icon),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name ?? '-',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
              if (p.mobile != null) ...[
                const SizedBox(height: 2),
                Text(p.mobile!,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ]),
          ),
          if (p.mobile != null)
            IconButton.filledTonal(
              tooltip: 'Call',
              onPressed: () => callNumber(context, p.mobile),
              icon: const Icon(Icons.call, size: 18),
            ),
        ]),
        if (showAddress && addr.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(addr,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _items(OrderDetail d) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Items (${d.items.length})', icon: Icons.inventory_2_outlined),
        if (d.items.isEmpty)
          const Text('No items.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        for (var i = 0; i < d.items.length; i++) ...[
          if (i > 0)
            const Divider(height: 18, color: AppColors.border),
          _itemRow(d.items[i]),
        ],
      ]),
    );
  }

  Widget _itemRow(OrderLine it) {
    final extra = <String>[
      if (it.hsn.isNotEmpty) 'HSN ${it.hsn}',
      if (it.gstPercent > 0)
        'GST ${it.gstPercent.toStringAsFixed(it.gstPercent % 1 == 0 ? 0 : 1)}%',
    ].join('  ·  ');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 46,
          height: 46,
          color: AppColors.bg,
          child: it.image == null
              ? const Icon(Icons.inventory_2_outlined,
                  size: 22, color: AppColors.muted)
              : Image.network(
                  it.image!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.inventory_2_outlined,
                      size: 22,
                      color: AppColors.muted),
                ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(it.name,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
          const SizedBox(height: 2),
          Text(
              '${it.quantity} ${it.unit.isEmpty ? 'pcs' : it.unit} × ${formatInr(it.unitPrice)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (extra.isNotEmpty)
            Text(extra,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
      const SizedBox(width: 8),
      Text(formatInr(it.subtotal),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text)),
    ]);
  }

  Widget _totals(OrderDetail d) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Amount', icon: Icons.receipt_long_outlined),
        _kv('Subtotal', formatInr(d.subtotal)),
        if (d.discount > 0)
          _kv('Discount', '- ${formatInr(d.discount)}',
              color: AppColors.successText),
        if (d.gst > 0) _kv('GST', formatInr(d.gst)),
        const Divider(height: 16, color: AppColors.border),
        _kv('Total', formatInr(d.total), bold: true, color: AppColors.blue),
      ]),
    );
  }

  Widget _shipping(OrderDetail d) {
    final s = d.shipping;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Shipping', icon: Icons.local_shipping_outlined),
        if (s.name != null)
          Text(s.name!,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
        if (s.fullAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(s.fullAddress,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        if (d.dispatchedAt != null) ...[
          const SizedBox(height: 8),
          _kv('Dispatched', d.dispatchedAt),
        ],
        if (d.receivedAt != null) _kv('Received', d.receivedAt),
      ]),
    );
  }

  Widget _invoice(OrderDetail d) {
    final paid = (d.paymentStatus ?? '').toLowerCase();
    final payColor = paid.contains('partial')
        ? AppColors.blue
        : paid.contains('paid')
            ? AppColors.successText
            : kAmber;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Invoice', icon: Icons.description_outlined),
        _kv('Invoice no.', d.number),
        _kv('Invoice date', d.invoiceDate),
        _kv('Due date', d.dueDate),
        _kv('Status', d.invoiceStatus),
        _kv('Payment', d.paymentStatus, bold: true, color: payColor),
        _kv('Method', d.paymentMethod),
        if (d.pdfUrl != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => openUrlExternal(context, d.pdfUrl!),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Open Invoice PDF'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                foregroundColor: AppColors.blue,
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _notes(String n) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('Notes', icon: Icons.sticky_note_2_outlined),
          Text(n,
              style: const TextStyle(fontSize: 13, color: AppColors.text)),
        ]),
      );
}