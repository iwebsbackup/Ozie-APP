import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';
import 'invoice_view_screen.dart';

/// "Where is my order": the order just placed (with a status timeline) on top,
/// then the retailer's recent approved orders.
class WhereIsMyOrderScreen extends StatefulWidget {
  /// Order that was just placed (null when opened from a menu).
  final PlaceOrderResult? placed;
  final String fallbackMethod;

  const WhereIsMyOrderScreen({
    super.key,
    this.placed,
    this.fallbackMethod = '',
  });

  @override
  State<WhereIsMyOrderScreen> createState() => _WhereIsMyOrderScreenState();
}

class _Step {
  final String title;
  final String doneText;
  final String pendingText;
  final IconData icon;
  const _Step(this.title, this.doneText, this.pendingText, this.icon);
}

const List<_Step> _kSteps = [
  _Step('Order placed', 'We have received your order',
      'Placing your order', Icons.receipt_long_outlined),
  _Step('Approved', 'Distributor approved your order',
      'Waiting for distributor approval', Icons.verified_outlined),
  _Step('Packing', 'Your items are packed', 'Items will be packed soon',
      Icons.inventory_2_outlined),
  _Step('Dispatched', 'Order is on the way', 'Will be dispatched after packing',
      Icons.local_shipping_outlined),
  _Step('Delivered', 'Order delivered', 'Delivery pending',
      Icons.home_outlined),
];

class _WhereIsMyOrderScreenState extends State<WhereIsMyOrderScreen> {
  static const Color _green = Color(0xFF0C831F);

  bool _loading = true;
  String? _error;
  List<ApprovedOrder> _orders = [];

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
      final page = await RetailerService.getOrders(limit: 20);
      if (!mounted) return;
      setState(() {
        _orders = page.orders;
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

  ApprovedOrder? get _liveMatch {
    final p = widget.placed;
    if (p == null || p.orderId.isEmpty) return null;
    for (final o in _orders) {
      if (o.invoiceNumber == p.orderId) return o;
    }
    return null;
  }

  /// How many timeline steps are finished for the just-placed order.
  int get _doneCount {
    final method =
        (widget.placed?.paymentMethod.isNotEmpty == true
                ? widget.placed!.paymentMethod
                : widget.fallbackMethod)
            .toLowerCase();
    final live = _liveMatch;
    final approved = method == 'online' ||
        (live != null && live.invoiceStatus.toLowerCase() == 'approved');
    return approved ? 2 : 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          'Where is my order',
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
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (widget.placed != null) ...[
              _latestCard(widget.placed!),
              const SizedBox(height: 22),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                'Recent orders',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
            ..._recent(),
          ],
        ),
      ),
    );
  }

  // ───────────── latest order + timeline ─────────────

  Widget _latestCard(PlaceOrderResult p) {
    final done = _doneCount;
    final method = p.paymentMethod.isEmpty ? widget.fallbackMethod : p.paymentMethod;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: _green,
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order placed',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.orderId.isEmpty ? '-' : p.orderId,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatInr(p.total),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Column(
              children: [
                for (var i = 0; i < _kSteps.length; i++)
                  _stepRow(i, done, last: i == _kSteps.length - 1),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined,
                    size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                  'Payment: ${method.isEmpty ? '-' : method}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(int i, int done, {required bool last}) {
    final s = _kSteps[i];
    final isDone = i < done;
    final isCurrent = i == done;
    final Color dot = isDone
        ? _green
        : (isCurrent ? AppColors.blue : AppColors.border);
    // Line below this step is green once the NEXT step is done too.
    final Color lineColor = (i + 1 < done) ? _green : AppColors.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isDone ? _green : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: dot, width: 2),
                  ),
                  child: Icon(
                    isDone ? Icons.check : s.icon,
                    size: 15,
                    color: isDone
                        ? Colors.white
                        : (isCurrent ? AppColors.blue : AppColors.muted),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: lineColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 4 : 16, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: (isDone || isCurrent)
                          ? AppColors.text
                          : AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDone ? s.doneText : s.pendingText,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isCurrent ? AppColors.blue : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── recent orders ─────────────

  List<Widget> _recent() {
    if (_loading && _orders.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null && _orders.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      ];
    }
    if (_orders.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No approved orders yet.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      ];
    }
    return [for (final o in _orders) _orderCard(o)];
  }

  Widget _orderCard(ApprovedOrder o) {
    final label = (o.invoiceNumber?.isNotEmpty == true)
        ? o.invoiceNumber!
        : (o.orderNumber.isNotEmpty ? o.orderNumber : 'Order #${o.id}');
    final paid = o.isPaid;
    final badgeBg = paid ? AppColors.successBg : const Color(0xFFFFF1D6);
    final badgeFg = paid ? AppColors.successText : const Color(0xFF8A5A00);
    final isNew = widget.placed != null && o.invoiceNumber == widget.placed!.orderId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: (o.invoiceNumber?.isNotEmpty == true)
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        InvoiceViewScreen(invoiceNumber: o.invoiceNumber!),
                  ),
                )
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isNew ? _green : AppColors.border,
              width: isNew ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_shipping_outlined,
                    size: 21, color: AppColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      o.formattedDate ?? formatDate(o.createdAt),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatInr(o.total),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      o.paymentBadge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeFg,
                      ),
                    ),
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
