import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/reports_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';

/// Sales & Analytics. Data: GET v1/retailer/reports.
/// Layout follows Invoices screen: blue app bar, rounded sheet body.
/// Charts are drawn with CustomPaint (no extra package).

// ---- chart palette (screen-local) ----
const Color _cBlue = Color(0xFF4F46E5); // indigo: sales charts
const Color _cTeal = Color(0xFF10B981); // mint: growth & savings
const Color _cAmber = Color(0xFFF97316); // orange: peak / offers
const Color _cGrey = Color(0xFF9AA4B2); // "Others" / muted bars
const Color _cRed = Color(0xFFEF4444); // negative trend only
// ignore: unused_element
const List<Color> _donutPalette = [
  Color(0xFF4F46E5),
  Color(0xFF10B981),
  Color(0xFF818CF8),
  Color(0xFF059669),
  Color(0xFFA5B4FC),
];

const List<String> _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _short(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

String _dm(DateTime d) => '${d.day} ${_mon[d.month - 1]}';

/// "22 Oct" -> DateTime. Year inferred: a month later than today's month
/// belongs to last year. Returns null if label cannot be parsed.
DateTime? _parseDm(String s) {
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final day = int.tryParse(parts[0]);
  if (day == null) return null;
  final mk = parts[1].toLowerCase();
  final mi = _mon.indexWhere((m) => mk.startsWith(m.toLowerCase()));
  if (mi < 0) return null;
  final now = DateTime.now();
  final year = (mi + 1) > now.month ? now.year - 1 : now.year;
  return DateTime(year, mi + 1, day);
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportsData? _data;
  bool _loading = true;
  String? _error;
  int _days = 30; // range: 7 | 15 | 30

  // UI-only filters (no API impact).
  String _metricFilter = 'Sales';
  String _productFilter = 'All';
  bool _rangeOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await RetailerService.getReports();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (silent && _data != null) {
        showStatus(context, e.message, error: true);
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  // ---------- shell ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blue,
      appBar: AppBar(
        title: const Text('Sales & Analytics'),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: Colors.white,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.dangerText)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final d = _data!;
    final s = _Series.from(d, _days);
    var products = d.topProducts;
    if (_productFilter == 'Top 1') products = products.take(1).toList();
    if (_productFilter == 'Top 2') products = products.take(2).toList();
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _filterStrip(),
          const SizedBox(height: 12),
          _heroCard(s, d.overview),
          const SizedBox(height: 12),
          _snapshotRow(d.overview, _days, (v) => setState(() => _days = v)),
          const SizedBox(height: 20),
          _title('Sales', HugeIcons.strokeRoundedChartIncrease),
          _dailyCard(s),
          const SizedBox(height: 12),
          _cumulativeCard(s),
          const SizedBox(height: 12),
          _weeklyCard(s),
          const SizedBox(height: 12),
          _weekdayCard(s),
          const SizedBox(height: 20),
          _title('Products', HugeIcons.strokeRoundedShoppingBag01),
          _topProductsCard(products),
          const SizedBox(height: 20),
          _title('Offers', HugeIcons.strokeRoundedDiscountTag01),
          _offersCard(d.overview, d.recentOffers),
          const SizedBox(height: 12),
          _recentOffersCard(d.recentOffers),
        ],
      ),
    );
  }

  // ---------- filter strip + sheet ----------

  Widget _filterStrip() {
    final applied = <String>[
      if (_metricFilter != 'Sales') 'Metric: $_metricFilter',
      if (_productFilter != 'All') 'Product: $_productFilter',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => PopupMenuButton<int>(
                  tooltip: 'Select range',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 6),
                  elevation: 10,
                  color: AppColors.card,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: const Color(0x330F172A),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                      minWidth: c.maxWidth, maxWidth: c.maxWidth),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: AppColors.border.withOpacity(0.8)),
                  ),
                  onOpened: () => setState(() => _rangeOpen = true),
                  onCanceled: () => setState(() => _rangeOpen = false),
                  onSelected: (v) => setState(() {
                    _days = v;
                    _rangeOpen = false;
                  }),
                  itemBuilder: (_) => [
                    for (final d in const [7, 15, 30])
                      PopupMenuItem<int>(
                        value: d,
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: d == _days
                                ? _cBlue.withOpacity(0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 16,
                                  color: d == _days ? _cBlue : AppColors.muted),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('Last $d days',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: d == _days
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: d == _days
                                            ? _cBlue
                                            : AppColors.text)),
                              ),
                              if (d == _days)
                                const Icon(Icons.check_rounded,
                                    size: 18, color: _cBlue),
                            ],
                          ),
                        ),
                      ),
                  ],
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _rangeOpen ? _cBlue : AppColors.border,
                          width: _rangeOpen ? 1.4 : 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 16, color: _cBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Last $_days days',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text)),
                        ),
                        AnimatedRotation(
                          turns: _rangeOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _showFilterSheet,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppColors.text, size: 20),
              ),
            ),
          ],
        ),
        if (applied.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in applied)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _cBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(a,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _cBlue)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showFilterSheet() async {
    var m = _metricFilter;
    var p = _productFilter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Widget section(String title, List<String> opts, String cur,
              void Function(String) pick) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in opts)
                      ChoiceChip(
                        label: Text(o),
                        selected: cur == o,
                        showCheckmark: false,
                        selectedColor: _cBlue.withOpacity(0.12),
                        backgroundColor: AppColors.card,
                        side: BorderSide(
                            color: cur == o ? _cBlue : AppColors.border),
                        labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cur == o ? _cBlue : AppColors.text),
                        onSelected: (_) => setS(() => pick(o)),
                      ),
                  ],
                ),
              ],
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Filters',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppColors.text)),
                  const SizedBox(height: 12),
                  section('Metric', const ['Sales', 'Offers', 'Savings'], m,
                      (v) => m = v),
                  const SizedBox(height: 12),
                  section('Product', const ['All', 'Top 1', 'Top 2'], p,
                      (v) => p = v),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _metricFilter = m;
                          _productFilter = p;
                        });
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- shared bits ----------

  BoxDecoration get _cardDeco => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      );

  Widget _title(String t, dynamic icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(
          children: [
            HugeIcon(
              icon: icon,
              size: 20,
              color: _cBlue,
              strokeWidth: 1.5,
            ),
            const SizedBox(width: 8),
            Text(t,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.text)),
          ],
        ),
      );

  Widget _cardHead(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.text)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ],
        ),
      );

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(msg, style: const TextStyle(color: AppColors.muted)),
        ),
      );

  Widget _iconDot(IconData icon, Color c) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: c, size: 20),
      );

  /// Bars grow in once; replays only when [animKey] changes.
  Widget _animatedBars({
    required Key animKey,
    required double height,
    required List<double> values,
    required List<String> labels,
    required Color color,
    bool showValues = false,
    bool highlightMax = false,
    Color? highlightColor,
    int? labelEvery,
    double maxBarW = 24,
  }) {
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        key: animKey,
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          size: Size.infinite,
          painter: _BarPainter(
            values: values,
            labels: labels,
            color: color,
            showValues: showValues,
            highlightMax: highlightMax,
            highlightColor: highlightColor,
            labelEvery: labelEvery,
            maxBarW: maxBarW,
            t: t,
          ),
        ),
      ),
    );
  }

  // ---------- hero + snapshot ----------

  Widget _heroCard(_Series s, ReportOverview o) {
    final trend = s.trendPct;
    Widget mini(String label, String value,
            {String? sub, Color color = AppColors.text}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
              if (sub != null)
                Text(sub,
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        );
    final sparse = s.take > 0 && s.activeDays < s.take / 2;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconDot(Icons.trending_up_rounded, _cBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total sales · last ${s.take} days',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(formatInr(s.total, decimals: false),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: AppColors.text)),
                    ),
                  ],
                ),
              ),
              if (trend != null) _trendChip(trend),
            ],
          ),
          if (sparse) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _cBlue.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 12, color: _cBlue),
                  const SizedBox(width: 6),
                  Text('${s.activeDays} active days of ${s.take}',
                      style: const TextStyle(fontSize: 11, color: _cBlue)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              mini('Avg / day', formatInr(s.avg, decimals: false)),
              mini('Best day', formatInr(s.best, decimals: false),
                  sub: s.bestDate == null ? null : _dm(s.bestDate!)),
              mini('Saved', formatInr(o.totalMoneySaved, decimals: false),
                  sub: 'via offers', color: _cTeal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trendChip(double pct) {
    final up = pct >= 0;
    final c = up ? AppColors.successText : _cRed;
    final bg = up ? AppColors.successBg : AppColors.dangerBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 13, color: c),
          const SizedBox(width: 2),
          Text('${pct.abs().toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }

  Widget _snapshotRow(
      ReportOverview o, int days, ValueChanged<int> onSelect) {
    Widget tile(int d, double v) {
      final sel = days == d;
      return Expanded(
        child: Material(
          color: sel ? const Color(0x124F46E5) : AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: sel
                ? const BorderSide(color: _cBlue, width: 1.4)
                : BorderSide(color: AppColors.border.withOpacity(0.8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(d),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 4,
                    decoration: BoxDecoration(
                        color: _cBlue,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 10),
                  Text('$d days',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? _cBlue : AppColors.muted)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatInr(v, decimals: false),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: sel ? _cBlue : AppColors.text)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(7, o.sales7),
        const SizedBox(width: 8),
        tile(15, o.sales15),
        const SizedBox(width: 8),
        tile(30, o.sales30),
      ],
    );
  }

  // ---------- sales charts ----------

  Widget _dailyCard(_Series s) {
    final idle = s.take - s.activeDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('Daily Sales', sub: 'Last ${s.take} days'),
          if (!s.hasData)
            _empty('No sales in this period.')
          else ...[
            _animatedBars(
              animKey: ValueKey('daily-${s.take}'),
              height: 170,
              values: s.values,
              labels: s.dateLabels,
              color: _cBlue,
              highlightMax: true,
            ),
            if (idle > 0) ...[
              const SizedBox(height: 8),
              Center(
                child: Text('No sales on $idle of ${s.take} days',
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.muted)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _cumulativeCard(_Series s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('Cumulative Sales', sub: 'Running total · tap or drag chart'),
          if (!s.hasData)
            _empty('No sales in this period.')
          else
            _TouchLine(
              key: ValueKey('cum-${s.take}'),
              values: s.cumulative,
              labels: s.dateLabels,
              color: _cTeal,
            ),
        ],
      ),
    );
  }

  Widget _weeklyCard(_Series s) {
    final w = s.weekly; // always from full 30d data
    final vals = w.map((e) => e.value).toList();
    String? growth;
    if (vals.length >= 2 && vals[vals.length - 2] > 0) {
      final g = (vals.last - vals[vals.length - 2]) / vals[vals.length - 2] * 100;
      growth = '${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)}% vs previous week';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('Weekly Sales', sub: growth ?? 'Last 4 weeks'),
          if (vals.every((v) => v <= 0))
            _empty('No sales in the last 4 weeks.')
          else
            _animatedBars(
              animKey: const ValueKey('weekly'),
              height: 170,
              values: vals,
              labels: w.map((e) => e.label).toList(),
              color: _cBlue,
              showValues: true,
              labelEvery: 1,
              highlightMax: true,
              highlightColor: _cAmber,
              maxBarW: 44,
            ),
        ],
      ),
    );
  }

  Widget _weekdayCard(_Series s) {
    final sums = s.weekdaySums;
    var bi = 0;
    for (var i = 1; i < 7; i++) {
      if (sums[i] > sums[bi]) bi = i;
    }
    final any = sums.any((v) => v > 0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('Sales by Weekday',
              sub: any ? 'Strongest day: ${_wd[bi]}' : 'Last ${s.take} days'),
          if (!any)
            _empty('No sales in this period.')
          else
            _animatedBars(
              animKey: ValueKey('weekday-${s.take}'),
              height: 170,
              values: sums,
              labels: _wd,
              color: _cBlue,
              showValues: true,
              labelEvery: 1,
              highlightMax: true,
              highlightColor: _cAmber,
              maxBarW: 30,
            ),
        ],
      ),
    );
  }

  // ---------- products ----------

  Widget _topProductsCard(List<TopProduct> items) {
    final maxVal =
        items.fold<double>(0, (m, e) => e.salesValue > m ? e.salesValue : m);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('Top Products', sub: 'Ranked by sales · last 30 days'),
          if (items.isEmpty)
            _empty('No product sales yet.')
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (i < 3 ? _cBlue : _cGrey).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i < 3 ? _cBlue : AppColors.muted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value:
                                maxVal <= 0 ? 0 : items[i].salesValue / maxVal,
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: i < 3 ? _cBlue : _cGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatInr(items[i].salesValue, decimals: false),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                      Text('${items[i].qtySold} units',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  // ---------- offers ----------

  Widget _offersCard(ReportOverview o, List<RecentOffer> offers) {
    Widget stat(IconData icon, String label, String value, Color c) => Expanded(
          child: Row(
            children: [
              _iconDot(icon, c),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    // inline breakdown by scheme type, from recent offers
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final x in offers) {
      final k = x.schemeType.isEmpty ? 'OFFER' : x.schemeType;
      sums[k] = (sums[k] ?? 0) + x.savings;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final keys = sums.keys.toList()
      ..sort((a, b) => sums[b]!.compareTo(sums[a]!));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat(Icons.local_offer_outlined, 'Offers availed',
                  '${o.totalOffersAvailed}', _cAmber),
              const SizedBox(width: 8),
              stat(Icons.savings_outlined, 'Money saved',
                  formatInr(o.totalMoneySaved, decimals: false), _cTeal),
            ],
          ),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border.withOpacity(0.6)),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in keys)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x1AF97316),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$k · ${counts[k]} · ${formatInr(sums[k], decimals: false)}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _cAmber),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recentOffersCard(List<RecentOffer> items) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('Recent Offers Availed'),
          if (items.isEmpty)
            _empty('No offers availed yet.')
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 20, color: AppColors.border),
              _offerRow(items[i]),
            ],
        ],
      ),
    );
  }

  Widget _offerRow(RecentOffer o) {
    final isFree = o.schemeType == 'FREE';
    String tag;
    if (isFree) {
      tag = 'FREE ${o.freeQty > 0 ? 'x${o.freeQty}' : ''}'.trim();
    } else if (o.schemeType == 'DISCOUNT' && o.discountPercentage > 0) {
      final p = o.discountPercentage;
      tag = 'DISCOUNT ${p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1)}%';
    } else {
      tag = o.schemeType.isEmpty ? 'OFFER' : o.schemeType;
    }
    final hasTitle = o.schemeTitle.isNotEmpty;
    final used = o.status == 'used';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hasTitle ? o.schemeTitle : o.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
              if (hasTitle) ...[
                const SizedBox(height: 2),
                Text(o.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1AF97316),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(tag,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _cAmber)),
                  ),
                  if (o.status.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: used ? AppColors.border : AppColors.successBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(o.status,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: used
                                  ? AppColors.muted
                                  : AppColors.successText)),
                    ),
                  if (o.appliedAt != null && o.appliedAt!.isNotEmpty)
                    Text(formatDate(o.appliedAt),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Saved ${formatInr(o.savings, decimals: false)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.successText)),
            if (o.discountedPrice > 0)
              Text(formatInr(o.discountedPrice, decimals: false),
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}

/* ------------------------------ derived data ------------------------------ */

class _Bucket {
  final String label;
  final double value;
  const _Bucket(this.label, this.value);
}

/// Series built from data.chart_data_30d. API labels are the source of truth;
/// DateTime.now() is only a fallback when labels are missing / unparsable.
class _Series {
  final int take;
  final List<double> values;
  final List<DateTime> dates;
  final List<String> dateLabels;
  final List<double> allValues; // full 30d
  final List<DateTime> allDates;

  _Series._(this.take, this.values, this.dates, this.dateLabels, this.allValues,
      this.allDates);

  factory _Series.from(ReportsData d, int days) {
    final all = d.chartValues;
    final n = all.length;
    final apiLabels = d.chartLabels;

    List<DateTime>? parsed;
    if (apiLabels.length == n && n > 0) {
      final tmp = [for (final l in apiLabels) _parseDm(l)];
      if (tmp.every((e) => e != null)) parsed = tmp.cast<DateTime>();
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final allDates = parsed ??
        [for (var i = 0; i < n; i++) today.subtract(Duration(days: n - 1 - i))];
    final allLabels = (apiLabels.length == n && n > 0)
        ? apiLabels
        : [for (final x in allDates) _dm(x)];

    final take = days < n ? days : n;
    return _Series._(
      take,
      all.sublist(n - take),
      allDates.sublist(n - take),
      allLabels.sublist(n - take),
      all,
      allDates,
    );
  }

  bool get hasData => values.any((v) => v > 0);
  double get total => values.fold<double>(0, (a, b) => a + b);
  double get avg => take == 0 ? 0 : total / take;
  int get activeDays => values.where((v) => v > 0).length;
  double get best => values.fold<double>(0, (m, v) => v > m ? v : m);
  DateTime? get bestDate {
    if (best <= 0) return null;
    return dates[values.indexOf(best)];
  }

  /// % change vs the previous window of same length. null if no prior data.
  double? get trendPct {
    final n = allValues.length;
    if (take == 0 || n < take * 2) return null;
    final prev = allValues
        .sublist(n - take * 2, n - take)
        .fold<double>(0, (a, b) => a + b);
    if (prev <= 0) return null;
    return (total - prev) / prev * 100;
  }

  List<double> get cumulative {
    var run = 0.0;
    return [for (final v in values) run += v];
  }

  /// Last 4 full 7-day buckets of the 30d data, oldest first.
  List<_Bucket> get weekly {
    final n = allValues.length;
    final out = <_Bucket>[];
    for (var w = 3; w >= 0; w--) {
      final end = n - w * 7;
      final start = end - 7;
      if (start < 0) continue;
      final sum =
          allValues.sublist(start, end).fold<double>(0, (a, b) => a + b);
      final a = allDates[start];
      final b = allDates[end - 1];
      final label = a.month == b.month
          ? '${a.day}–${b.day} ${_mon[b.month - 1]}'
          : '${_dm(a)}–${_dm(b)}';
      out.add(_Bucket(label, sum));
    }
    return out;
  }

  List<double> get weekdaySums {
    final s = List<double>.filled(7, 0);
    for (var i = 0; i < values.length; i++) {
      s[dates[i].weekday - 1] += values[i];
    }
    return s;
  }
}

class _Part {
  final String label;
  final double value;
  final Color color;
  const _Part(this.label, this.value, this.color);
}

/* -------------------------------- widgets --------------------------------- */

/// Area line chart with tap / drag readout. Grows in left to right once.
class _TouchLine extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  const _TouchLine({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  State<_TouchLine> createState() => _TouchLineState();
}

class _TouchLineState extends State<_TouchLine> {
  int? _sel;

  void _pick(double dx, double width) {
    final n = widget.values.length;
    if (n == 0) return;
    final w = width - _LinePainter.left - _LinePainter.right;
    if (w <= 0) return;
    final t = ((dx - _LinePainter.left) / w).clamp(0.0, 1.0);
    final i = n == 1 ? 0 : (t * (n - 1)).round();
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    final i = (_sel != null && _sel! < n) ? _sel : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: Text(
            i == null
                ? 'Total ${formatInr(widget.values.last, decimals: false)}'
                : '${widget.labels[i]}  ·  ${formatInr(widget.values[i], decimals: false)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: widget.color),
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition.dx, c.maxWidth),
            onHorizontalDragStart: (d) => _pick(d.localPosition.dx, c.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _pick(d.localPosition.dx, c.maxWidth),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, t, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: child,
                  ),
                ),
                child: SizedBox(
                  width: c.maxWidth,
                  height: 180,
                  child: CustomPaint(
                    painter: _LinePainter(
                      values: widget.values,
                      labels: widget.labels,
                      color: widget.color,
                      selected: i,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _DonutWithLegend extends StatelessWidget {
  final List<_Part> parts;
  final String centerTop;
  final String centerBottom;
  final String Function(double) valueFmt;
  const _DonutWithLegend({
    required this.parts,
    required this.centerTop,
    required this.centerBottom,
    required this.valueFmt,
  });

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (a, e) => a + e.value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(130, 130),
                painter: _DonutPainter(parts),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerTop,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text)),
                  Text(centerBottom,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: parts[i].color,
                          borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(parts[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.text)),
                    ),
                    const SizedBox(width: 8),
                    Text(valueFmt(parts[i].value),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(total <= 0 ? 0 : parts[i].value / total * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/* -------------------------------- painters -------------------------------- */

void _paintText(Canvas c, String s, Offset at,
    {Alignment align = Alignment.center,
    double fs = 10,
    Color color = AppColors.muted,
    FontWeight fw = FontWeight.w400}) {
  final tp = TextPainter(
    text: TextSpan(
        text: s,
        style: TextStyle(fontSize: fs, color: color, fontWeight: fw)),
    textDirection: TextDirection.ltr,
  )..layout();
  c.save();
  c.translate(at.dx - tp.width * (align.x + 1) / 2,
      at.dy - tp.height * (align.y + 1) / 2);
  tp.paint(c, Offset.zero);
  c.restore();
}

void _paintGrid(Canvas canvas, Size size, double left, double top, double h,
    double maxV) {
  final grid = Paint()
    ..color = AppColors.border
    ..strokeWidth = 1;
  for (var i = 0; i <= 4; i++) {
    final y = top + h - h * i / 4;
    canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
    _paintText(canvas, _short(maxV * i / 4), Offset(left - 6, y),
        align: Alignment.centerRight);
  }
}

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final bool showValues;
  final bool highlightMax;
  final Color? highlightColor;
  final int? labelEvery;
  final double maxBarW;
  final double t; // grow-in progress 0..1 (bar height only)
  _BarPainter({
    required this.values,
    required this.labels,
    required this.color,
    this.showValues = false,
    this.highlightMax = false,
    this.highlightColor,
    this.labelEvery,
    this.maxBarW = 24,
    this.t = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 20.0;
    final top = showValues ? 18.0 : 8.0;
    final w = size.width - left;
    final h = size.height - bottom - top;
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxV <= 0 || values.isEmpty) return;

    _paintGrid(canvas, size, left, top, h, maxV);

    final slot = w / values.length;
    final barW = (slot * 0.6).clamp(2.0, maxBarW);
    final step = labelEvery ?? (values.length / 6).ceil();
    for (var i = 0; i < values.length; i++) {
      final bh = h * values[i] / maxV * t;
      final x = left + slot * i + (slot - barW) / 2;
      final isMax = highlightMax && values[i] == maxV;
      final paint = Paint()
        ..color = (highlightMax && !isMax)
            ? color.withOpacity(0.45)
            : (isMax && highlightColor != null ? highlightColor! : color);
      if (bh > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, top + h - bh, barW, bh),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          paint,
        );
        if (showValues && t >= 0.6) {
          _paintText(canvas, _short(values[i]),
              Offset(x + barW / 2, top + h - bh - 8),
              fs: 10, color: AppColors.text, fw: FontWeight.w600);
        }
      }
      if (i % step == 0 && i < labels.length && labels[i].isNotEmpty) {
        _paintText(canvas, labels[i], Offset(x + barW / 2, size.height - 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.color != color ||
      old.highlightColor != highlightColor ||
      old.showValues != showValues ||
      old.t != t;
}

class _LinePainter extends CustomPainter {
  static const double left = 44, right = 8, top = 8, bottom = 20;
  final List<double> values;
  final List<String> labels;
  final Color color;
  final int? selected;
  _LinePainter({
    required this.values,
    required this.labels,
    required this.color,
    this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - left - right;
    final h = size.height - bottom - top;
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxV <= 0 || values.isEmpty || w <= 0) return;

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      _paintText(canvas, _short(maxV * i / 4), Offset(left - 6, y),
          align: Alignment.centerRight);
    }

    final n = values.length;
    Offset pt(int i) => Offset(
          n == 1 ? left + w / 2 : left + w * i / (n - 1),
          top + h - h * values[i] / maxV,
        );

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < n; i++) {
      final a = pt(i - 1), b = pt(i);
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pt(n - 1).dx, top + h)
      ..lineTo(pt(0).dx, top + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.28), color.withOpacity(0.02)],
        ).createShader(Rect.fromLTWH(left, top, w, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    final step = (n / 6).ceil();
    for (var i = 0; i < n; i += step) {
      if (i < labels.length) {
        _paintText(canvas, labels[i], Offset(pt(i).dx, size.height - 8));
      }
    }

    if (selected != null && selected! < n) {
      final p = pt(selected!);
      canvas.drawLine(
        Offset(p.dx, top),
        Offset(p.dx, top + h),
        Paint()
          ..color = color.withOpacity(0.4)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.color != color ||
      old.selected != selected;
}

class _DonutPainter extends CustomPainter {
  final List<_Part> parts;
  _DonutPainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<double>(0, (a, e) => a + e.value);
    if (total <= 0) return;
    const stroke = 22.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2 - stroke / 2,
    );
    const gap = 0.03; // radians between segments
    var start = -math.pi / 2;
    for (final p in parts) {
      final sweep = p.value / total * 2 * math.pi;
      if (sweep <= 0) continue;
      final s = parts.length > 1 ? math.max(sweep - gap, 0.001) : sweep;
      canvas.drawArc(
        rect,
        start + (parts.length > 1 ? gap / 2 : 0),
        s,
        false,
        Paint()
          ..color = p.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.parts != parts;
}