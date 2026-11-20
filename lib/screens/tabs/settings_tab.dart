import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/router.dart';
import '../../widgets/app_widgets.dart';
import '../catalog_screen.dart';
import '../notifications_screen.dart';
import '../profile_screen.dart';
import '../schemes_screen.dart';
import '../pending_payments_screen.dart';
import '../invoices_screen.dart';
import '../dispatch_screen.dart';
import '../finance_screen.dart';
import '../packing_screen.dart';
import '../received_screen.dart';
import '../returns_screen.dart';
import '../reports_screen.dart';
import '../support_tickets_screen.dart';

class _MenuItem {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;
  const _MenuItem(this.icon, this.label, this.tint, [this.onTap]);
}

class _MenuGroup {
  final String title;
  final List<_MenuItem> items;
  const _MenuGroup(this.title, this.items);
}

class SettingsTab extends StatelessWidget {
  final Session session;
  final VoidCallback? onViewCatalog;
  final VoidCallback? onViewOrders;
  const SettingsTab({
    super.key,
    required this.session,
    this.onViewCatalog,
    this.onViewOrders,
  });

  Future<void> _confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await logoutAndGoToLogin(context);
    }
  }

  void _soon(BuildContext context, String label) {
    showStatus(context, '$label will be available in the next update.');
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _profileHeader(BuildContext context) {
    final user = session.user;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
        ),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.green, AppColors.blue],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.blue.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFDCE9FA),
                  child: Text(
                    _initials(user.displayName),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        user.roleLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'View & edit account',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _menuTile(_MenuItem m, {required bool last}) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: m.tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(m.icon, color: m.tint, size: 22),
          ),
          title: Text(
            m.label,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 24),
          onTap: m.onTap,
        ),
        if (!last) const Divider(height: 1, indent: 68, endIndent: 14, color: AppColors.border),
      ],
    );
  }

  Widget _group(_MenuGroup g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(g.title),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < g.items.length; i++)
                _menuTile(g.items[i], last: i == g.items.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    VoidCallback soon(String l) => () => _soon(context, l);

    const orange = Color(0xFFF59E0B);
    const purple = Color(0xFF7C3AED);
    const teal = Color(0xFF0D9488);
    const pink = Color(0xFFDB2777);
    const red = Color(0xFFDC3545);

    final groups = <_MenuGroup>[
      _MenuGroup('Shop', [
        _MenuItem(
          Icons.grid_view_rounded,
          'My Catalog',
          AppColors.blue,
          onViewCatalog ?? () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CatalogScreen()),
        );
      },
        ),
        _MenuItem(Icons.receipt_long_outlined, 'View Orders', teal, onViewOrders ?? soon('View Orders')),
        _MenuItem(Icons.local_offer_outlined, 'Schemes', pink, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SchemesScreen()),
        );
      }),
      ]),
      _MenuGroup('Payments', [
        _MenuItem(Icons.payments_outlined, 'Pending Payments', orange, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PendingPaymentsScreen()),
        );
      }),
        _MenuItem(Icons.description_outlined, 'Invoices', AppColors.blue, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const InvoicesScreen()),
        );
      }),
        _MenuItem(Icons.account_balance_wallet_outlined, 'Ozie Finance', purple, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FinanceScreen()),
        );
      }),
      ]),
      _MenuGroup('Fulfilment', [
        _MenuItem(Icons.inventory_2_outlined, 'Packing', orange, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PackingScreen()),
        );
      }),
        _MenuItem(Icons.local_shipping_outlined, 'Dispatch', teal, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DispatchScreen()),
        );
      }),
        _MenuItem(Icons.move_to_inbox_outlined, 'Received Order', AppColors.green, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ReceivedScreen()),
        );
      }),
        _MenuItem(Icons.assignment_return_outlined, 'My Returns', red, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ReturnsScreen()),
        );
      }),
      ]),
      _MenuGroup('Insights & Help', [
        _MenuItem(Icons.bar_chart_rounded, 'Report', purple, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
        );
      }),
        _MenuItem(Icons.notifications_none_rounded, 'Notifications', orange, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        );
      }),
        _MenuItem(Icons.support_agent_outlined, 'My Tickets', AppColors.blue, () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SupportTicketsScreen()),
        );
      }),
      ]),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + kBottomNavSpace),
      children: [
        _profileHeader(context),
        for (final g in groups) _group(g),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _confirmLogout(context),
          icon: const Icon(Icons.logout, size: 22, color: red),
          label: const Text(
            'Logout',
            style: TextStyle(fontSize: 16, color: red, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.card,
            side: BorderSide(color: red.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}