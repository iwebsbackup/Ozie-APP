import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/models.dart';
import '../../core/push_service.dart';
import '../../core/router.dart';
import '../../widgets/app_widgets.dart';
import '../notifications_screen.dart';
import '../tabs/placeholder_tab.dart';
import 'distributor_home_tab.dart';
import 'order_tracking_tab.dart';

/// Distributor app shell: Home | Reports | Voice | Dispatch | Profile.
/// Home + Dispatch are built. Reports / Voice / Profile show "Coming Soon".
class DistributorShell extends StatefulWidget {
  final Session session;
  const DistributorShell({super.key, required this.session});

  @override
  State<DistributorShell> createState() => _DistributorShellState();
}

class _DistributorShellState extends State<DistributorShell> {
  int _index = 0;
  final _trackingKey = GlobalKey<OrderTrackingTabState>();

  static const _titles = ['Home', 'Reports', 'Voice', 'Dispatch', 'Profile'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PushService.openPendingIfAny(),
    );
  }

  Widget _title() {
    if (_index == 0) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogoImage(size: 32, radius: 8),
          SizedBox(width: 10),
          Text('Ozie',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
        ],
      );
    }
    return Text(_titles[_index],
        style: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text));
  }

  Widget _comingSoon(IconData icon, String name) => PlaceholderTab(
        icon: icon,
        title: 'Coming Soon',
        subtitle: '$name is under development.\nIt will be available in a future update.',
      );

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DistributorHomeTab(
        session: widget.session,
        onOpenDispatch: (tab) {
          setState(() => _index = 3);
          _trackingKey.currentState?.setTab(tab);
        },
      ),
      _comingSoon(Icons.bar_chart_rounded, 'Reports'),
      _comingSoon(Icons.mic_none_rounded, 'Voice'),
      OrderTrackingTab(key: _trackingKey),
      _comingSoon(Icons.person_outline, 'Profile'),
    ];

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 16,
          title: _title(),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedNotification01,
                color: AppColors.text,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen()),
              ),
            ),
            // Profile tab is "coming soon", so keep logout reachable here.
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout, color: AppColors.text),
              onPressed: () => logoutAndGoToLogin(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 6)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) {
                setState(() => _index = i);
                if (i == 3) _trackingKey.currentState?.refresh();
              },
              backgroundColor: AppColors.card,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              elevation: 0,
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                const NavigationDestination(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedHome03),
                  selectedIcon: HugeIcon(
                      icon: HugeIcons.strokeRoundedHome03,
                      color: AppColors.blue),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.bar_chart_rounded),
                  selectedIcon:
                      Icon(Icons.bar_chart_rounded, color: AppColors.blue),
                  label: 'Reports',
                ),
                // Centre voice button
                NavigationDestination(
                  icon: _voiceIcon(false),
                  selectedIcon: _voiceIcon(true),
                  label: 'Voice',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.local_shipping_outlined),
                  selectedIcon: Icon(Icons.local_shipping, color: AppColors.blue),
                  label: 'Dispatch',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person, color: AppColors.blue),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceIcon(bool selected) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.blue : AppColors.blue.withOpacity(0.12),
        ),
        child: Icon(Icons.mic_rounded,
            size: 22, color: selected ? Colors.white : AppColors.blue),
      );
}