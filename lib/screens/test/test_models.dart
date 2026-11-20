int _i(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
double _d(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _dn(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String _s(dynamic v) => v == null ? '' : '$v';

/// 850 -> "850 m", 4210 -> "4.21 km".
String fmtDistanceM(num m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';

/// 45 -> "45 sec", 1130 -> "18 min 50 sec", 4000 -> "1 hr 6 min".
String fmtDurationS(int s) {
  if (s < 60) return '$s sec';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  if (h > 0) return '$h hr $m min';
  return sec == 0 ? '$m min' : '$m min $sec sec';
}

/// Retailer_test_orders row (retailer list, distributor list, assign list).
class TestOrder {
  final int id;
  final String orderNumber;
  final String retailerName;
  final String retailerMobile;
  final String productName;
  final double price;
  final int quantity;
  final double total;
  final String address;
  final double? lat;
  final double? lng;
  final String addressSource;
  final String status;
  final String createdAt;

  // Only on assign-order list.
  final int? assignmentId;
  final String? deliveryStatus;
  final int? boyId;
  final String? boyName;
  final String? boyMobile;
  final String? startedAt;
  final String? deliveredAt;
  final int distanceM;
  final int durationS;

  TestOrder({
    required this.id,
    required this.orderNumber,
    required this.retailerName,
    required this.retailerMobile,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.total,
    required this.address,
    required this.lat,
    required this.lng,
    required this.addressSource,
    required this.status,
    required this.createdAt,
    this.assignmentId,
    this.deliveryStatus,
    this.boyId,
    this.boyName,
    this.boyMobile,
    this.startedAt,
    this.deliveredAt,
    this.distanceM = 0,
    this.durationS = 0,
  });

  bool get isAssigned => assignmentId != null;
  bool get isDelivered => deliveryStatus == 'Delivered';
  bool get isOnTheWay => deliveryStatus == 'Started';

  factory TestOrder.fromJson(Map<String, dynamic> j) => TestOrder(
        id: _i(j['order_id'] ?? j['id']),
        orderNumber: _s(j['order_number']),
        retailerName: _s(j['retailer_name']),
        retailerMobile: _s(j['retailer_mobile']),
        productName: _s(j['product_name']),
        price: _d(j['price']),
        quantity: _i(j['quantity']),
        total: _d(j['total_amount']),
        address: _s(j['address']),
        lat: _dn(j['latitude']),
        lng: _dn(j['longitude']),
        addressSource: _s(j['address_source']),
        status: _s(j['status']).isEmpty ? 'Accepted' : _s(j['status']),
        createdAt: _s(j['created_at']),
        assignmentId: j['assignment_id'] == null ? null : _i(j['assignment_id']),
        deliveryStatus:
            j['delivery_status'] == null ? null : _s(j['delivery_status']),
        boyId: j['delivery_boy_id'] == null ? null : _i(j['delivery_boy_id']),
        boyName:
            j['delivery_boy_name'] == null ? null : _s(j['delivery_boy_name']),
        boyMobile: j['delivery_boy_mobile'] == null
            ? null
            : _s(j['delivery_boy_mobile']),
        startedAt: j['started_at'] == null ? null : _s(j['started_at']),
        deliveredAt: j['delivered_at'] == null ? null : _s(j['delivered_at']),
        distanceM: _i(j['distance_m']),
        durationS: _i(j['duration_s']),
      );
}

class TestDeliveryBoy {
  final int id;
  final String name;
  final String mobile;
  final bool active;
  final int activeOrders;

  TestDeliveryBoy({
    required this.id,
    required this.name,
    required this.mobile,
    required this.active,
    required this.activeOrders,
  });

  factory TestDeliveryBoy.fromJson(Map<String, dynamic> j) => TestDeliveryBoy(
        id: _i(j['id']),
        name: _s(j['name']),
        mobile: _s(j['mobile']),
        active: _i(j['is_active']) == 1,
        activeOrders: _i(j['active_orders']),
      );
}

class DeliveryLoginResult {
  final String token;
  final int id;
  final String name;
  final String mobile;
  DeliveryLoginResult(this.token, this.id, this.name, this.mobile);
}

/// One assigned order as the delivery boy sees it.
class DeliveryOrder {
  final int assignmentId;
  final int orderId;
  final String orderNumber;
  final String deliveryStatus;
  final String assignedAt;
  final String retailerName;
  final String retailerMobile;
  final String address;
  final double? lat;
  final double? lng;
  final String mapUrl;
  final String productName;
  final double price;
  final int quantity;
  final double total;
  final String? startedAt;
  final String? deliveredAt;
  final int distanceM;
  final int durationS;
  final int elapsedS; // seconds since Start Delivery (server clock)

  DeliveryOrder({
    required this.assignmentId,
    required this.orderId,
    required this.orderNumber,
    required this.deliveryStatus,
    required this.assignedAt,
    required this.retailerName,
    required this.retailerMobile,
    required this.address,
    required this.lat,
    required this.lng,
    required this.mapUrl,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.total,
    this.startedAt,
    this.deliveredAt,
    this.distanceM = 0,
    this.durationS = 0,
    this.elapsedS = 0,
  });

  bool get isStarted => deliveryStatus == 'Started';
  bool get isDelivered => deliveryStatus == 'Delivered';

  DeliveryOrder copyWithStatus(String status) => DeliveryOrder(
        assignmentId: assignmentId,
        orderId: orderId,
        orderNumber: orderNumber,
        deliveryStatus: status,
        assignedAt: assignedAt,
        retailerName: retailerName,
        retailerMobile: retailerMobile,
        address: address,
        lat: lat,
        lng: lng,
        mapUrl: mapUrl,
        productName: productName,
        price: price,
        quantity: quantity,
        total: total,
        startedAt: startedAt,
        deliveredAt: deliveredAt,
        distanceM: distanceM,
        durationS: durationS,
        elapsedS: elapsedS,
      );

  factory DeliveryOrder.fromJson(Map<String, dynamic> j) {
    final r = j['retailer'] is Map
        ? Map<String, dynamic>.from(j['retailer'] as Map)
        : <String, dynamic>{};
    final a = j['delivery_address'] is Map
        ? Map<String, dynamic>.from(j['delivery_address'] as Map)
        : <String, dynamic>{};
    final p = j['product'] is Map
        ? Map<String, dynamic>.from(j['product'] as Map)
        : <String, dynamic>{};
    return DeliveryOrder(
      assignmentId: _i(j['assignment_id']),
      orderId: _i(j['order_id']),
      orderNumber: _s(j['order_number']),
      deliveryStatus: _s(j['delivery_status']),
      assignedAt: _s(j['assigned_at']),
      retailerName: _s(r['name']),
      retailerMobile: _s(r['mobile']),
      address: _s(a['address']),
      lat: _dn(a['latitude']),
      lng: _dn(a['longitude']),
      mapUrl: _s(a['map_url']),
      productName: _s(p['name']),
      price: _d(p['price']),
      quantity: _i(p['quantity']),
      total: _d(p['total_amount']),
      startedAt: j['started_at'] == null ? null : _s(j['started_at']),
      deliveredAt: j['delivered_at'] == null ? null : _s(j['delivered_at']),
      distanceM: _i(j['distance_m']),
      durationS: _i(j['duration_s']),
      elapsedS: _i(j['elapsed_s']),
    );
  }
}

/// Result of POST v1/delivery/test/orders action=delivered.
class DeliveryResult {
  final int distanceM;
  final int durationS;
  DeliveryResult(this.distanceM, this.durationS);
}

/// Retailer-side live tracking snapshot of one order.
class OrderTracking {
  final TestOrder order;
  final bool isLive;
  final double? lat; // delivery boy position (only while on the way)
  final double? lng;
  final int? heading;
  final int? ageS; // seconds since last ping

  OrderTracking(this.order, this.isLive, this.lat, this.lng, this.heading, this.ageS);

  factory OrderTracking.fromJson(TestOrder o, Map<String, dynamic> t) =>
      OrderTracking(
        o,
        t['is_live'] == true,
        _dn(t['cur_lat']),
        _dn(t['cur_lng']),
        t['cur_heading'] == null ? null : _i(t['cur_heading']),
        t['cur_age_s'] == null ? null : _i(t['cur_age_s']),
      );
}

// ───────────────────────── Distributor live tracking ─────────────────────────

class LiveTrip {
  final int assignmentId;
  final String orderNumber;
  final String retailerName;
  final String address;
  final double? destLat;
  final double? destLng;
  final int distanceM; // trip so far
  final int elapsedS; // trip time so far

  LiveTrip({
    required this.assignmentId,
    required this.orderNumber,
    required this.retailerName,
    required this.address,
    this.destLat,
    this.destLng,
    this.distanceM = 0,
    this.elapsedS = 0,
  });

  factory LiveTrip.fromJson(Map<String, dynamic> j) => LiveTrip(
        assignmentId: _i(j['assignment_id']),
        orderNumber: _s(j['order_number']),
        retailerName: _s(j['retailer_name']),
        address: _s(j['address']),
        destLat: _dn(j['dest_lat']),
        destLng: _dn(j['dest_lng']),
        distanceM: _i(j['distance_m']),
        elapsedS: _i(j['elapsed_s']),
      );
}

class TodayStats {
  final int deliveries;
  final int inProgress;
  final int distanceM;
  final int durationS;
  const TodayStats(this.deliveries, this.inProgress, this.distanceM, this.durationS);

  factory TodayStats.fromJson(Map<String, dynamic> j) => TodayStats(
      _i(j['deliveries']), _i(j['in_progress']), _i(j['distance_m']), _i(j['duration_s']));
}

class LiveBoy {
  final int id;
  final String name;
  final String mobile;
  final bool isOnline; // on a trip and pinged in the last 2 min
  final bool onTrip;
  final double? lat;
  final double? lng;
  final int? heading;
  final int? ageS;
  final LiveTrip? trip;
  final TodayStats today;

  LiveBoy({
    required this.id,
    required this.name,
    required this.mobile,
    required this.isOnline,
    required this.onTrip,
    this.lat,
    this.lng,
    this.heading,
    this.ageS,
    this.trip,
    required this.today,
  });

  bool get hasPosition => lat != null && lng != null;

  factory LiveBoy.fromJson(Map<String, dynamic> j) => LiveBoy(
        id: _i(j['id']),
        name: _s(j['name']),
        mobile: _s(j['mobile']),
        isOnline: j['is_online'] == true,
        onTrip: j['on_trip'] == true,
        lat: _dn(j['lat']),
        lng: _dn(j['lng']),
        heading: j['heading'] == null ? null : _i(j['heading']),
        ageS: j['age_s'] == null ? null : _i(j['age_s']),
        trip: j['trip'] is Map
            ? LiveTrip.fromJson(Map<String, dynamic>.from(j['trip'] as Map))
            : null,
        today: j['today'] is Map
            ? TodayStats.fromJson(Map<String, dynamic>.from(j['today'] as Map))
            : const TodayStats(0, 0, 0, 0),
      );
}
