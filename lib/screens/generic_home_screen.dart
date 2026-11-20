import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/location_tracker.dart';
import '../core/models.dart';
import '../core/push_service.dart';
import '../core/router.dart';
import '../widgets/app_widgets.dart';
import 'notifications_screen.dart';

/// Fallback home for user types that have no dedicated screen yet
/// (distributor, manufacturer, brand, salesman, bank ...).
/// Center: logged-in user's details. Top right: notification icon.
class GenericHomeScreen extends StatefulWidget {
  final Session session;
  const GenericHomeScreen({super.key, required this.session});

  @override
  State<GenericHomeScreen> createState() => _GenericHomeScreenState();
}

class _GenericHomeScreenState extends State<GenericHomeScreen>
    with WidgetsBindingObserver {
  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App killed + notification tapped: open the notification / its link.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PushService.openPendingIfAny(),
    );
    // Salesman: ask location permission (incl. background) and start tracking.
    if ((session.user.userType ?? '').toLowerCase() == 'salesman') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => LocationTracker.ensureAndStart(context),
      );
    }
  }

  bool get _isSalesman =>
      (session.user.userType ?? '').toLowerCase() == 'salesman';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed && _isSalesman) {
      LocationTracker.resume();
    }
  }

  Widget _trackingCard() {
    return ValueListenableBuilder<TrackState>(
      valueListenable: LocationTracker.state,
      builder: (context, st, _) {
        final on = st == TrackState.on;
        final color = on
            ? AppColors.successText
            : (st == TrackState.checking ? AppColors.muted : AppColors.dangerText);
        final bg = on
            ? AppColors.successBg
            : (st == TrackState.checking ? AppColors.inputBg : AppColors.dangerBg);
        final text = switch (st) {
          TrackState.on => 'Location tracking ON',
          TrackState.limited =>
            'Tracking limited. Set location to "Allow all the time".',
          TrackState.off => 'Location tracking OFF',
          TrackState.checking => 'Checking location tracking...',
        };
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Row(children: [
                Icon(on ? Icons.my_location : Icons.location_off,
                    size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color))),
              ]),
              if (!on && st != TrackState.checking) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => LocationTracker.ensureAndStart(context),
                    child: const Text('Enable tracking'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _typeLabel(String? t) {
    if (t == null || t.isEmpty) return 'User';
    return t
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final u = session.user;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: const Row(
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
        ),
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
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.blue.withOpacity(0.1),
                  child: Text(
                    u.displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue),
                  ),
                ),
                const SizedBox(height: 16),
                Text(u.displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                Text(_typeLabel(u.userType),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.blue)),
                const SizedBox(height: 20),
                if ((u.email ?? '').isNotEmpty)
                  _row(Icons.email_outlined, u.email!),
                if ((u.mobile ?? '').isNotEmpty)
                  _row(Icons.phone_outlined, u.mobile!),
                _row(Icons.badge_outlined, 'ID: ${u.id}'),
                if (_isSalesman) ...[
                  const SizedBox(height: 16),
                  _trackingCard(),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => logoutAndGoToLogin(context),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.text)),
            ),
          ],
        ),
      );
}