import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/razorpay_service.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import 'order_success_screen.dart';

/// Checkout: loads `v1/retailer/checkout?action=get_summary`, lets the
/// retailer pick a payment method and places the order with `place_order`.
/// Online payments go through Razorpay first, then the order is placed.
/// Pops with `true` when the order was placed (cart is cleared server side).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _PayMethod {
  final String value; // exact string the API expects
  final String label;
  final String hint;
  final IconData icon;
  const _PayMethod(this.value, this.label, this.hint, this.icon);
}

const List<_PayMethod> _kMethods = [
  _PayMethod('Online', 'Pay Online', 'UPI, card or net banking',
      Icons.account_balance_wallet_outlined),
  _PayMethod('Credit', 'Use Credit Limit', 'Deducted from available credit',
      Icons.credit_score_outlined),
  _PayMethod('Cash on Delivery', 'Cash on Delivery',
      'Pay when order arrives', Icons.payments_outlined),
];

const Color _tint = Color(0xFFE8F1FC);
const Color _tintSoft = Color(0xFFF4F8FE);

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutSummary? _data;
  String? _error;
  bool _loading = true;
  bool _placing = false;
  String _method = 'Online';

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
      final next = await RetailerService.getCheckoutSummary();
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

  bool _creditShortFor(CheckoutSummary d) => d.payableAmount > d.availableCredit;

  bool get _creditShort {
    final d = _data;
    if (d == null) return false;
    return _method == 'Credit' && _creditShortFor(d);
  }

  bool get _canPlace =>
      !_placing && _data != null && _data!.payableAmount > 0 && !_creditShort;

  Future<void> _placeOrder() async {
    final d = _data;
    if (d == null || !_canPlace) return;
    setState(() => _placing = true);

    // Online: collect money via Razorpay FIRST, then place the order.
    String? paymentId;
    if (_method == 'Online') {
      final out = await RazorpayService.pay(
        amount: d.payableAmount,
        description: 'Ozie order payment',
        contact: d.billing.contact.isNotEmpty
            ? d.billing.contact
            : d.shipping.contact,
      );
      if (!mounted) return;
      if (!out.success) {
        setState(() => _placing = false);
        if (!out.cancelled) {
          showStatus(context, out.error ?? 'Payment failed.', error: true);
        }
        return;
      }
      paymentId = out.paymentId;
    }

    try {
      final res = await RetailerService.placeOrder(
        paymentMethod: _method,
        shippingName: d.shipping.name.isNotEmpty ? d.shipping.name : 'Retailer',
        shippingCity: d.shipping.city.isNotEmpty ? d.shipping.city : 'City',
      );
      if (!mounted) return;
      setState(() => _placing = false);
      // Green success screen -> auto-moves to "Where is my order".
      // `result: true` tells the cart the order was placed (reload it).
      Navigator.of(context).pushReplacement<void, bool>(
        MaterialPageRoute<void>(
          builder: (_) =>
              OrderSuccessScreen(result: res, fallbackMethod: _method),
        ),
        result: true,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
      showStatus(
        context,
        paymentId == null
            ? e.message
            : 'Payment received (ID: $paymentId) but order failed: ${e.message}. '
                'Contact support with this payment ID.',
        error: true,
      );
    }
  }

  Widget _kv(String k, String v, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(k, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const Spacer(),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          'Checkout',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: AppColors.text,
          ),
          onPressed: _placing ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: _body(),
      bottomNavigationBar: _data == null ? null : _bottom(_data!),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final d = _data!;
    final same = d.billing.oneLine.trim() == d.shipping.oneLine.trim();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _sectionTitle('Delivery address'),
          _addressCard(
            icon: Icons.location_on_outlined,
            a: d.shipping,
            showName: true,
            footer: same ? 'Billing address is the same' : null,
          ),
          if (!same) ...[
            const SizedBox(height: 16),
            _sectionTitle('Billing address'),
            _addressCard(
              icon: Icons.receipt_long_outlined,
              a: d.billing,
              showName: false,
            ),
          ],
          const SizedBox(height: 20),
          _sectionTitle('Payment method'),
          for (final m in _kMethods) _methodTile(m, d),
          const SizedBox(height: 12),
          _sectionTitle('Order summary'),
          _summaryCard(d),
          const SizedBox(height: 16),
          if (_method == 'Online') _secureNote(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      );

  Widget _iconBadge(IconData icon, {bool active = true, double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? _tint : AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        color: active ? AppColors.blue : AppColors.muted,
      ),
    );
  }

  BoxDecoration _cardDeco({bool selected = false}) => BoxDecoration(
        color: selected ? _tintSoft : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.blue : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      );

  Widget _addressCard({
    required IconData icon,
    required CheckoutAddress a,
    required bool showName,
    String? footer,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBadge(icon),
          const SizedBox(width: 12),
          Expanded(
            child: a.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'No address on file. Update it from My Account.',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showName && a.name.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            a.name,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      Text(
                        a.oneLine,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.text,
                        ),
                      ),
                      if (a.contact.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.call_outlined,
                                size: 14, color: AppColors.muted),
                            const SizedBox(width: 5),
                            Text(
                              a.contact,
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                size: 14, color: AppColors.green),
                            const SizedBox(width: 5),
                            Text(
                              footer,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.successText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _methodTile(_PayMethod m, CheckoutSummary d) {
    final selected = _method == m.value;
    final isCredit = m.value == 'Credit';
    final short = isCredit && _creditShortFor(d);
    final enabled = !_placing && !short;

    final String hint;
    if (isCredit) {
      hint = short
          ? 'Available ${formatInr(d.availableCredit)} - not enough'
          : 'Available ${formatInr(d.availableCredit)}';
    } else {
      hint = m.hint;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: short ? 0.55 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => setState(() => _method = m.value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _cardDeco(selected: selected),
            child: Row(
              children: [
                _iconBadge(m.icon, active: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          color: short
                              ? AppColors.dangerText
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.blue : AppColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(CheckoutSummary d) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: _cardDeco(),
      child: Column(
        children: [
          _kv('Pay via', _method),
          if (_method == 'Credit')
            _kv(
              'Credit left after order',
              formatInr(d.availableCredit - d.payableAmount),
              color: _creditShortFor(d)
                  ? AppColors.dangerText
                  : AppColors.successText,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            children: [
              const Text(
                'Total payable',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                formatInr(d.payableAmount),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _secureNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(
          AppConfig.razorpayIsTest
              ? 'Razorpay TEST mode - no real money is charged'
              : 'Secure payment powered by Razorpay',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }

  Widget _bottom(CheckoutSummary d) {
    final online = _method == 'Online';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_creditShort)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.dangerText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Credit ${formatInr(d.availableCredit)} is less than '
                        '${formatInr(d.payableAmount)}. Pick another method.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.dangerText),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canPlace ? _placeOrder : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _placing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(online ? Icons.lock_outline : Icons.check, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            online
                                ? 'Pay ${formatInr(d.payableAmount)}'
                                : 'Place order - ${formatInr(d.payableAmount)}',
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
