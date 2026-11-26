import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/order_detail_models.dart';
import '../widgets/app_widgets.dart';
import '../widgets/invoice_link.dart';

/// Order Details: opened by tapping an entry in View Orders -> Approved.
/// Everything comes from the tapped order (GET v1/retailer/orders already
/// returns items, addresses, payment, logistics and a signed invoice URL).
class OrderDetailsScreen extends StatelessWidget {
  final ApprovedOrder order;
  const OrderDetailsScreen({super.key, required this.order});

  BoxDecoration get _cardDeco => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      );

  Future<void> _open(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showStatus(context, 'Could not open link.', error: true);
    } catch (_) {
      if (context.mounted) showStatus(context, 'Could not open link.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = OrderDetailData.fromJson(order.raw.isEmpty
        ? {
            'id': order.id,
            'order_number': order.orderNumber,
            'invoice_number': order.invoiceNumber,
            'shipping_name': order.shippingName,
            'total': order.total,
            'invoice_status': order.invoiceStatus,
            'payment_status': order.paymentStatus,
            'payment_badge': order.paymentBadge,
            'created_at': order.createdAt,
            'formatted_date': order.formattedDate,
          }
        : order.raw);
    final viewUrl = d.invoiceViewUrl;
    final pdfUrl = d.invoicePdfUrl;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: AppColors.text,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _header(d),
          const SizedBox(height: 12),
          _itemsCard(d),
          if (!d.shipping.isEmpty) ...[
            const SizedBox(height: 12),
            _addressCard('Shipping to', Icons.local_shipping_outlined, d.shipping),
          ],
          if (!d.billing.isEmpty) ...[
            const SizedBox(height: 12),
            _addressCard('Billing', Icons.business_outlined, d.billing),
          ],
          const SizedBox(height: 12),
          _paymentCard(d),
          if (_showLogistics(d)) ...[
            const SizedBox(height: 12),
            _logisticsCard(d),
          ],
          const SizedBox(height: 12),
          _summaryCard(d),
        ],
      ),
      bottomNavigationBar: (viewUrl == null && pdfUrl == null)
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (viewUrl != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _open(context, viewUrl),
                          icon: const Icon(Icons.receipt_long_outlined, size: 20),
                          label: const Text('View invoice'),
                          style: _btnStyle(AppColors.blue, Colors.white),
                        ),
                      ),
                    if (viewUrl != null && pdfUrl != null) const SizedBox(width: 10),
                    if (pdfUrl != null)
                      Expanded(
                        child: viewUrl == null
                            ? FilledButton.icon(
                                onPressed: () => _open(context, pdfUrl),
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                label: const Text('Invoice PDF'),
                                style: _btnStyle(AppColors.blue, Colors.white),
                              )
                            : OutlinedButton.icon(
                                onPressed: () => _open(context, pdfUrl),
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                label: const Text('PDF'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.blue,
                                  minimumSize: const Size.fromHeight(54),
                                  textStyle: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w600),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  ButtonStyle _btnStyle(Color bg, Color fg) => FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  /* ----------------------------- pieces ----------------------------- */

  Widget _kv(String k, Widget v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(k, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ),
            Expanded(child: v),
          ],
        ),
      );

  Text _val(String s) =>
      Text(s, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _sectionTitle(String title, IconData icon) => Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE0ECFB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: AppColors.blue),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _header(OrderDetailData d) {
    final approved = d.invoiceStatus.toLowerCase() == 'approved';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.orderNumber,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (d.invoiceStatus.isNotEmpty)
                _badge(
                  d.invoiceStatus,
                  approved ? const Color(0xFFE0ECFB) : AppColors.bg,
                  approved ? AppColors.blue : AppColors.muted,
                ),
              if (d.paymentBadge.isNotEmpty)
                _badge(
                  d.paymentBadge,
                  d.isPaid ? AppColors.successBg : AppColors.dangerBg,
                  d.isPaid ? AppColors.successText : AppColors.dangerText,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE0ECFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Order total',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.blue)),
                const SizedBox(height: 2),
                Text(formatInr(d.total),
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.blue)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _kv('Order date', _val(d.formattedDate ?? formatDate(d.createdAt))),
          if (d.poNumber != null && d.poNumber != d.orderNumber)
            _kv('PO number', _val(d.poNumber!)),
          if (d.invoiceNumber != null)
            _kv(
              'Invoice',
              Align(
                alignment: Alignment.centerLeft,
                child: InvoiceLink(
                  d.invoiceNumber!,
                  url: d.invoiceViewUrl,
                  orderId: d.id,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard(OrderDetailData d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Items (${d.items.length})', Icons.inventory_2_outlined),
          if (!d.hasItems)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Item details are not available for this order.',
                style: TextStyle(fontSize: 14.5, color: AppColors.muted),
              ),
            ),
          for (var i = 0; i < d.items.length; i++) ...[
            if (i > 0) const Divider(height: 22, color: AppColors.border),
            _itemRow(d.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _thumb(String? url) {
    const size = 56.0;
    Widget fallback() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.image_outlined, color: AppColors.muted),
        );
    if (url == null) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        Uri.encodeFull(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  Widget _itemRow(OrderLine it) {
    final meta = <String>[
      if (it.brand != null) it.brand!,
      if (it.unitSize != null) it.unitSize!,
      if (it.units > 1 && it.packingType != null) '${it.units} per ${it.packingType}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumb(it.photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.name,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.3)),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(meta,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ),
                const SizedBox(height: 4),
                Text('Qty ${it.quantity} x ${formatInr(it.unitPrice)}',
                    style: const TextStyle(fontSize: 14, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(formatInr(it.lineTotal),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _addressCard(String title, IconData icon, OrderParty a) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title, icon),
            const SizedBox(height: 12),
            if (a.name != null)
              Text(a.name!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (a.fullAddress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(a.fullAddress,
                    style: const TextStyle(
                        fontSize: 14.5, color: AppColors.muted, height: 1.45)),
              ),
            if (a.contact != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Phone: ${a.contact}',
                    style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
              ),
            if (a.gst != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('GSTIN: ${a.gst}',
                    style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
              ),
          ],
        ),
      );

  Widget _paymentCard(OrderDetailData d) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Payment', Icons.payments_outlined),
            const SizedBox(height: 8),
            if (d.paymentMethod.isNotEmpty) _kv('Method', _val(d.paymentMethod)),
            if (d.paymentBadge.isNotEmpty) _kv('Status', _val(d.paymentBadge)),
            if (d.paymentDate != null) _kv('Paid on', _val(formatDate(d.paymentDate))),
            if (d.dueDate != null && !d.isPaid) _kv('Due date', _val(formatDate(d.dueDate))),
            if (d.paidAmount > 0) _kv('Paid amount', _val(formatInr(d.paidAmount))),
            if (d.dueAmount > 0) _kv('Due amount', _val(formatInr(d.dueAmount))),
          ],
        ),
      );

  bool _showLogistics(OrderDetailData d) =>
      d.dispatchStatus.isNotEmpty ||
      d.carrier != null ||
      d.trackingNo != null ||
      d.warehouse != null;

  Widget _logisticsCard(OrderDetailData d) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Delivery', Icons.local_shipping_outlined),
            const SizedBox(height: 8),
            if (d.dispatchStatus.isNotEmpty) _kv('Status', _val(d.dispatchStatus)),
            if (d.packingStatus.isNotEmpty) _kv('Packing', _val(d.packingStatus)),
            if (d.warehouse != null) _kv('Warehouse', _val(d.warehouse!)),
            if (d.carrier != null) _kv('Carrier', _val(d.carrier!)),
            if (d.trackingNo != null) _kv('Tracking no.', _val(d.trackingNo!)),
            if (d.dispatchedAt != null) _kv('Dispatched', _val(formatDate(d.dispatchedAt))),
            if (d.eta != null) _kv('ETA', _val(formatDate(d.eta))),
            if (d.receivedAt != null) _kv('Received', _val(formatDate(d.receivedAt))),
          ],
        ),
      );

  Widget _sumRow(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(k,
                  style: TextStyle(
                      fontSize: bold ? 16 : 14.5,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                      color: bold ? AppColors.text : AppColors.muted)),
            ),
            Text(v,
                style: TextStyle(
                    fontSize: bold ? 17 : 15,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: color ?? AppColors.text)),
          ],
        ),
      );

  Widget _summaryCard(OrderDetailData d) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco,
        child: Column(
          children: [
            if (d.hasItems) _sumRow('Items subtotal', formatInr(d.itemsSubtotal)),
            if (d.totalQuantity > 0) _sumRow('Total quantity', '${d.totalQuantity}'),
            if (d.couponDiscount > 0)
              _sumRow(
                d.couponCode != null ? 'Coupon (${d.couponCode})' : 'Coupon discount',
                '- ${formatInr(d.couponDiscount)}',
                color: AppColors.successText,
              ),
            if (d.hasItems || d.totalQuantity > 0 || d.couponDiscount > 0)
              const Divider(height: 20, color: AppColors.border),
            _sumRow('Order total', formatInr(d.total), bold: true),
          ],
        ),
      );
}
