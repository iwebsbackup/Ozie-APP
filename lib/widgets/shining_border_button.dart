import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_widgets.dart';

/// Outlined button whose border has a light "shine" sweeping around it.
class ShiningBorderButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final Duration duration;
  final double radius;
  final double borderWidth;
  final double height;
  final double fontSize;
  final double horizontalPadding;
  final Color backgroundColor;
  final bool enabled;
  final bool loading;

  const ShiningBorderButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.duration = const Duration(milliseconds: 2400),
    this.radius = 8,
    this.borderWidth = 1.6,
    this.height = 34,
    this.fontSize = 13,
    this.horizontalPadding = 12,
    this.backgroundColor = AppColors.bg,
    this.enabled = true,
    this.loading = false,
  });

  @override
  State<ShiningBorderButton> createState() => _ShiningBorderButtonState();
}

class _ShiningBorderButtonState extends State<ShiningBorderButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _content(Color color) {
    if (widget.loading) {
      return SizedBox(
        width: widget.fontSize + 1,
        height: widget.fontSize + 1,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    // Shrinks the label instead of overflowing on narrow screens.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        widget.label,
        maxLines: 1,
        style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    if (!widget.enabled) {
      return Container(
        height: widget.height + widget.borderWidth * 2,
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: AppColors.border),
        ),
        child: _content(AppColors.muted),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Container(
            padding: EdgeInsets.all(widget.borderWidth),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              gradient: SweepGradient(
                transform: GradientRotation(_ctrl.value * 2 * math.pi),
                colors: const [
                  AppColors.blue,
                  AppColors.blue,
                  AppColors.green,
                  Colors.white,
                  AppColors.green,
                  AppColors.blue,
                  AppColors.blue,
                ],
                stops: const [0.0, 0.55, 0.70, 0.78, 0.86, 0.95, 1.0],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x261A6FD4), blurRadius: 8),
              ],
            ),
            child: child,
          );
        },
        child: Material(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(r - widget.borderWidth),
          child: InkWell(
            onTap: widget.loading ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(r - widget.borderWidth),
            child: Container(
              height: widget.height,
              padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
              alignment: Alignment.center,
              child: _content(AppColors.blue),
            ),
          ),
        ),
      ),
    );
  }
}


/// Wraps [child] with an animated, light-sweeping border.
/// [child] should paint its own background (radius = [radius] - [borderWidth]).
class ShiningBorder extends StatefulWidget {
  final Widget child;
  final double radius;
  final double borderWidth;
  final Duration duration;

  const ShiningBorder({
    super.key,
    required this.child,
    this.radius = 12,
    this.borderWidth = 1.6,
    this.duration = const Duration(milliseconds: 2600),
  });

  @override
  State<ShiningBorder> createState() => _ShiningBorderState();
}

class _ShiningBorderState extends State<ShiningBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Container(
            padding: EdgeInsets.all(widget.borderWidth),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: SweepGradient(
                transform: GradientRotation(_ctrl.value * 2 * math.pi),
                colors: const [
                  AppColors.blue,
                  AppColors.blue,
                  AppColors.green,
                  Colors.white,
                  AppColors.green,
                  AppColors.blue,
                  AppColors.blue,
                ],
                stops: const [0.0, 0.55, 0.70, 0.78, 0.86, 0.95, 1.0],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x261A6FD4), blurRadius: 8),
              ],
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}