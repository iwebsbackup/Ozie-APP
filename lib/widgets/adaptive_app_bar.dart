import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shining_border_button.dart';

/// Header action that collapses by itself when space is tight:
/// full label -> short label -> icon only. The title is never pushed out.
class AdaptiveHeaderAction {
  final String label;
  final String shortLabel;
  final IconData icon;
  final VoidCallback onPressed;
  const AdaptiveHeaderAction({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.onPressed,
  });
}

/// Global header: fits phones (small/big), foldables (cover + unfolded) and
/// tablets. It measures its own real width (LayoutBuilder), so it also works
/// inside the device_lab frame / split-screen / hinge layouts.
///
/// - title shrinks (FittedBox) instead of being covered by actions
/// - [primaryAction] collapses full -> short -> icon
/// - bar height follows text scale a little, so big fonts never clip
class AdaptiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final AdaptiveHeaderAction? primaryAction;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final double titleSpacing;

  /// Width kept free for the title before any action may use space.
  final double titleMinWidth;

  /// Width of each icon button in [actions] (used for space maths).
  final double actionWidth;

  const AdaptiveAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.primaryAction,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
    this.titleSpacing = 16,
    this.titleMinWidth = 112,
    this.actionWidth = 48,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  // Rough text width at 13sp semi-bold + button padding/border.
  static double _buttonWidth(String label) => label.length * 7.6 + 28;

  Widget? _primary(BuildContext context, double width) {
    final a = primaryAction;
    if (a == null) return null;
    final fg = foregroundColor ?? Theme.of(context).colorScheme.onSurface;

    final used = (leading != null ? 56.0 : 0.0) +
        titleSpacing +
        titleMinWidth +
        actions.length * actionWidth +
        12;
    final space = width - used;

    if (space >= _buttonWidth(a.label)) {
      return _pad(ShiningBorderButton(onPressed: a.onPressed, label: a.label));
    }
    if (space >= _buttonWidth(a.shortLabel)) {
      return _pad(
          ShiningBorderButton(onPressed: a.onPressed, label: a.shortLabel));
    }
    return IconButton(
      tooltip: a.label,
      icon: Icon(a.icon, color: fg),
      onPressed: a.onPressed,
    );
  }

  Widget _pad(Widget w) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: w,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final primary = _primary(context, c.maxWidth);
        return AppBar(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          systemOverlayStyle: systemOverlayStyle,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: leading,
          titleSpacing: titleSpacing,
          // Title takes whatever is left and scales down if still too wide.
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: title,
          ),
          actions: [
            if (primary != null) ...[primary, const SizedBox(width: 4)],
            ...actions,
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}
