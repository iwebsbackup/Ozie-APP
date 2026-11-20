import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'test_models.dart';

void testToast(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.dangerText : AppColors.text,
      behavior: SnackBarBehavior.floating,
    ));
}

String testErr(Object e) => e is ApiException ? e.message : 'Something went wrong.';

class TestStatusChip extends StatelessWidget {
  final String status;
  const TestStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Accepted':
      case 'Delivered':
        bg = AppColors.successBg;
        fg = AppColors.successText;
        break;
      case 'Rejected':
        bg = AppColors.dangerBg;
        fg = AppColors.dangerText;
        break;
      case 'Started':
        bg = const Color(0xFFFFE8CC);
        fg = const Color(0xFFB45309);
        break;
      case 'Assigned':
        bg = const Color(0xFFDCEBFF);
        fg = AppColors.blue;
        break;
      default:
        bg = const Color(0xFFFFF3D6);
        fg = const Color(0xFF9A6700);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status == 'Started' ? 'On the way' : status,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class TestCard extends StatelessWidget {
  final Widget child;
  const TestCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class TestLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const TestLine(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: AppColors.text)),
            ),
          ],
        ),
      );
}

/// Order card used on retailer / distributor screens.
class TestOrderCard extends StatelessWidget {
  final TestOrder o;
  final bool showRetailer;
  final bool showTracker;
  final List<Widget> actions;
  const TestOrderCard({
    super.key,
    required this.o,
    this.showRetailer = false,
    this.showTracker = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final src = o.addressSource == 'current_location'
        ? 'Current location'
        : 'Saved address';
    return TestCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${o.orderNumber}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              TestStatusChip(o.status),
            ],
          ),
          if (showTracker) ...[
            const SizedBox(height: 12),
            TestOrderTracker(o),
            const SizedBox(height: 4),
          ],
          if (showRetailer)
            TestLine(Icons.storefront_outlined,
                '${o.retailerName}  •  ${o.retailerMobile}'),
          TestLine(Icons.inventory_2_outlined,
              '${o.productName}  ×  ${o.quantity}  @  ${formatInr(o.price)}'),
          TestLine(Icons.currency_rupee, 'Total ${formatInr(o.total)}'),
          TestLine(Icons.place_outlined, o.address),
          if (o.lat != null && o.lng != null)
            TestLine(Icons.my_location,
                '${o.lat!.toStringAsFixed(5)}, ${o.lng!.toStringAsFixed(5)}  ($src)'),
          if (o.isAssigned)
            TestLine(Icons.delivery_dining,
                '${o.isDelivered ? 'Delivered by' : 'Delivery boy'}: ${o.boyName ?? '-'} (${o.boyMobile ?? '-'})  •  ${o.isOnTheWay ? 'On the way' : (o.deliveryStatus ?? '')}'),
          if (o.isDelivered) ...[
            if ((o.deliveredAt ?? '').isNotEmpty)
              TestLine(Icons.event_available_outlined,
                  'Delivered on ${o.deliveredAt}'),
            TestLine(Icons.route_outlined,
                'Distance travelled: ${fmtDistanceM(o.distanceM)}'),
            TestLine(Icons.timer_outlined,
                'Time taken: ${fmtDurationS(o.durationS)}'),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: actions),
          ],
        ],
      ),
    );
  }
}

class TestEmpty extends StatelessWidget {
  final String text;
  const TestEmpty(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
      );
}

class TestError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const TestError(this.message, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.dangerText)),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

/// Small filled button used for Accept / Assign / etc.
class TestBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool outlined;
  const TestBtn(this.label,
      {super.key,
      required this.onPressed,
      this.color = AppColors.blue,
      this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: outlined
            ? OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color),
                    shape: shape),
                child: Text(label))
            : ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: shape),
                child: Text(label)),
      ),
    );
  }
}


/// Placed -> Accepted -> Assigned -> Delivered progress for one order.
class TestOrderTracker extends StatelessWidget {
  final TestOrder o;
  const TestOrderTracker(this.o, {super.key});

  static const _steps = ['Placed', 'Accepted', 'Assigned', 'On the way', 'Delivered'];

  int get _current {
    if (o.deliveryStatus == 'Delivered') return 4;
    if (o.deliveryStatus == 'Started') return 3;
    if (o.isAssigned) return 2;
    if (o.status == 'Accepted') return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (o.status == 'Rejected') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Order rejected by distributor.',
            style: TextStyle(fontSize: 12, color: AppColors.dangerText)),
      );
    }
    final cur = _current;
    return Row(
      children: List.generate(_steps.length, (i) {
        final done = i <= cur;
        final lineOn = Colors.green.shade400;
        final lineOff = AppColors.border;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == 0
                          ? Colors.transparent
                          : (i <= cur ? lineOn : lineOff),
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AppColors.green : AppColors.border,
                    ),
                    child: Icon(done ? Icons.check : Icons.circle,
                        size: done ? 14 : 6,
                        color: done ? Colors.white : AppColors.muted),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == _steps.length - 1
                          ? Colors.transparent
                          : (i < cur ? lineOn : lineOff),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_steps[i],
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      color: done ? AppColors.text : AppColors.muted)),
            ],
          ),
        );
      }),
    );
  }
}

/// Big tappable tile for the Quick Actions grid.
class TestActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const TestActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCEBFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.blue),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared top bar for the test homes (no bottom menu in test mode).
PreferredSizeWidget testAppBar(BuildContext context,
    {required String title, List<Widget> actions = const []}) {
  return AppBar(
    backgroundColor: AppColors.bg,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    titleSpacing: 16,
    title: Text(title,
        style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
    actions: actions,
  );
}
