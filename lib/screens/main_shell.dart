import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/models.dart';
import '../core/responsive.dart';
import '../core/push_service.dart';
import '../widgets/adaptive_app_bar.dart';
import '../widgets/app_widgets.dart';
import 'bank_card_screen.dart';
import 'catalog_screen.dart';
import 'notifications_screen.dart';
import 'orderbox_screen.dart';
import 'schemes_screen.dart';
import 'tabs/home_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/settings_tab.dart';

/// App shell after login: top bar (logo + notifications) and bottom menu.
class MainShell extends StatefulWidget {
  final Session session;
  const MainShell({super.key, required this.session});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _schemesReady = false;
  bool _ordersReady = false;
  int _ordersTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PushService.openPendingIfAny(),
    );
  }

  static const List<String> _titles = ['Home', 'Schemes', 'View Orders', 'Settings'];

  /// Home shows logo + app name. Other tabs show the tab name.
  // ---- bottom nav sizing (phones, foldables, tablets) ----
  /// Gap under the bar. SafeArea already lifts the bar above the gesture /
  /// 3-button bar, so only a hairline gap is added there; on devices with no
  /// system inset the bar still floats a little off the screen edge.
  double _navBottomGap(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    if (inset > 0) return 2;
    return context.isSmallPhone ? 4 : 6;
  }

  /// How far (dp) the bar is lowered into the system gesture / 3-button
  /// inset. Bigger = bar sits lower. Set to 0 for the old position.
  static const double _navLowerBy = 8;

  /// Lift above the screen bottom from the system inset. Phones with no
  /// inset get 0 (only the small gap above is used).
  double _navSystemLift(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    if (inset <= 0) return 0;
    return math.max(0, inset - _navLowerBy);
  }

  /// Tab icon size by screen class.
  double _navIconSize(BuildContext context) {
    if (context.isSmallPhone) return 22;
    if (context.isTablet) return 26;
    return 24;
  }

  /// Nav bar width: full width minus margin on phones, capped on wide screens.
  double _navBarWidth(BuildContext context) {
    final margin = context.isSmallPhone ? 12.0 : 16.0;
    final w = context.sw - margin * 2;
    return w > 560 ? 560 : w;
  }

  /// Width of one tab slot (bar minus the gap under the mic, split in 4).
  double _navSlot(BuildContext context) =>
      (_navBarWidth(context) - 76) / 4;

  /// One label size for all tabs (never a mix of big and shrunk labels).
  double _navLabelSize(BuildContext context) {
    final slot = _navSlot(context);
    if (slot < 56) return 10.5;
    if (slot < 66) return 11;
    return 12;
  }

  Widget _buildTitle(Color fg) {
    if (_index == 0) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogoImage(size: 32, radius: 8),
          SizedBox(width: 10),
          Text(
            'Ozie',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      );
    }
    return Text(
      _titles[_index],
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  void _openBankCard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BankCardScreen()),
    );
  }

  void _openCatalog({int? productId, String? productName}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogScreen(
          highlightProductId: productId,
          highlightProductName: productName,
        ),
      ),
    );
  }

  void _selectPage(int i) => setState(() {
        if (i == 1) _schemesReady = true;
        if (i == 2) _ordersReady = true;
        _index = i;
      });

  void _onMicTap() {
    HapticFeedback.lightImpact();
    // Mic opens OrderBox By Ozie (AI voice order, API: v1/retailer/voice-order).
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OrderboxScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_index == 1) _schemesReady = true;
    if (_index == 2) _ordersReady = true;

    final pages = <Widget>[
      HomeTab(
        session: widget.session,
        onViewCatalog: () => _openCatalog(),
        onViewOrders: () => setState(() {
          _ordersReady = true;
          _index = 2;
        }),
      ),
      _schemesReady
          ? SchemesScreen(
              embedded: true,
              onApply: _openCatalog,
            )
          : const SizedBox.shrink(),
      _ordersReady
          ? OrdersTab(
              onTabChanged: (i) {
                if (i != _ordersTab) setState(() => _ordersTab = i);
              },
            )
          : const SizedBox.shrink(),
      SettingsTab(
        session: widget.session,
        onViewCatalog: () => _openCatalog(),
        onViewOrders: () => setState(() {
          _ordersReady = true;
          _index = 2;
        }),
      ),
    ];

    final onOrders = _index == 2;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        // Body runs under the floating nav; the nav blurs what is behind it.
        extendBody: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: ValueListenableBuilder<int>(
            valueListenable: OrdersTab.activeTab,
            builder: (context, tab, _) {
              final fg =
                  onOrders ? OrdersTab.headerForeground(tab) : AppColors.text;
              return AdaptiveAppBar(
                backgroundColor:
                    onOrders ? OrdersTab.headerColor(tab) : AppColors.bg,
                foregroundColor: fg,
                systemOverlayStyle: onOrders && tab == 1
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                // Back arrow only on View Orders tab -> goes back to Home.
                leading: onOrders
                    ? IconButton(
                        tooltip: 'Back',
                        icon: Icon(Icons.arrow_back_rounded, color: fg),
                        onPressed: () => setState(() => _index = 0),
                      )
                    : null,
                titleSpacing: onOrders ? 0 : 16,
                title: _buildTitle(fg),
                // Bank card CTA: full label -> "Apply" -> icon, by free space.
                primaryAction: onOrders
                    ? null
                    : AdaptiveHeaderAction(
                        label: 'Apply For Card',
                        shortLabel: 'Apply',
                        icon: Icons.credit_card_rounded,
                        onPressed: _openBankCard,
                      ),
                actions: [
                  IconButton(
                    tooltip: 'Notifications',
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedNotification01,
                      color: fg,
                    ),
                    onPressed: _openNotifications,
                  ),
                ],
              );
            },
          ),
        ),
        // Nav bar sits above the system gesture/3-button bar (SafeArea), so
        // push the pages up by the same inset (body is extended under the nav).
        body: Padding(
          padding: EdgeInsets.only(
            bottom: _navSystemLift(context),
          ),
          child: IndexedStack(index: _index, children: pages),
        ),
        bottomNavigationBar: SafeArea(
          // Sides only (cutouts / hinge). Bottom is handled by _navSystemLift
          // so the bar can sit a little lower than the full system inset.
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: _navSystemLift(context)),
            child: SizedBox(
          // bar + bump + small bottom gap (system inset comes from SafeArea)
          height: _NavBarShape.totalHeight + _navBottomGap(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: _navBottomGap(context),
                height: _NavBarShape.totalHeight,
                child: Center(
                  child: SizedBox(
                    width: _navBarWidth(context),
                    height: _NavBarShape.totalHeight,
                    child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Bar with a curved bump on top, around the mic.
                    Positioned.fill(
                      child: ClipPath(
                        clipper: _NavBarClipper(),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _NavBarPainter()),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _NavBarShape.barHeight,
                      child: Row(
                        children: [
                          _NavItem(
                            fontSize: _navLabelSize(context),
                            iconSize: _navIconSize(context),
                            label: 'Home',
                            selected: _index == 0,
                            onTap: () => _selectPage(0),
                            icon: (c, s) => HugeIcon(
                                icon: HugeIcons.strokeRoundedHome03, color: c, size: s),
                          ),
                          _NavItem(
                            fontSize: _navLabelSize(context),
                            iconSize: _navIconSize(context),
                            label: 'Schemes',
                            selected: _index == 1,
                            onTap: () => _selectPage(1),
                            icon: (c, s) => Icon(
                                _index == 1
                                    ? Icons.local_offer
                                    : Icons.local_offer_outlined,
                                color: c, size: s),
                          ),
                          // Gap under the mic button.
                          const SizedBox(width: 76),
                          _NavItem(
                            fontSize: _navLabelSize(context),
                            iconSize: _navIconSize(context),
                            // "View Orders" only when the slot is wide enough,
                            // so every label keeps the same size.
                            label: _navSlot(context) >= 80
                                ? 'View Orders'
                                : 'Orders',
                            selected: _index == 2,
                            onTap: () => _selectPage(2),
                            icon: (c, s) => HugeIcon(
                                icon: HugeIcons.strokeRoundedShoppingBag01,
                                color: c, size: s),
                          ),
                          _NavItem(
                            fontSize: _navLabelSize(context),
                            iconSize: _navIconSize(context),
                            label: 'Settings',
                            selected: _index == 3,
                            onTap: () => _selectPage(3),
                            icon: (c, s) => HugeIcon(
                                icon: HugeIcons.strokeRoundedSettings02,
                                color: c, size: s),
                          ),
                        ],
                      ),
                    ),
                    // Mic button centered inside the bump.
                    Positioned(
                      top: _NavBarShape.micTop,
                      left: 0,
                      right: 0,
                      child: Center(child: _MicButton(onTap: _onMicTap)),
                    ),
                  ],
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
    );
  }
}

/// Raised round mic button shown in the center of the bottom nav.
class _MicButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MicButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Voice assistant',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.blue.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.blue, AppColors.green],
              ),
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}


/// One bottom-nav tab: icon + single-line label (shrinks if too wide).
class _NavItem extends StatelessWidget {
  final Widget Function(Color color, double size) icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;
  final double iconSize;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fontSize = 12,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.blue : AppColors.text;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon(color, iconSize),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Sizes shared by the nav bar painter and its layout.
class _NavBarShape {
  static const double barHeight = 64;
  static const double haloRadius = 40; // white halo around the mic
  static const double haloDrop = -11; // halo center vs bar top (+ above, - below). Lower = smaller bump
  static const double fillet = 16; // smooth curve where halo meets the bar
  static const double corner = 20;
  static const double barTop = haloRadius + haloDrop; // bar top y inside the shape (halo top = 0)
  static const double totalHeight = barTop + barHeight;
  // Mic (64px) centered on the halo center.
  static const double micTop = barTop - haloDrop - 32;
}

/// Bar outline: rounded rect with a smooth round bump on top, around the mic.
Path _navBarPath(Size size) {
  final w = size.width;
  final cx = w / 2;
  const t = _NavBarShape.barTop;
  const r = _NavBarShape.haloRadius;
  const d = _NavBarShape.haloDrop;
  const f = _NavBarShape.fillet;
  const c = _NavBarShape.corner;
  final h = size.height;

  // Fillet circles are tangent to the bar line and to the halo circle.
  final dx = math.sqrt((r + f) * (r + f) - (f - d) * (f - d));
  final alpha = math.atan2(f - d, dx);

  final halo = Rect.fromCircle(center: Offset(cx, t - d), radius: r);
  final fl = Rect.fromCircle(center: Offset(cx - dx, t - f), radius: f);
  final fr = Rect.fromCircle(center: Offset(cx + dx, t - f), radius: f);

  return Path()
    ..moveTo(c, t)
    ..lineTo(cx - dx, t)
    ..arcTo(fl, math.pi / 2, -(math.pi / 2 - alpha), false)
    ..arcTo(halo, -math.pi + alpha, math.pi - 2 * alpha, false)
    ..arcTo(fr, math.pi - alpha, -(math.pi / 2 - alpha), false)
    ..lineTo(w - c, t)
    ..arcToPoint(Offset(w, t + c), radius: const Radius.circular(c))
    ..lineTo(w, h - c)
    ..arcToPoint(Offset(w - c, h), radius: const Radius.circular(c))
    ..lineTo(c, h)
    ..arcToPoint(Offset(0, h - c), radius: const Radius.circular(c))
    ..lineTo(0, t + c)
    ..arcToPoint(Offset(c, t), radius: const Radius.circular(c))
    ..close();
}

class _NavBarClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _navBarPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Paints the glass bar: soft shadow, translucent white fill, thin border.
class _NavBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _navBarPath(size);
    canvas.drawShadow(path, const Color(0x40000000), 10, false);
    canvas.drawPath(path, Paint()..color = AppColors.card.withOpacity(0.72));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border.withOpacity(0.9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}