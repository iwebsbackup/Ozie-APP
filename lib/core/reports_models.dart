import 'dart:convert';

double _rpDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

int _rpInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

Map<String, dynamic> _rpMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<Map<String, dynamic>> _rpList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// data.overview
class ReportOverview {
  final int totalOffersAvailed;
  final double totalMoneySaved;
  final double sales30;
  final double sales15;
  final double sales7;

  const ReportOverview({
    this.totalOffersAvailed = 0,
    this.totalMoneySaved = 0,
    this.sales30 = 0,
    this.sales15 = 0,
    this.sales7 = 0,
  });

  factory ReportOverview.fromJson(Map<String, dynamic> j) => ReportOverview(
        totalOffersAvailed: _rpInt(j['total_offers_availed']),
        totalMoneySaved: _rpDouble(j['total_money_saved']),
        sales30: _rpDouble(j['sales_30_days']),
        sales15: _rpDouble(j['sales_15_days']),
        sales7: _rpDouble(j['sales_7_days']),
      );
}

/// data.top_products[]
class TopProduct {
  final String name;
  final int qtySold;
  final double salesValue;

  const TopProduct({
    required this.name,
    this.qtySold = 0,
    this.salesValue = 0,
  });

  factory TopProduct.fromJson(Map<String, dynamic> j) => TopProduct(
        name: (j['name'] ?? 'Product').toString(),
        qtySold: _rpInt(j['stock_sold']),
        salesValue: _rpDouble(j['sales_value']),
      );
}

/// data.recent_offers[]
class RecentOffer {
  final String productName;
  final String schemeType;
  final double discountedPrice;
  final double savings;
  final int freeQty;
  final String? appliedAt;
  final String status; // lower-case, e.g. active | used
  final double discountPercentage;
  final String schemeTitle; // parsed from scheme_details / scheme_title

  const RecentOffer({
    required this.productName,
    this.schemeType = '',
    this.discountedPrice = 0,
    this.savings = 0,
    this.freeQty = 0,
    this.appliedAt,
    this.status = '',
    this.discountPercentage = 0,
    this.schemeTitle = '',
  });

  static String _title(dynamic details, dynamic direct) {
    String pick(Map m) {
      for (final k in const ['scheme_title', 'title', 'name']) {
        final v = m[k];
        if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
      }
      return '';
    }

    dynamic d = details;
    if (d is String && d.trim().isNotEmpty) {
      try {
        d = jsonDecode(d);
      } catch (_) {
        d = null;
      }
    }
    if (d is Map) {
      final t = pick(d);
      if (t.isNotEmpty) return t;
    }
    final s = (direct ?? '').toString().trim();
    return s;
  }

  factory RecentOffer.fromJson(Map<String, dynamic> j) => RecentOffer(
        productName: (j['product_name'] ?? 'Product').toString(),
        schemeType: (j['scheme_type'] ?? '').toString().toUpperCase(),
        discountedPrice: _rpDouble(j['discounted_price']),
        savings: _rpDouble(j['savings_amount']),
        freeQty: _rpInt(j['free_quantity']),
        appliedAt: j['applied_at']?.toString(),
        status: (j['status'] ?? '').toString().trim().toLowerCase(),
        discountPercentage: _rpDouble(j['discount_percentage'] ??
            j['discount_percent'] ??
            j['discount']),
        schemeTitle: _title(j['scheme_details'], j['scheme_title']),
      );
}

/// GET v1/retailer/reports -> data.
class ReportsData {
  final ReportOverview overview;
  final List<TopProduct> topProducts;
  final List<RecentOffer> recentOffers;
  final List<String> chartLabels;
  final List<double> chartValues;

  const ReportsData({
    this.overview = const ReportOverview(),
    this.topProducts = const [],
    this.recentOffers = const [],
    this.chartLabels = const [],
    this.chartValues = const [],
  });

  bool get hasChartData => chartValues.any((v) => v > 0);

  factory ReportsData.fromJson(Map<String, dynamic> j) {
    final chart = _rpMap(j['chart_data_30d']);
    final labels = chart['labels'] is List
        ? (chart['labels'] as List).map((e) => '$e').toList()
        : <String>[];
    final values = chart['data'] is List
        ? (chart['data'] as List).map(_rpDouble).toList()
        : <double>[];
    return ReportsData(
      overview: ReportOverview.fromJson(_rpMap(j['overview'])),
      topProducts: _rpList(j['top_products']).map(TopProduct.fromJson).toList(),
      recentOffers:
          _rpList(j['recent_offers']).map(RecentOffer.fromJson).toList(),
      chartLabels: labels,
      chartValues: values,
    );
  }
}