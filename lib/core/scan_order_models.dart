/// Models for v1/retailer/scan-order (AI invoice / purchase-order scan).

double _d(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0;
}

int _i(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String _s(dynamic v) => (v ?? '').toString();

/// One catalog product (GET scan-order -> data.catalog[]).
class ScanProduct {
  final int id;
  final String name;
  final String brand;
  final double price; // per case
  final String unitSize;
  final String category;

  const ScanProduct({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.unitSize,
    required this.category,
  });

  factory ScanProduct.fromJson(Map<String, dynamic> j) => ScanProduct(
        id: _i(j['id']),
        name: _s(j['name']),
        brand: _s(j['brand']),
        price: _d(j['price']),
        unitSize: _s(j['unit_size']),
        category: _s(j['product_category'] ?? j['category']),
      );
}

/// GET v1/retailer/scan-order -> data.
class ScanCatalog {
  final String retailerCategory;
  final List<ScanProduct> products;
  final List<String> schemeTitles;

  const ScanCatalog({
    required this.retailerCategory,
    required this.products,
    required this.schemeTitles,
  });

  factory ScanCatalog.fromJson(Map<String, dynamic> j) {
    final products = <ScanProduct>[];
    if (j['catalog'] is List) {
      for (final p in j['catalog'] as List) {
        if (p is Map) products.add(ScanProduct.fromJson(Map<String, dynamic>.from(p)));
      }
    }
    final titles = <String>[];
    if (j['active_schemes'] is List) {
      for (final s in j['active_schemes'] as List) {
        if (s is Map) {
          final t = _s(s['scheme_title']).trim();
          if (t.isNotEmpty) titles.add(t);
        }
      }
    }
    return ScanCatalog(
      retailerCategory: _s(j['retailer_category']),
      products: products,
      schemeTitles: titles,
    );
  }

  ScanProduct? byId(int id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// One order line. Mutable: user edits qty / product before confirming.
class ScanItem {
  int? productId;
  String name;
  String extractedName;
  int quantity;
  double price;
  String brand;
  String unitSize;
  int matchConfidence;
  List<int> suggestedProductIds;

  ScanItem({
    this.productId,
    required this.name,
    this.extractedName = '',
    this.quantity = 1,
    this.price = 0,
    this.brand = '',
    this.unitSize = '',
    this.matchConfidence = 0,
    this.suggestedProductIds = const [],
  });

  bool get isMatched => productId != null && productId! > 0;
  double get lineTotal => quantity * price;

  factory ScanItem.fromJson(Map<String, dynamic> j) {
    final pid = _i(j['product_id']);
    return ScanItem(
      productId: pid > 0 ? pid : null,
      name: _s(j['name']),
      extractedName: _s(j['extracted_name']),
      quantity: _i(j['quantity']).clamp(1, 100000),
      price: _d(j['price']),
      brand: _s(j['brand']),
      unitSize: _s(j['unit_size']),
      matchConfidence: _i(j['match_confidence']),
      suggestedProductIds: (j['suggested_product_ids'] is List)
          ? (j['suggested_product_ids'] as List).map(_i).toList()
          : const [],
    );
  }

  factory ScanItem.fromProduct(ScanProduct p) => ScanItem(
        productId: p.id,
        name: p.name,
        price: p.price,
        brand: p.brand,
        unitSize: p.unitSize,
      );

  void assign(ScanProduct p) {
    productId = p.id;
    name = p.name;
    brand = p.brand;
    unitSize = p.unitSize;
    price = p.price;
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'name': name,
        'extracted_name': extractedName,
        'quantity': quantity,
        'price': price,
      };
}

class AppliedScheme {
  final String title;
  final String? code;
  final double discount;
  const AppliedScheme({required this.title, this.code, required this.discount});

  factory AppliedScheme.fromJson(Map<String, dynamic> j) => AppliedScheme(
        title: _s(j['title']),
        code: _s(j['code']).isEmpty ? null : _s(j['code']),
        discount: _d(j['discount']),
      );
}

class SuggestedScheme {
  final String title;
  final String message;
  const SuggestedScheme({required this.title, required this.message});

  factory SuggestedScheme.fromJson(Map<String, dynamic> j) =>
      SuggestedScheme(title: _s(j['title']), message: _s(j['message']));
}

/// Response of action=scan and action=recalculate.
class ScanResult {
  final List<ScanItem> items;
  final double subtotal;
  final double schemeSavings;
  final double grandTotal;
  final List<AppliedScheme> applied;
  final List<SuggestedScheme> suggested;

  const ScanResult({
    required this.items,
    required this.subtotal,
    required this.schemeSavings,
    required this.grandTotal,
    required this.applied,
    required this.suggested,
  });

  factory ScanResult.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) f) {
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((e) => f(Map<String, dynamic>.from(e)))
          .toList();
    }

    return ScanResult(
      items: list(j['items'], ScanItem.fromJson),
      subtotal: _d(j['subtotal']),
      schemeSavings: _d(j['scheme_savings']),
      grandTotal: _d(j['grand_total']),
      applied: list(j['applied_schemes'], AppliedScheme.fromJson),
      suggested: list(j['suggested_schemes'], SuggestedScheme.fromJson),
    );
  }
}
