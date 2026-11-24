import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/invoice_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';

/// Coloured pill for invoice payment status (Paid / Pending / Partial ...).
class InvoiceStatusBadge extends StatelessWidget {
  final String status;
  const InvoiceStatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = status.trim().toLowerCase();
    Color bg;
    Color fg;
    if (s == 'paid') {
      bg = AppColors.successBg;
      fg = AppColors.successText;
    } else if (s == 'requested') {
      bg = const Color(0xFFDCE9FB);
      fg = AppColors.blue;
    } else if (s == 'overdue' || s == 'unpaid' || s == 'due') {
      bg = AppColors.dangerBg;
      fg = AppColors.dangerText;
    } else {
      bg = const Color(0xFFFFF1D6);
      fg = const Color(0xFF8A5A00);
    }
    final label = s.isEmpty
        ? '-'
        : status
            .trim()
            .split(' ')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Retailer invoice detail (GET v1/retailer/invoice-view).
class InvoiceViewScreen extends StatefulWidget {
  final String invoiceNumber;
  const InvoiceViewScreen({super.key, required this.invoiceNumber});

  @override
  State<InvoiceViewScreen> createState() => _InvoiceViewScreenState();
}

class _InvoiceViewScreenState extends State<InvoiceViewScreen> {
  InvoiceDetail? _inv;
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
      final d = await RetailerService.getInvoiceDetail(widget.invoiceNumber);
      if (!mounted) return;
      setState(() {
        _inv = d;
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

  Future<void> _openPdf(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showStatus(context, 'Could not open PDF.', error: true);
    } catch (_) {
      if (mounted) showStatus(context, 'Could not open PDF.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdf = _inv?.pdfUrl;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.invoiceNumber),
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
      body: _body(),
      bottomNavigationBar: pdf == null || _loading
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: () => _openPdf(pdf),
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedPdf01,
                    color: Colors.white,
                    size: 22,
                    strokeWidth: 1.5,
                  ),
                  label: const Text('Open invoice PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _inv == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Invoice not found.',
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
    final inv = _inv!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _header(inv),
          const SizedBox(height: 14),
          if (!inv.shipping.isEmpty) ...[
            _addressCard('Shipping to', Icons.local_shipping_outlined, inv.shipping),
            const SizedBox(height: 12),
          ],
          if (!inv.billing.isEmpty) ...[
            _addressCard('Billing', Icons.business_outlined, inv.billing),
            const SizedBox(height: 12),
          ],
          _itemsCard(inv),
          const SizedBox(height: 12),
          _summaryCard(inv.summary),
        ],
      ),
    );
  }

  BoxDecoration get _cardDeco => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(k, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _header(InvoiceDetail inv) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inv.invoiceNumber,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              InvoiceStatusBadge(inv.paymentStatus),
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
                const Text(
                  'Net payable',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.blue),
                ),
                const SizedBox(height: 2),
                Text(
                  formatInr(inv.summary.netPayable),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _kv('Invoice date', formatDate(inv.invoiceDate)),
          _kv('Due date', formatDate(inv.dueDate)),
          if (inv.paymentMethod != null) _kv('Payment', inv.paymentMethod!),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
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
        Flexible(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _addressCard(String title, IconData icon, InvoiceAddress a) {
    return Container(
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
              child: Text(
                a.fullAddress,
                style: const TextStyle(fontSize: 14.5, color: AppColors.muted, height: 1.45),
              ),
            ),
          if (a.contact != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Phone: ${a.contact}',
                  style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
            ),
          if (a.gstin != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('GSTIN: ${a.gstin}',
                  style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard(InvoiceDetail inv) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Items (${inv.items.length})', Icons.inventory_2_outlined),
          const SizedBox(height: 2),
          if (inv.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No items.', style: TextStyle(fontSize: 15, color: AppColors.muted)),
            ),
          for (var i = 0; i < inv.items.length; i++) ...[
            if (i > 0) const Divider(height: 22, color: AppColors.border),
            _itemRow(inv.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(InvoiceLine it) {
    final discounted = it.originalPrice > 0 && it.originalPrice != it.unitPrice && !it.isReturn;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  it.productName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                it.isReturn ? 'FREE' : formatInr(it.totalAmount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: it.isReturn ? AppColors.successText : AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(child: Text(
                'Qty ${it.quantity} x ${formatInr(it.unitPrice)}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (discounted) ...[
                const SizedBox(width: 6),
                Text(
                  formatInr(it.originalPrice),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.muted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
          if (it.isSpecial)
            _tag('Special price - saved ${formatInr(it.specialSaving)}'),
          for (final s in it.schemes) _tag(s),
        ],
      ),
    );
  }

  Widget _tag(String t) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            t,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.successText,
            ),
          ),
        ),
      );

  Widget _sumRow(String k, double v, {bool minus = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontSize: bold ? 17 : 15,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? AppColors.text : AppColors.muted,
              ),
            ),
          ),
          Text(
            '${minus ? '- ' : ''}${formatInr(v)}',
            style: TextStyle(
              fontSize: bold ? 22 : 15,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: minus ? AppColors.successText : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(InvoiceSummary s) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco,
      child: Column(
        children: [
          _sumRow('Gross total', s.grossTotal),
          if (s.specialDiscount > 0) _sumRow('Special discount', s.specialDiscount, minus: true),
          if (s.schemeDiscount > 0) _sumRow('Scheme discount', s.schemeDiscount, minus: true),
          if (s.freeValue > 0) _sumRow('Free items value', s.freeValue, minus: true),
          if (s.returnCredit > 0) _sumRow('Return credit', s.returnCredit, minus: true),
          if (s.totalSavings > 0) _sumRow('Total savings', s.totalSavings, minus: true),
          const Divider(height: 24, color: AppColors.border),
          _sumRow('Net payable', s.netPayable, bold: true),
        ],
      ),
    );
  }
}