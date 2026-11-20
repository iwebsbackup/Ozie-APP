import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../widgets/app_widgets.dart';
import 'pending_orders_screen.dart';
import 'salesman_tracking_screen.dart';

/// Distributor Home. Has the "View Reports" button -> salesman tracking.
class DistributorHomeTab extends StatelessWidget {
  final Session session;
  /// Switch shell to Dispatch tab with filter: all | approved | dispatched.
  final void Function(String tab)? onOpenDispatch;
  const DistributorHomeTab(
      {super.key, required this.session, this.onOpenDispatch});

  Widget _card(IconData icon, String title, String sub, String btn,
      IconData btnIcon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: Icon(btnIcon, size: 18),
              label: Text(btn),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: AppColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = session.user;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('Hello, ${u.displayName}',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 4),
        const Text('Distributor',
            style: TextStyle(fontSize: 13, color: AppColors.blue)),
        const SizedBox(height: 20),
        _card(
          Icons.pending_actions_outlined,
          'Pending Orders',
          'Review, approve or reject purchase orders.',
          'View Pending Orders',
          Icons.fact_check_outlined,
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PendingOrdersScreen()),
          ),
        ),
        _card(
          Icons.local_shipping_outlined,
          'Order Tracking',
          'Approved and dispatched orders with status.',
          'Open Dispatch',
          Icons.arrow_forward,
          () => onOpenDispatch?.call('all'),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.route, color: AppColors.blue),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Salesman Tracking',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                      SizedBox(height: 2),
                      Text('Live location, route and visits of your salesmen.',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SalesmanTrackingScreen()),
                  ),
                  icon: const Icon(Icons.assessment_outlined, size: 18),
                  label: const Text('View Reports'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: AppColors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}