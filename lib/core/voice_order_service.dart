import 'api_client.dart';

/// OrderBox (AI voice order) -> v1/retailer/voice-order.
///
/// Actions: process_audio, process_text, preview, search_products, confirm.
/// The server draft is kept as raw maps and sent back untouched on
/// preview/confirm, so server-side fields are never lost.

double _num(Map<String, dynamic> j, List<String> keys, [double def = 0]) {
  for (final k in keys) {
    final v = j[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final d = double.tryParse(v.replaceAll(',', '').replaceAll('₹', '').trim());
      if (d != null) return d;
    }
  }
  return def;
}

String _str(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return '';
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// One order line of the draft. Wraps the raw server map.
class VoiceItem {
  final Map<String, dynamic> raw;
  VoiceItem(this.raw);

  static const _qtyKeys = ['quantity', 'qty', 'product_quantity'];

  int get productId => _num(raw, ['product_id', 'id']).toInt();
  String get name => _str(raw, ['product_name', 'name', 'matched_name']);
  String get spoken => _str(raw, ['spoken_name', 'extracted_name']);
  String get unitSize => _str(raw, ['unit_size', 'pack']);
  String get packingType => _str(raw, ['packing_type', 'pack_size']);
  String get imageUrl =>
      _str(raw, ['image_url', 'image', 'thumbnail', 'product_image', 'photo']);
  double get price => _num(raw, ['price', 'unit_price', 'product_price']);
  int get quantity => _num(raw, _qtyKeys, 1).toInt().clamp(0, 100000);
  bool get isMatched => productId > 0 && raw['matched'] != false;
  String get displayName => name.isNotEmpty ? name : spoken;
  double get lineTotal =>
      _num(raw, ['line_total', 'subtotal', 'total'], quantity * price);

  set quantity(int v) {
    var wrote = false;
    for (final k in _qtyKeys) {
      if (raw.containsKey(k)) {
        raw[k] = v;
        wrote = true;
      }
    }
    if (!wrote) raw['quantity'] = v;
  }

  /// Point this line at a catalog product picked by the user.
  void assign(VoiceProduct p) {
    raw['product_id'] = p.id;
    raw['name'] = p.name;
    raw['product_name'] = p.name;
    raw['price'] = p.price;
    if (p.unitSize.isNotEmpty) raw['unit_size'] = p.unitSize;
    raw['matched'] = true;
  }

  factory VoiceItem.fromProduct(VoiceProduct p) => VoiceItem({
        'product_id': p.id,
        'name': p.name,
        'product_name': p.name,
        'price': p.price,
        'unit_size': p.unitSize,
        'quantity': 1,
        'matched': true,
      });
}

class VoiceProduct {
  final int id;
  final String name;
  final String brand;
  final String unitSize;
  final double price;
  const VoiceProduct({
    required this.id,
    required this.name,
    this.brand = '',
    this.unitSize = '',
    this.price = 0,
  });

  factory VoiceProduct.fromJson(Map<String, dynamic> j) => VoiceProduct(
        id: _num(j, ['id', 'product_id']).toInt(),
        name: _str(j, ['name', 'product_name']),
        brand: _str(j, ['brand']),
        unitSize: _str(j, ['unit_size']),
        price: _num(j, ['price', 'billing_case', 'unit_price']),
      );
}

/// `data.draft` of process_* / preview.
class VoiceDraft {
  final List<VoiceItem> items;
  final String transcript;
  final String notes;
  final double subtotal;
  final double discount;
  final double total;
  final String couponMessage;
  final Map<String, dynamic> raw;

  const VoiceDraft({
    required this.items,
    this.transcript = '',
    this.notes = '',
    this.subtotal = 0,
    this.discount = 0,
    this.total = 0,
    this.couponMessage = '',
    this.raw = const {},
  });

  factory VoiceDraft.fromJson(Map<String, dynamic> j,
      {String transcript = '', String notes = ''}) {
    final items = <VoiceItem>[];
    final rawItems = j['items'] ?? j['lines'];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) items.add(VoiceItem(Map<String, dynamic>.from(e)));
      }
    }
    final totals = _map(j['totals'] ?? j['summary']);
    final src = totals.isEmpty ? j : {...j, ...totals};
    final sub = _num(src, ['subtotal', 'total_price', 'gross_total'],
        items.fold<double>(0, (a, e) => a + e.lineTotal));
    final disc = _num(src, ['discount', 'total_discount', 'total_savings', 'savings']);
    final tot = _num(src, ['net_payable', 'grand_total', 'total'], sub - disc);
    final coupon = _map(j['coupon']);
    return VoiceDraft(
      items: items,
      transcript: _str(j, ['transcript']).isNotEmpty ? _str(j, ['transcript']) : transcript,
      notes: _str(j, ['order_notes']).isNotEmpty ? _str(j, ['order_notes']) : notes,
      subtotal: sub,
      discount: disc,
      total: tot,
      couponMessage: _str(coupon, ['message']),
      raw: j,
    );
  }
}

class VoiceOrderService {
  VoiceOrderService._();

  static final ApiClient _api = ApiClient.instance;
  static const String _path = 'v1/retailer/voice-order';

  static Map<String, dynamic> _data(Map<String, dynamic> res) {
    final d = res['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    throw ApiException('Unexpected server response.');
  }

  static List<Map<String, dynamic>> _itemsJson(List<VoiceItem> items) =>
      items.map((e) => e.raw).toList();

  static VoiceDraft _draftFrom(Map<String, dynamic> d) => VoiceDraft.fromJson(
        _map(d['draft']),
        transcript: _str(d, ['transcript']),
        notes: _str(d, ['order_notes']),
      );

  /// Spoken audio (base64 data URI) -> transcript + matched draft.
  static Future<VoiceDraft> processAudio(String base64Audio,
      {String mime = 'audio/mp4'}) async {
    final res = await _api.post(
      _path,
      body: {
        'action': 'process_audio',
        'audio_base64': 'data:$mime;base64,$base64Audio',
      },
      receiveTimeout: const Duration(seconds: 120),
    );
    return _draftFrom(_data(res));
  }

  /// Typed Hinglish/English order -> matched draft.
  static Future<VoiceDraft> processText(String text) async {
    final res = await _api.post(
      _path,
      body: {'action': 'process_text', 'transcript': text},
      receiveTimeout: const Duration(seconds: 90),
    );
    return _draftFrom(_data(res));
  }

  /// Recalculate after edits (qty, product, promo).
  static Future<VoiceDraft> preview(
    List<VoiceItem> items, {
    String promoCode = '',
    String transcript = '',
    String notes = '',
  }) async {
    final res = await _api.post(_path, body: {
      'action': 'preview',
      'items': _itemsJson(items),
      if (promoCode.isNotEmpty) 'promo_code': promoCode,
      'transcript': transcript,
      'order_notes': notes,
    });
    return _draftFrom(_data(res));
  }

  static Future<List<VoiceProduct>> searchProducts(String query) async {
    final res = await _api.post(
      _path,
      body: {'action': 'search_products', 'query': query},
    );
    final list = _data(res)['products'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => VoiceProduct.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id > 0)
        .toList();
  }

  /// Saves lines to the cart. Returns server message.
  static Future<String> confirm(List<VoiceItem> items,
      {String promoCode = ''}) async {
    final res = await _api.post(_path, body: {
      'action': 'confirm',
      'items': _itemsJson(items),
      if (promoCode.isNotEmpty) 'promo_code': promoCode,
    });
    final d = _data(res);
    return _str(d, ['message']).isNotEmpty
        ? _str(d, ['message'])
        : ((res['message'] as String?) ?? 'Saved to cart.');
  }
}