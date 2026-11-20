import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'distributor_service.dart';

const Color kAmber = Color(0xFFB45309);

/// Small rounded status label.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

/// Colour for tracking stage 1..4 (Pending, Processing, Dispatched, Delivered).
Color stageColor(int step) => switch (step) {
      4 => AppColors.successText,
      3 => AppColors.blue,
      2 => kAmber,
      _ => AppColors.muted,
    };

/// Colour for payment badge colour keyword from API.
Color paymentColor(String key) => switch (key) {
      'success' => AppColors.successText,
      'primary' => AppColors.blue,
      _ => kAmber,
    };

Color poStatusColor(String s) => switch (s) {
      'approved' => AppColors.successText,
      'rejected' => AppColors.dangerText,
      _ => kAmber,
    };

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.text)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyView({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ]),
        ),
      );
}

/// Search box + date-range filter used by both order lists.
class OrderFilterBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final DateTimeRange? range;
  final ValueChanged<String> onSearch;
  final ValueChanged<DateTimeRange?> onRange;

  const OrderFilterBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.range,
    required this.onSearch,
    required this.onRange,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: range,
    );
    if (r != null) onRange(r);
  }

  @override
  Widget build(BuildContext context) {
    final has = range != null;
    return Column(children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: onSearch,
            style: const TextStyle(fontSize: 14, color: AppColors.text),
            decoration: inputDecoration(
              hint: hint,
              suffix: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, v, __) => v.text.isEmpty
                    ? IconButton(
                        icon: const Icon(Icons.search, size: 20),
                        onPressed: () => onSearch(controller.text),
                      )
                    : IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          controller.clear();
                          onSearch('');
                        },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: has ? AppColors.blue : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pick(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: has ? AppColors.blue : AppColors.border),
              ),
              child: Icon(Icons.date_range,
                  size: 20, color: has ? Colors.white : AppColors.muted),
            ),
          ),
        ),
      ]),
      if (has)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InputChip(
              label: Text(
                '${formatDate(range!.start.toIso8601String())}  -  '
                '${formatDate(range!.end.toIso8601String())}',
                style: const TextStyle(fontSize: 12),
              ),
              onDeleted: () => onRange(null),
            ),
          ),
        ),
    ]);
  }
}

/// Open phone dialer.
Future<void> callNumber(BuildContext context, String? mobile) async {
  final n = (mobile ?? '').trim();
  if (n.isEmpty) return;
  try {
    final ok = await launchUrl(Uri(scheme: 'tel', path: n));
    if (!ok && context.mounted) {
      showStatus(context, 'Could not open dialer.', error: true);
    }
  } catch (_) {
    if (context.mounted) {
      showStatus(context, 'Could not open dialer.', error: true);
    }
  }
}

/// Open invoice PDF in browser / viewer.
Future<void> openUrlExternal(BuildContext context, String url) async {
  try {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showStatus(context, 'Could not open link.', error: true);
    }
  } catch (_) {
    if (context.mounted) {
      showStatus(context, 'Could not open link.', error: true);
    }
  }
}

/// Confirm -> call API -> show result.
/// Returns `approved` / `rejected` on success, `conflict` if the PO was
/// already handled (409), or null if cancelled / failed.
Future<String?> runPoAction(
  BuildContext context, {
  required int poId,
  required String poNumber,
  required bool approve,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(approve ? 'Approve PO?' : 'Reject PO?'),
      content: Text(approve
          ? 'Approve purchase order $poNumber? Retailer will be notified.'
          : 'Reject purchase order $poNumber? Retailer will be notified.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
              backgroundColor:
                  approve ? AppColors.green : AppColors.dangerText),
          child: Text(approve ? 'Approve' : 'Reject'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  String? result;
  ApiException? err;
  try {
    final r = await DistributorService.actOnPo(poId, approve: approve);
    result = r.newStatus.isEmpty ? (approve ? 'approved' : 'rejected') : r.newStatus;
  } on ApiException catch (e) {
    err = e;
  }

  if (!context.mounted) return result;
  Navigator.of(context, rootNavigator: true).pop(); // close loader

  if (err != null) {
    showStatus(context, err.message, error: true);
    return err.statusCode == 409 ? 'conflict' : null;
  }
  showStatus(context, 'PO $poNumber $result.');
  return result;
}