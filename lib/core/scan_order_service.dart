import 'api_client.dart';
import 'scan_order_models.dart';

/// Create Order (AI & scan upload) -> v1/retailer/scan-order.
class ScanOrderService {
  ScanOrderService._();

  static final ApiClient _api = ApiClient.instance;
  static const String _path = 'v1/retailer/scan-order';

  static Map<String, dynamic> _dataOf(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException('Unexpected server response.');
  }

  /// GET: catalog (for manual pick) + active schemes.
  static Future<ScanCatalog> getCatalog() async {
    final res = await _api.get(_path);
    return ScanCatalog.fromJson(_dataOf(res));
  }

  /// POST action=scan. Sends the photo as base64 (`image_base64`).
  /// AI vision is slow, so wait longer than the default 30s.
  static Future<ScanResult> scan(String imageBase64) async {
    final res = await _api.post(
      _path,
      body: {'action': 'scan', 'image_base64': imageBase64},
      receiveTimeout: const Duration(seconds: 120),
    );
    return ScanResult.fromJson(_dataOf(res));
  }

  /// POST action=recalculate. Re-prices lines + re-evaluates schemes.
  static Future<ScanResult> recalculate(List<ScanItem> items) async {
    final res = await _api.post(
      _path,
      body: {
        'action': 'recalculate',
        'items': items.map((e) => e.toJson()).toList(),
      },
    );
    return ScanResult.fromJson(_dataOf(res));
  }

  /// POST action=confirm. Replaces the cart with these lines.
  /// Returns number of lines committed.
  static Future<int> confirm(List<ScanItem> items) async {
    final res = await _api.post(
      _path,
      body: {
        'action': 'confirm',
        'items': items.map((e) => e.toJson()).toList(),
      },
    );
    final d = _dataOf(res);
    final n = d['committed_items'];
    return n is num ? n.toInt() : items.length;
  }
}
