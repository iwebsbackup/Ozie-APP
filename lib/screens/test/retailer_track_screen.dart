import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_widgets.dart';
import 'test_models.dart';
import 'test_service.dart';
import 'test_widgets.dart';
import 'truck_icon.dart';

/// Retailer: tap an order in "Where is my order" -> this screen.
/// Green header with live status / "Arriving in N minutes", map with the
/// delivery boy moving towards the shop, delivery partner card, order details.
class RetailerTrackScreen extends StatefulWidget {
  final TestOrder order;
  const RetailerTrackScreen({super.key, required this.order});

  @override
  State<RetailerTrackScreen> createState() => _RetailerTrackScreenState();
}

class _RetailerTrackScreenState extends State<RetailerTrackScreen> {
  static const Color _green = Color(0xFF0C831F);

  late OrderTracking _t;
  Timer? _poll;
  final Dio _dio = Dio();

  MapplsMapController? _map;
  bool _styleReady = false;
  bool _fitted = false;
  final List<Circle> _circles = [];
  final List<Line> _lines = [];
  final List<Symbol> _symbols = [];

  static const String _truckAsset = 'assets/icons/truck-top-view.png';
  static const double _truckDp = 100; // truck's longest side on the map (dp)
  // Turn this if the PNG does not point UP (north): right = 90, down = 180, left = 270.
  static const double _truckImageOffsetDeg = 0;
  double _truckDeg = 0; // direction the truck is driving, 0 = north, 90 = east
  LatLng? _lastBoy;
  bool _truckOk = false;
  bool _homeOk = false;
  static const double _homeDp = 52; // home pin size
  double _truckScale = 0.3;
  bool _followBoy = true; // camera stays on the delivery boy
  double? _routeM;
  List<LatLng> _routePts = [];
  LatLng? _routeFrom;
  bool _routing = false;
  String? _error;

  TestOrder get _o => _t.order;

  LatLng? get _dest => (_o.lat != null && _o.lng != null)
      ? LatLng(_o.lat!, _o.lng!)
      : null;
  LatLng? get _boy => (_t.isLive && _t.lat != null && _t.lng != null)
      ? LatLng(_t.lat!, _t.lng!)
      : null;

  @override
  void initState() {
    super.initState();
    _t = OrderTracking(widget.order, false, null, null, null, null);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _dio.close();
    super.dispose();
  }

  bool _busy = false; // never run two refreshes at once

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final t = await TestService.trackOrder(widget.order.id);
      if (!mounted) return;
      setState(() {
        _t = t;
        _error = null;
      });
      if (t.order.isDelivered) _poll?.cancel();
      await _updateRoute();
      _updateBearing();
      _redraw();
    } catch (e) {
      if (mounted) setState(() => _error = testErr(e));
    } finally {
      _busy = false;
    }
  }

  // ───────────────────────── truck direction ─────────────────────────

  static double _bearingDeg(LatLng a, LatLng b) {
    final p1 = a.latitude * math.pi / 180, p2 = b.latitude * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static double _metersBetween(LatLng a, LatLng b) {
    final dy = (b.latitude - a.latitude) * 110574.0;
    final dx = (b.longitude - a.longitude) *
        111320.0 *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Truck faces where it is really going:
  /// 1) last two live positions (real movement), 2) next point of the road
  /// route, 3) heading reported by the delivery boy's phone.
  void _updateBearing() {
    final boy = _boy;
    if (boy == null) {
      _lastBoy = null;
      return;
    }
    final prev = _lastBoy;
    if (prev != null && _metersBetween(prev, boy) >= 4) {
      _truckDeg = _bearingDeg(prev, boy);
      _lastBoy = boy;
      return;
    }
    if (prev == null) _lastBoy = boy;
    // standing / first fix -> face along the route
    for (final p in _routePts) {
      if (_metersBetween(boy, p) >= 8) {
        _truckDeg = _bearingDeg(boy, p);
        return;
      }
    }
    if (_t.heading != null) _truckDeg = _t.heading!.toDouble();
  }

  // ───────────────────────── route / eta ─────────────────────────

  Future<void> _updateRoute() async {
    final boy = _boy, dest = _dest;
    if (boy == null || dest == null) {
      _routeM = null;
      _routePts = [];
      return;
    }
    if (_routing) return;
    // skip if the boy barely moved since the last route
    if (_routeFrom != null &&
        (boy.latitude - _routeFrom!.latitude).abs() < 0.00008 &&
        (boy.longitude - _routeFrom!.longitude).abs() < 0.00008 &&
        _routePts.isNotEmpty) {
      return;
    }
    _routing = true;
    _routeFrom = boy;
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${boy.longitude},${boy.latitude};${dest.longitude},${dest.latitude}';
      final res = await _dio.get<dynamic>(url, queryParameters: {
        'overview': 'full',
        'geometries': 'polyline',
      });
      final data = res.data;
      final routes = data is Map ? data['routes'] : null;
      if (routes is List && routes.isNotEmpty && routes.first is Map) {
        final r = routes.first as Map;
        _routePts = [boy, ..._decode(r['geometry'] as String)];
        _routeM = (r['distance'] as num?)?.toDouble();
      }
    } catch (_) {
      // keep the previous route
    } finally {
      _routing = false;
    }
  }

  List<LatLng> _decode(String encoded) {
    final out = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      out.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return out;
  }

  // ───────────────────────── map ─────────────────────────

  Future<void> _clear() async {
    final c = _map;
    if (c == null) return;
    for (final l in _lines) {
      await c.removeLine(l);
    }
    for (final x in _circles) {
      await c.removeCircle(x);
    }
    for (final s in _symbols) {
      await c.removeSymbol(s);
    }
    _lines.clear();
    _circles.clear();
    _symbols.clear();
  }

  Future<void> _redraw() async {
    final c = _map;
    if (c == null || !_styleReady || !mounted) return;
    await _clear();
    final dest = _dest, boy = _boy;

    if (_routePts.length > 1) {
      _lines.add(await c.addLine(LineOptions(
        geometry: _routePts,
        lineColor: '#FFFFFF',
        lineWidth: 8.0,
      )));
      _lines.add(await c.addLine(LineOptions(
        geometry: _routePts,
        lineColor: '#1E2A3B',
        lineWidth: 4.0,
        lineOpacity: 0.9,
      )));
    }
    if (dest != null) {
      if (_homeOk) {
        // retailer's location: home pin (Blinkit style)
        _symbols.add(await c.addSymbol(SymbolOptions(
          geometry: dest,
          iconImage: 'home',
          iconSize: _homeDp / 128.0,
          textField: 'Your location',
          textSize: 12.0,
          textOffset: const Offset(0, 2.6),
        )));
      } else {
        _circles.add(await c.addCircle(CircleOptions(
          geometry: dest,
          circleRadius: 9,
          circleColor: '#1A73E8',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        )));
      }
    }
    if (boy != null) {
      if (_truckOk) {
        // truck image, turned to the direction it is driving
        _symbols.add(await c.addSymbol(SymbolOptions(
          geometry: boy,
          iconImage: 'truck',
          iconSize: _truckScale,
          iconRotate: (_truckDeg + _truckImageOffsetDeg) % 360,
          textField: _o.boyName ?? 'Delivery partner',
          textSize: 12.0,
          textOffset: const Offset(0, 2.6),
        )));
      } else {
        _circles.add(await c.addCircle(CircleOptions(
          geometry: boy,
          circleRadius: 11,
          circleColor: '#0C831F',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3.5,
        )));
      }
    }

    // delivery boy FIRST: camera stays on him; button switches to full route
    if (boy != null && _followBoy) {
      c.animateCamera(CameraUpdate.newLatLngZoom(boy, 16.0));
    } else if (boy != null && dest != null) {
      _fit(boy, dest);
    } else if (dest != null && !_fitted) {
      _fitted = true;
      c.animateCamera(CameraUpdate.newLatLngZoom(dest, 16.0));
    }
  }

  /// Draws the home pin in code (dark circle, white ring, white home glyph),
  /// 128x128 px, and registers it as the map icon 'home'.
  Future<void> _loadHome() async {
    final c = _map;
    if (c == null || _homeOk) return;
    try {
      const size = 128.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, size, size));
      const center = Offset(size / 2, size / 2);
      canvas.drawCircle(center, size / 2 - 2, Paint()..color = Colors.white);
      canvas.drawCircle(
          center, size / 2 - 10, Paint()..color = const Color(0xFF1E2A3B));
      final icon = Icons.home_rounded;
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 70,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      await c.addImage('home', bd.buffer.asUint8List());
      _homeOk = true;
    } catch (e) {
      debugPrint('home icon failed: $e');
    }
  }

  /// Registers assets/icons/truck-top-view.png as the map icon.
  Future<void> _loadTruck() async {
    final c = _map;
    if (c == null || _truckOk) return;
    try {
      // background removed + cropped to the truck only
      final t = await TruckIcon.load(_truckAsset);
      _truckScale = _truckDp / t.longestSide;
      await c.addImage('truck', t.png);
      _truckOk = true;
    } catch (e) {
      debugPrint('truck icon load failed: $e');
    }
  }

  void _fit(LatLng a, LatLng b) {
    final c = _map;
    if (c == null) return;
    final sw = LatLng(a.latitude < b.latitude ? a.latitude : b.latitude,
        a.longitude < b.longitude ? a.longitude : b.longitude);
    final ne = LatLng(a.latitude > b.latitude ? a.latitude : b.latitude,
        a.longitude > b.longitude ? a.longitude : b.longitude);
    c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: sw, northeast: ne),
      left: 60,
      right: 60,
      top: 60,
      bottom: 60,
    ));
  }

  // ───────────────────────── header text ─────────────────────────

  ({String top, String big}) get _headline {
    final o = _o;
    if (o.status == 'Rejected') {
      return (top: 'Order update', big: 'Order rejected');
    }
    if (o.isDelivered) {
      return (top: 'Order delivered', big: 'Delivered');
    }
    if (o.isOnTheWay) {
      return (top: 'On the way', big: 'Delivery partner is on the way');
    }
    if (o.isAssigned) {
      return (top: 'Partner assigned', big: 'Getting ready to deliver');
    }
    if (o.status == 'Accepted') {
      return (top: 'Packing your order', big: 'Order accepted');
    }
    return (top: 'Order placed', big: 'Waiting for distributor');
  }

  String get _partnerLine {
    final o = _o;
    if (o.status == 'Rejected') return 'The distributor rejected this order.';
    if (o.isDelivered) return 'Delivered by ${o.boyName ?? '-'}';
    if (o.isOnTheWay) {
      return '${o.boyName ?? 'Your delivery partner'} is on the way to you';
    }
    if (o.isAssigned) {
      return '${o.boyName ?? 'A delivery partner'} will pick up your order soon';
    }
    if (o.status == 'Accepted') {
      return "We'll assign a delivery partner as soon as your order is packed";
    }
    return 'Waiting for the distributor to accept your order';
  }

  Future<void> _call(String number) async {
    if (number.isEmpty) return;
    try {
      await launchUrl(Uri.parse('tel:$number'));
    } catch (_) {}
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final h = _headline;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _header(h),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.dangerText, fontSize: 12)),
                    ),
                  _mapCard(),
                  const SizedBox(height: 14),
                  _partnerCard(),
                  const SizedBox(height: 14),
                  if (_o.isDelivered) ...[
                    _deliveredCard(),
                    const SizedBox(height: 14),
                  ],
                  _orderCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(({String top, String big}) h) => Container(
        width: double.infinity,
        color: _green,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Material(
                      color: Colors.white24,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.arrow_back, color: Colors.white),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(h.top,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
                const SizedBox(height: 6),
                Text(h.big,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Order #${_o.orderNumber}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  Widget _mapCard() {
    final dest = _dest;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 260,
        child: dest == null
            ? Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: const Text('No map location for this order.',
                    style: TextStyle(color: AppColors.muted)),
              )
            : Stack(
                children: [
                  MapplsMap(
                    initialCameraPosition:
                        CameraPosition(target: _boy ?? dest, zoom: 15.0),
                    onMapCreated: (c) => _map = c,
                    onStyleLoadedCallback: () async {
                      _styleReady = true;
                      await _loadTruck();
                      await _loadHome();
                      _redraw();
                    },
                    compassEnabled: false,
                  ),
                  if (!_t.isLive && !_o.isDelivered)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4)
                            ]),
                        child: const Text('Live tracking starts when the partner leaves',
                            style: TextStyle(fontSize: 11, color: AppColors.text)),
                      ),
                    ),
                  if (_t.isLive && _routeM != null)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4)
                            ]),
                        child: Text('${fmtDistanceM(_routeM!)} away',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text)),
                      ),
                    ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          final b = _boy;
                          if (b == null) {
                            _map?.animateCamera(
                                CameraUpdate.newLatLngZoom(dest, 16.0));
                            return;
                          }
                          setState(() => _followBoy = !_followBoy);
                          if (_followBoy) {
                            _map?.animateCamera(CameraUpdate.newLatLngZoom(b, 16.0));
                          } else {
                            _fit(b, dest);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(_followBoy ? Icons.zoom_out_map : Icons.local_shipping_outlined, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _partnerCard() {
    final o = _o;
    final hasBoy = o.isAssigned && (o.boyName ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: Color(0xFFFFF3D6), shape: BoxShape.circle),
                child: const Icon(Icons.delivery_dining,
                    size: 30, color: Color(0xFF9A6700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(_partnerLine,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.25)),
              ),
            ],
          ),
          if (hasBoy) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.boyName!,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      if ((o.boyMobile ?? '').isNotEmpty)
                        Text(o.boyMobile!,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
                ),
                if ((o.boyMobile ?? '').isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _call(o.boyMobile!),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: const BorderSide(color: _green),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          TestOrderTracker(o),
        ],
      ),
    );
  }

  Widget _deliveredCard() {
    final o = _o;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.check_circle, color: AppColors.successText),
            SizedBox(width: 8),
            Text('Delivered',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.successText)),
          ]),
          const SizedBox(height: 8),
          if ((o.deliveredAt ?? '').isNotEmpty)
            Text('On ${o.deliveredAt}',
                style: const TextStyle(fontSize: 13, color: AppColors.text)),
          Text('By ${o.boyName ?? '-'}',
              style: const TextStyle(fontSize: 13, color: AppColors.text)),
          Text('Distance travelled: ${fmtDistanceM(o.distanceM)}',
              style: const TextStyle(fontSize: 13, color: AppColors.text)),
          Text('Time taken: ${fmtDurationS(o.durationS)}',
              style: const TextStyle(fontSize: 13, color: AppColors.text)),
        ],
      ),
    );
  }

  Widget _orderCard() {
    final o = _o;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order details',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
          TestLine(Icons.inventory_2_outlined,
              '${o.productName}  ×  ${o.quantity}  @  ${formatInr(o.price)}'),
          TestLine(Icons.currency_rupee, 'Total ${formatInr(o.total)}'),
          TestLine(Icons.place_outlined, o.address),
        ],
      ),
    );
  }
}