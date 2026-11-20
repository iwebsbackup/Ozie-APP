import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../widgets/app_widgets.dart';
import 'where_is_my_order_screen.dart';

/// Full-green "order placed" screen: animated tick, order details below,
/// then auto-moves to [WhereIsMyOrderScreen] after ~3 seconds.
class OrderSuccessScreen extends StatefulWidget {
  final PlaceOrderResult result;
  final String fallbackMethod;

  const OrderSuccessScreen({
    super.key,
    required this.result,
    this.fallbackMethod = '',
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF0C831F);
  static const Duration _stay = Duration(milliseconds: 3200);

  late final AnimationController _c;
  late final Animation<double> _circle;
  late final Animation<double> _tick;
  late final Animation<double> _ring;
  late final Animation<double> _titleFade;
  late final Animation<double> _detailsFade;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _circle = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
    );
    _tick = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 0.65, curve: Curves.easeOut),
    );
    _ring = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.35, 0.9, curve: Curves.easeOut),
    );
    _titleFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOut),
    );
    _detailsFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );
    _c.forward();
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
    _timer = Timer(_stay, _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => WhereIsMyOrderScreen(
          placed: widget.result,
          fallbackMethod: widget.fallbackMethod,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final method = r.paymentMethod.isEmpty ? widget.fallbackMethod : r.paymentMethod;
    return PopScope(
      canPop: false, // no going back to checkout mid-animation
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _green,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tickBadge(),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _titleFade,
                      child: Column(
                        children: [
                          const Text(
                            'Order placed',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            r.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _detailsFade,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(_detailsFade),
                        child: _details(r, method),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FadeTransition(
                      opacity: _detailsFade,
                      child: TextButton(
                        onPressed: _goNext,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Taking you to your order...  Skip',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tickBadge() {
    const size = 124.0;
    return SizedBox(
      width: size * 1.7,
      height: size * 1.7,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final ringT = _ring.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // expanding ripple
              Opacity(
                opacity: (1 - ringT).clamp(0.0, 1.0) * 0.35,
                child: Container(
                  width: size * (1 + 0.6 * ringT),
                  height: size * (1 + 0.6 * ringT),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // white disc
              Transform.scale(
                scale: _circle.value.clamp(0.0, 1.2),
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CustomPaint(
                    painter: _TickPainter(progress: _tick.value, color: _green),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _details(PlaceOrderResult r, String method) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          _row('Order no.', r.orderId.isEmpty ? '-' : r.orderId),
          _divider(),
          _row('Amount', formatInr(r.total), big: true),
          _divider(),
          _row('Payment', method.isEmpty ? '-' : method),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.2));

  Widget _row(String k, String v, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: big ? 18 : 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a check mark that "writes itself" as [progress] goes 0 -> 1.
class _TickPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _TickPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.27, h * 0.53)
      ..lineTo(w * 0.44, h * 0.69)
      ..lineTo(w * 0.74, h * 0.35);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.085
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TickPainter old) =>
      old.progress != progress || old.color != color;
}
