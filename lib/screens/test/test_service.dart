import '../../core/api_client.dart';
import 'test_models.dart';

/// All TEST-flow API calls: retailer order -> distributor accept ->
/// create delivery boy -> assign -> delivery boy login + orders.
class TestService {
  TestService._();
  static final ApiClient _api = ApiClient.instance;

  static Map<String, dynamic> _data(Map<String, dynamic> res) {
    final d = res['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    throw ApiException('Unexpected server response.');
  }

  static List<Map<String, dynamic>> _list(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  // ───────────── Retailer ─────────────

  /// POST v1/retailer/test/orders. lat/lng null -> server uses saved address.
  static Future<Map<String, dynamic>> createOrder({
    required String productName,
    required double price,
    required int quantity,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final res = await _api.post('v1/retailer/test/orders', body: {
      'product_name': productName,
      'price': price,
      'quantity': quantity,
      if (latitude != null && longitude != null) ...{
        'latitude': latitude,
        'longitude': longitude,
      },
      if (address != null && address.trim().isNotEmpty) 'address': address,
    });
    return _data(res);
  }

  /// GET v1/retailer/test/orders
  static Future<List<TestOrder>> myOrders() async {
    final res = await _api.get('v1/retailer/test/orders', query: {'limit': 50});
    return _list(_data(res)['orders']).map(TestOrder.fromJson).toList();
  }

  /// GET v1/retailer/test/track?order_id=  (live position while Started)
  static Future<OrderTracking> trackOrder(int orderId) async {
    final res =
        await _api.get('v1/retailer/test/track', query: {'order_id': orderId});
    final d = _data(res);
    final o = d['order'] is Map
        ? Map<String, dynamic>.from(d['order'] as Map)
        : <String, dynamic>{};
    final t = d['tracking'] is Map
        ? Map<String, dynamic>.from(d['tracking'] as Map)
        : <String, dynamic>{};
    return OrderTracking.fromJson(TestOrder.fromJson(o), t);
  }

  // ───────────── Distributor ─────────────

  /// GET v1/distributor/test/orders?status=Pending|Accepted|Rejected|all
  static Future<List<TestOrder>> distributorOrders(
      {String status = 'Pending'}) async {
    final res = await _api.get('v1/distributor/test/orders',
        query: {'status': status, 'limit': 50});
    return _list(_data(res)['orders']).map(TestOrder.fromJson).toList();
  }

  /// POST v1/distributor/test/orders {order_id, action: accept|reject}
  static Future<void> actOnOrder(int orderId, {required bool accept}) async {
    await _api.post('v1/distributor/test/orders', body: {
      'order_id': orderId,
      'action': accept ? 'accept' : 'reject',
    });
  }

  /// GET v1/distributor/test/delivery-boys
  static Future<List<TestDeliveryBoy>> deliveryBoys() async {
    final res = await _api.get('v1/distributor/test/delivery-boys');
    return _list(_data(res)['delivery_boys'])
        .map(TestDeliveryBoy.fromJson)
        .toList();
  }

  /// POST v1/distributor/test/delivery-boys
  static Future<void> createDeliveryBoy(String name, String mobile) async {
    await _api.post('v1/distributor/test/delivery-boys',
        body: {'name': name, 'mobile': mobile});
  }

  /// GET v1/distributor/test/assign-order?filter=unassigned|assigned|all
  static Future<List<TestOrder>> acceptedOrders(
      {String filter = 'unassigned'}) async {
    final res = await _api
        .get('v1/distributor/test/assign-order', query: {'filter': filter});
    return _list(_data(res)['orders']).map(TestOrder.fromJson).toList();
  }

  /// POST v1/distributor/test/assign-order
  static Future<void> assignOrder(int orderId, int deliveryBoyId) async {
    await _api.post('v1/distributor/test/assign-order',
        body: {'order_id': orderId, 'delivery_boy_id': deliveryBoyId});
  }

  /// GET v1/distributor/test/live  (all delivery boys + today's stats)
  static Future<List<LiveBoy>> liveBoys() async {
    final res = await _api.get('v1/distributor/test/live');
    final d = _data(res);
    final list = d['delivery_boys'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => LiveBoy.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET v1/distributor/test/live-path?assignment_id=  -> travelled points
  static Future<List<List<double>>> livePath(int assignmentId) async {
    final res = await _api
        .get('v1/distributor/test/live-path', query: {'assignment_id': assignmentId});
    final d = _data(res);
    final pts = d['points'];
    if (pts is! List) return [];
    return pts
        .whereType<List>()
        .where((p) => p.length >= 2)
        .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
        .toList();
  }

  // ───────────── Delivery boy (own token, kept in memory) ─────────────

  /// POST v1/delivery/test/login {name, mobile}
  static Future<DeliveryLoginResult> deliveryLogin(
      String name, String mobile) async {
    final res = await _api.post('v1/delivery/test/login',
        body: {'name': name, 'mobile': mobile}, auth: false);
    final d = _data(res);
    final boy = d['delivery_boy'] is Map
        ? Map<String, dynamic>.from(d['delivery_boy'] as Map)
        : <String, dynamic>{};
    return DeliveryLoginResult(
      '${d['token'] ?? ''}',
      int.tryParse('${boy['id']}') ?? 0,
      '${boy['name'] ?? name}',
      '${boy['mobile'] ?? mobile}',
    );
  }

  /// GET v1/delivery/test/orders?status=Assigned|Delivered|all
  static Future<List<DeliveryOrder>> deliveryOrders(String token,
      {String status = 'Assigned'}) async {
    final res = await _api.get('v1/delivery/test/orders',
        query: {'status': status}, tokenOverride: token);
    return _list(_data(res)['orders']).map(DeliveryOrder.fromJson).toList();
  }

  /// POST v1/delivery/test/orders {assignment_id, action: start, latitude, longitude}
  static Future<void> startDelivery(
      String token, int assignmentId, double lat, double lng) async {
    await _api.post('v1/delivery/test/orders',
        body: {
          'assignment_id': assignmentId,
          'action': 'start',
          'latitude': lat,
          'longitude': lng,
        },
        tokenOverride: token);
  }

  /// POST v1/delivery/test/track  (live ping while trip is Started)
  static Future<void> trackPing(String token, int assignmentId, double lat,
      double lng, double? heading) async {
    await _api.post('v1/delivery/test/track',
        body: {
          'assignment_id': assignmentId,
          'latitude': lat,
          'longitude': lng,
          if (heading != null) 'heading': heading,
        },
        tokenOverride: token);
  }

  /// POST v1/delivery/test/orders {assignment_id, action: delivered, ...}
  /// Server stores who/when/distance/time; retailer + distributor see it.
  static Future<DeliveryResult> markDelivered(
    String token,
    int assignmentId, {
    double? lat,
    double? lng,
    double distanceM = 0,
  }) async {
    final res = await _api.post('v1/delivery/test/orders',
        body: {
          'assignment_id': assignmentId,
          'action': 'delivered',
          if (lat != null && lng != null) ...{
            'latitude': lat,
            'longitude': lng,
          },
          'distance_m': distanceM.round(),
        },
        tokenOverride: token);
    final d = _data(res);
    return DeliveryResult(
        int.tryParse('${d['distance_m']}') ?? distanceM.round(),
        int.tryParse('${d['duration_s']}') ?? 0);
  }
}
