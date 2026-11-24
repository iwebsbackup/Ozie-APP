import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Window size classes (Material 3 / Android guidance).
/// compact  : < 600dp  -> phones (small, medium, big), folded foldables
/// medium   : 600-839  -> small tablets, unfolded foldables
/// expanded : >= 840   -> big tablets, large unfolded foldables
enum WindowClass { compact, medium, expanded }

const double kMediumBreakpoint = 600;
const double kExpandedBreakpoint = 840;

/// Widest the app content may grow. Phones are never affected.
const double kMediumMaxWidth = 720;
const double kExpandedMaxWidth = 840;

/// Text scale limits. System font size still works, but never breaks layouts.
const double kMinTextScale = 0.9;
const double kMaxTextScale = 1.15;

/// Content width for a given window width.
double contentWidthFor(double w) {
  if (w >= kExpandedBreakpoint) return kExpandedMaxWidth;
  if (w >= kMediumBreakpoint) return w < kMediumMaxWidth ? w : kMediumMaxWidth;
  return w;
}

/// Wrap the whole app once (MaterialApp.builder).
/// - clamps system font scale
/// - on tablets/foldables centers content and limits its width
/// - re-reports the REAL content size via MediaQuery, so every
///   `MediaQuery.sizeOf(context)` in the app is correct
/// - rebuilds live on fold/unfold, rotation, split-screen resize
class ResponsiveScope extends StatefulWidget {
  final Widget child;
  const ResponsiveScope({super.key, required this.child});

  @override
  State<ResponsiveScope> createState() => _ResponsiveScopeState();
}

class _ResponsiveScopeState extends State<ResponsiveScope> {
  bool? _largeScreen;

  /// Phones stay portrait-only. Tablets / unfolded foldables (shortest side
  /// >= 600dp) may rotate, so they never get a stretched portrait-only UI.
  void _applyOrientation(Size screen) {
    final large = screen.shortestSide >= kMediumBreakpoint;
    if (large == _largeScreen) return;
    _largeScreen = large;
    SystemChrome.setPreferredOrientations(
      large
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    _applyOrientation(mq.size);
    final w = contentWidthFor(mq.size.width);
    // Side insets (cutout / hinge area) only matter when full width is used.
    final sideCapped = w < mq.size.width;
    final data = mq.copyWith(
      size: Size(w, mq.size.height),
      textScaler: mq.textScaler.clamp(
        minScaleFactor: kMinTextScale,
        maxScaleFactor: kMaxTextScale,
      ),
      padding: sideCapped
          ? mq.padding.copyWith(left: 0, right: 0)
          : mq.padding,
      viewPadding: sideCapped
          ? mq.viewPadding.copyWith(left: 0, right: 0)
          : mq.viewPadding,
    );
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: w,
          child: MediaQuery(data: data, child: widget.child),
        ),
      ),
    );
  }
}

/// `context.sw`, `context.windowClass`, `context.gridColumns(...)`, ...
extension ResponsiveContext on BuildContext {
  Size get screen => MediaQuery.sizeOf(this);

  /// Real content width (already capped on tablets by [ResponsiveScope]).
  double get sw => screen.width;
  double get sh => screen.height;

  WindowClass get windowClass {
    final w = sw;
    if (w >= kExpandedBreakpoint) return WindowClass.expanded;
    if (w >= kMediumBreakpoint) return WindowClass.medium;
    return WindowClass.compact;
  }

  bool get isCompact => windowClass == WindowClass.compact;
  bool get isTablet => windowClass != WindowClass.compact;

  /// Small phones (<= 360dp wide).
  bool get isSmallPhone => sw <= 360;

  /// Page side padding that grows a bit on bigger screens.
  double get pagePad => isSmallPhone ? 12 : (isCompact ? 16 : 24);

  /// Current (clamped) font scale.
  double get textScale => MediaQuery.textScalerOf(this).scale(1.0);

  /// Scale a design size (made on 392dp phone) by width; stays near [size].
  double fit(double size, {double? min, double? max}) {
    final v = size * (sw / 392.0);
    return v.clamp(min ?? size * 0.82, max ?? size * 1.18).toDouble();
  }

  /// For fixed-height boxes that hold text: grows with font scale.
  double fitText(double size) => size * textScale;

  /// Columns for a grid: as many as fit with tiles >= [minTile] wide.
  int gridColumns({
    double minTile = 160,
    double pad = 32,
    double gap = 12,
    int min = 2,
    int max = 5,
  }) {
    final n = ((sw - pad + gap) / (minTile + gap)).floor();
    return n.clamp(min, max);
  }

  /// Width of one grid tile for [columns].
  double gridTileWidth(int columns, {double pad = 32, double gap = 12}) =>
      (sw - pad - gap * (columns - 1)) / columns;
}
