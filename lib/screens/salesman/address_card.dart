import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_widgets.dart';
import 'salesman_mappls_nav_screen.dart';
import 'salesman_models.dart';

/// One assigned address on the salesman home screen.
///
/// Bottom row:  [ call icon ]  [ View Directions ]
///  - call icon        -> opens dialer with the shop number
///  - View Directions  -> opens in-app Mappls map (needs lat/lng)
class AddressCard extends StatelessWidget {
  final SalesmanAddress item;
  final int index;
  final VoidCallback? onViewDirections;

  const AddressCard({
    super.key,
    required this.item,
    required this.index,
    this.onViewDirections,
  });

  static const Color _warnBg = Color(0xFFFEF3C7);
  static const Color _warnText = Color(0xFF92400E);

  (Color, Color) get _statusColors {
    switch (item.finalStatus) {
      case 'approved':
        return (AppColors.successBg, AppColors.successText);
      case 'rejected':
        return (AppColors.dangerBg, AppColors.dangerText);
      case 'under_review':
        return (_warnBg, _warnText);
      default:
        return (AppColors.inputBg, AppColors.muted);
    }
  }

  Future<void> _call(BuildContext context) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: item.contactNumber));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open dialer.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (chipBg, chipText) = _statusColors;
    final title =
        item.shopName.isEmpty ? 'Retailer #${item.retailerId}' : item.shopName;
    final canCall = item.contactNumber.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- header: number, shop name, owner, status ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$index',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.blue)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                      if (item.ownerName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(item.ownerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: chipBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(item.statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: chipText)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- details ----
            _infoRow(Icons.location_on_outlined, item.displayAddress),
            if (canCall) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.phone_outlined, item.contactNumber),
            ],
            if (!item.hasLocation) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: _warnBg, borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wrong_location_outlined,
                        size: 14, color: _warnText),
                    SizedBox(width: 6),
                    Text('Map pin missing for this shop',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _warnText)),
                  ],
                ),
              ),
            ],

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: AppColors.border),
            ),

            // ---- actions: [call icon] [View Directions] ----
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: canCall ? () => _call(context) : null,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: AppColors.successText,
                      side: BorderSide(
                          color: canCall
                              ? AppColors.successText
                              : AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.call, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      // enabled only when lat/lng exist
                      onPressed: item.hasLocation
                          ? (onViewDirections ??
                              () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SalesmanMapplsNavScreen(
                                          target: item),
                                    ),
                                  ))
                          : null,
                      icon: const Icon(Icons.directions, size: 20),
                      label: const Text('View Directions'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, height: 1.35, color: AppColors.text)),
          ),
        ],
      );
}