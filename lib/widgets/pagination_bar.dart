import 'package:flutter/material.dart';

import 'app_widgets.dart';

/// Page-number bar: `<  1 … 4 5 6 … 20  >` + "Showing a - b of N label".
class PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int limit;
  final String itemLabel;
  final ValueChanged<int> onPage;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPage,
    this.totalItems = 0,
    this.limit = 15,
    this.itemLabel = 'items',
  });

  Widget _btn({
    required Widget child,
    VoidCallback? onTap,
    bool active = false,
    bool disabled = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.blue, AppColors.green],
                )
              : null,
          color: active ? null : (disabled ? AppColors.bg : AppColors.card),
          borderRadius: BorderRadius.circular(10),
          border: active ? null : Border.all(color: AppColors.border),
        ),
        child: Center(child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = totalPages < 1 ? 1 : totalPages;
    final cur = currentPage.clamp(1, total);
    final hasPrev = cur > 1;
    final hasNext = cur < total;

    final nums = <int>{1, total, cur - 1, cur, cur + 1}.where((n) => n >= 1 && n <= total).toList()..sort();
    final items = <Widget>[];
    int? prev;
    for (final n in nums) {
      if (prev != null && n - prev > 1) {
        items.add(const Padding(
          padding: EdgeInsets.only(left: 2),
          child: Text('…', style: TextStyle(color: AppColors.muted)),
        ));
      }
      final active = n == cur;
      items.add(_btn(
        active: active,
        onTap: active ? null : () => onPage(n),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.text,
          ),
        ),
      ));
      prev = n;
    }

    final from = (cur - 1) * limit + 1;
    final to = (cur * limit).clamp(0, totalItems);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(
                disabled: !hasPrev,
                onTap: hasPrev ? () => onPage(cur - 1) : null,
                child: Icon(Icons.chevron_left, size: 20, color: hasPrev ? AppColors.text : AppColors.border),
              ),
              for (final w in items) ...[const SizedBox(width: 5), w],
              const SizedBox(width: 5),
              _btn(
                disabled: !hasNext,
                onTap: hasNext ? () => onPage(cur + 1) : null,
                child: Icon(Icons.chevron_right, size: 20, color: hasNext ? AppColors.text : AppColors.border),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            totalItems > 0
                ? 'Showing $from - $to of $totalItems $itemLabel'
                : 'Page $cur of $total',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}