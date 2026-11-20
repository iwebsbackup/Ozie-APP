import '../../core/api_client.dart';
import '../salesman/salesman_models.dart';
import 'distributor_models.dart';
import 'distributor_order_models.dart';

class DistributorService {
  DistributorService._();
  static final ApiClient _api = ApiClient.instance;

  /// GET v1/distributor/salesmen
  static Future<SalesmanListResult> getSalesmen() async {
    final res = await _api.get('v1/distributor/salesmen');
    final data = res['data'];
    if (data is Map) {
      return SalesmanListResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Unexpected server response.');
  }

  /// GET v1/distributor/salesman-track  (one day)
  static Future<DayTrack> getDayTrack(int userId, DateTime day) async {
    final d = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final res = await _api.get(
      'v1/distributor/salesman-track',
      query: {'user_id': userId, 'from': d, 'to': d},
    );
    final data = res['data'];
    if (data is Map && data['days'] is List && (data['days'] as List).isNotEmpty) {
      return DayTrack.fromJson(
          Map<String, dynamic>.from((data['days'] as List).first as Map));
    }
    throw ApiException('Unexpected server response.');
  }

  /// GET v1/salesman/addresses?salesman_id=<salesman.id>  (distributor allowed)
  /// Every address assigned to that salesman (pages of 100).
  static Future<List<SalesmanAddress>> getAssignedAddresses(
      int salesmanId) async {
    final all = <SalesmanAddress>[];
    var page = 1;
    while (true) {
      final res = await _api.get('v1/salesman/addresses',
          query: {'salesman_id': salesmanId, 'page': page, 'limit': 100});
      final data = res['data'];
      if (data is! Map) throw ApiException('Unexpected server response.');
      final p = SalesmanAddressPage.fromJson(Map<String, dynamic>.from(data));
      all.addAll(p.addresses);
      if (!p.hasMore || p.addresses.isEmpty || page >= 10) break;
      page++;
    }
    return all;
  }

  // ───────────── Orders (pending POs / tracking / detail) ─────────────

  static String? _ymd(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  /// GET v1/distributor/pending-orders
  static Future<PendingPoPage> getPendingOrders({
    int page = 1,
    int limit = 15,
    String search = '',
    DateTime? start,
    DateTime? end,
  }) async {
    final res = await _api.get('v1/distributor/pending-orders', query: {
      'page': page,
      'limit': limit,
      'search': search.trim(),
      'start_date': _ymd(start),
      'end_date': _ymd(end),
    });
    final data = res['data'];
    if (data is Map) {
      return PendingPoPage.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Unexpected server response.');
  }

  /// POST v1/distributor/pending-orders  { po_id, action: approve|reject }
  static Future<PoActionResult> actOnPo(int poId, {required bool approve}) async {
    final res = await _api.post('v1/distributor/pending-orders', body: {
      'po_id': poId,
      'action': approve ? 'approve' : 'reject',
    });
    final data = res['data'];
    if (data is Map) {
      return PoActionResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Unexpected server response.');
  }

  /// GET v1/distributor/order-tracking  (tab: all | approved | dispatched)
  static Future<TrackingPage> getOrderTracking({
    String tab = 'all',
    int page = 1,
    int limit = 15,
    String search = '',
    DateTime? start,
    DateTime? end,
  }) async {
    final res = await _api.get('v1/distributor/order-tracking', query: {
      'tab': tab,
      'page': page,
      'limit': limit,
      'search': search.trim(),
      'start_date': _ymd(start),
      'end_date': _ymd(end),
    });
    final data = res['data'];
    if (data is Map) {
      return TrackingPage.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Unexpected server response.');
  }

  /// GET v1/distributor/order-detail
  /// [isPo] true  -> id is purchase_orders.id  (type=po)
  /// [isPo] false -> id is retailer_orders.id  (type=retailer)
  static Future<OrderDetail> getOrderDetail(int id, {required bool isPo}) async {
    final res = await _api.get('v1/distributor/order-detail', query: {
      'order_id': id,
      'type': isPo ? 'po' : 'retailer',
    });
    final data = res['data'];
    if (data is Map) {
      return OrderDetail.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Unexpected server response.');
  }
}