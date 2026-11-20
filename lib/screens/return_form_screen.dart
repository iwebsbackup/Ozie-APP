import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/retailer_service.dart';
import '../core/returns_models.dart';
import '../widgets/app_widgets.dart';

/// New return request. Pick invoice -> pick items + qty (bottles) -> reason
/// + resolution -> submit. Pops with `true` on success.
/// API: GET returns?action=search_invoices|fetch_invoice,
///      POST returns action=submit_return.
class ReturnFormScreen extends StatefulWidget {
  const ReturnFormScreen({super.key});

  @override
  State<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnFormScreenState extends State<ReturnFormScreen> {
  static const Color _header = Color(0xFF7C3AED); // same as My Returns
  static const List<String> _reasons = [
    'Damaged goods',
    'Expired goods',
    'Wrong product delivered',
    'Short delivery',
    'Other',
  ];
  static const List<String> _resolutions = ['Credit Note', 'Replacement'];

  final _invCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Timer? _debounce;

  List<ReturnInvoiceSuggestion> _suggestions = [];
  bool _searching = false;

  ReturnInvoiceDetail? _invoice;
  bool _loadingInvoice = false;
  // product row index -> bottles to return
  final Map<int, int> _qty = {};

  String _reason = _reasons.first;
  String _resolution = _resolutions.first;
  bool _submitting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _invCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onInvoiceChanged(String v) {
    _debounce?.cancel();
    if (_invoice != null && v.trim() != _invoice!.invoiceNumber) {
      setState(() {
        _invoice = null;
        _qty.clear();
      });
    }
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final r = await RetailerService.searchReturnInvoices(q);
        if (!mounted) return;
        setState(() {
          _suggestions = r;
          _searching = false;
        });
      } on ApiException {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  Future<void> _pickInvoice(ReturnInvoiceSuggestion s) async {
    FocusScope.of(context).unfocus();
    _invCtrl.text = s.invoiceNumber;
    setState(() {
      _suggestions = [];
      _loadingInvoice = true;
      _invoice = null;
      _qty.clear();
    });
    try {
      final d = await RetailerService.fetchReturnInvoice(s.invoiceNumber);
      if (!mounted) return;
      setState(() {
        _invoice = d;
        _loadingInvoice = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingInvoice = false);
      showStatus(context, e.message, error: true);
    }
  }

  double get _credit {
    final inv = _invoice;
    if (inv == null) return 0;
    var sum = 0.0;
    _qty.forEach((i, q) {
      if (i < inv.items.length) sum += q * inv.items[i].bottlePrice;
    });
    return sum;
  }

  int get _selectedCount => _qty.values.where((q) => q > 0).length;

  void _setQty(int i, int q, int max) {
    final v = q.clamp(0, max);
    setState(() {
      if (v == 0) {
        _qty.remove(i);
      } else {
        _qty[i] = v;
      }
    });
  }

  Future<void> _submit() async {
    final inv = _invoice;
    if (inv == null) {
      showStatus(context, 'Select an invoice first.', error: true);
      return;
    }
    if (_selectedCount == 0) {
      showStatus(context, 'Select at least one item to return.', error: true);
      return;
    }
    final items = <Map<String, dynamic>>[];
    _qty.forEach((i, q) {
      if (q <= 0 || i >= inv.items.length) return;
      final it = inv.items[i];
      items.add({
        'product_id': it.productId,
        'product_name': it.productName,
        'return_quantity': q,
        'original_price': it.bottlePrice,
        'units_per_case': it.unitsPerCase,
      });
    });

    setState(() => _submitting = true);
    try {
      final msg = await RetailerService.submitReturn(
        invoiceNumber: inv.invoiceNumber,
        reason: _reason,
        resolutionType: _resolution,
        creditAmount: _credit,
        items: items,
        description: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      showStatus(context, msg);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showStatus(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _header,
      appBar: AppBar(
        title: const Text('New Return'),
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
      bottomNavigationBar: _invoice == null ? null : _footer(),
      body: Column(
        children: [
          Container(
            color: _header,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: TextField(
              controller: _invCtrl,
              onChanged: _onInvoiceChanged,
              decoration: inputDecoration(hint: 'Search invoice number').copyWith(
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
                suffixIcon: _searching || _loadingInvoice
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
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
    final inv = _invoice;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        if (_suggestions.isNotEmpty) _suggestionList(),
        if (inv == null && _suggestions.isEmpty && !_loadingInvoice) _emptyHint(),
        if (inv != null) ...[
          _invoiceCard(inv),
          const SizedBox(height: 16),
          _section('Items to return', Icons.inventory_2_outlined, [
            const Text(
              'Enter quantity in bottles.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            if (inv.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No items found on this invoice.',
                    style: TextStyle(color: AppColors.muted)),
              ),
            for (var i = 0; i < inv.items.length; i++) _itemRow(i),
          ]),
          const SizedBox(height: 16),
          _section('Reason', Icons.report_gmailerrorred_outlined, [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _reasons) _pickChip(r, _reason == r, () => setState(() => _reason = r)),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          _section('Resolution', Icons.swap_horiz_rounded, [
            Row(
              children: [
                for (var k = 0; k < _resolutions.length; k++) ...[
                  if (k > 0) const SizedBox(width: 10),
                  Expanded(child: _resolutionTile(_resolutions[k])),
                ],
              ],
            ),
          ]),
          const SizedBox(height: 16),
          _section('Description (optional)', Icons.notes_rounded, [
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: inputDecoration(hint: 'Add details'),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _emptyHint() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _header.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_return_outlined, size: 40, color: _header),
            ),
            const SizedBox(height: 16),
            const Text(
              'Find your invoice',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
            const SizedBox(height: 6),
            const Text(
              'Search the invoice number above, then pick the items you want to return.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      );

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _header.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: _header),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _invoiceCard(ReturnInvoiceDetail inv) {
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
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.receipt_long_outlined, color: AppColors.successText, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selected invoice',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(
                  inv.invoiceNumber,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.green),
        ],
      ),
    );
  }

  Widget _pickChip(String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? _header : AppColors.inputBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _header : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: sel ? Colors.white : AppColors.text,
          ),
        ),
      ),
    );
  }

  Widget _resolutionTile(String r) {
    final sel = _resolution == r;
    final isRepl = r.toLowerCase() == 'replacement';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _resolution = r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? _header.withValues(alpha: 0.08) : AppColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _header : AppColors.border, width: sel ? 1.6 : 1),
        ),
        child: Column(
          children: [
            Icon(
              isRepl ? Icons.swap_horiz_rounded : Icons.account_balance_wallet_outlined,
              color: sel ? _header : AppColors.muted,
            ),
            const SizedBox(height: 6),
            Text(
              r,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? _header : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _suggestions.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _header.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: _header, size: 20),
              ),
              title: Text(_suggestions[i].invoiceNumber,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text(
                '${_suggestions[i].invoiceDate.isEmpty ? '' : '${_suggestions[i].invoiceDate} · '}${formatInr(_suggestions[i].subtotal)}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: () => _pickInvoice(_suggestions[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(int i) {
    final it = _invoice!.items[i];
    final q = _qty[i] ?? 0;
    final max = it.totalBottles;
    Widget stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: onTap == null ? AppColors.inputBg : _header.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: onTap == null ? AppColors.muted : _header),
          ),
        );
    return Container(
      margin: EdgeInsets.only(bottom: i == _invoice!.items.length - 1 ? 0 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: q > 0 ? _header.withValues(alpha: 0.04) : AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q > 0 ? _header : AppColors.border, width: q > 0 ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(it.productName,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(
            '${it.casesOrdered} case × ${it.unitsPerCase} = ${it.totalBottles} bottles'
            ' · ${formatInr(it.bottlePrice)}/bottle',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stepBtn(Icons.remove, q > 0 ? () => _setQty(i, q - 1, max) : null),
              SizedBox(
                width: 48,
                child: Text(
                  '$q',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              stepBtn(Icons.add, q < max ? () => _setQty(i, q + 1, max) : null),
              const Spacer(),
              if (q > 0)
                Text(
                  formatInr(q * it.bottlePrice),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _header,
                    fontSize: 15,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(color: Color(0x141E2A3B), blurRadius: 12, offset: Offset(0, -3)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_selectedCount item(s) · ${_resolution == 'Replacement' ? 'Value' : 'Credit'}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatInr(_credit),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _header,
                minimumSize: const Size(150, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Return',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}