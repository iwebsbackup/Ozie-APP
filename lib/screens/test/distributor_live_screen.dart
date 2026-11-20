import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_widgets.dart';
import 'test_models.dart';
import 'test_service.dart';
import 'test_widgets.dart';
import 'truck_icon.dart';

/// Distributor: "View Live Tracking".
/// Map with every ONLINE delivery boy as a truck. Tap a truck (or a card) to
/// see that boy's path (driven part + road ahead to the shop) and follow him.
/// The sheet lists every delivery boy with today's distance + deliveries.
class DistributorLiveScreen extends StatefulWidget {
  const DistributorLiveScreen({super.key});

  @override
  State<DistributorLiveScreen> createState() => _DistributorLiveScreenState();
}

class _DistributorLiveScreenState extends State<DistributorLiveScreen> {
  static const String _truckAsset = 'assets/icons/truck-top-view.png';
  static const double _truckDp = 130; // truck longest side on map (dp)
  // Turn if the PNG does not point UP: right = 90, down = 180, left = 270.
  static const double _truckImageOffsetDeg = 0;
  static const LatLng _india = LatLng(28.6139, 77.2090);

  final Dio _dio = Dio();
  Timer? _poll;
  bool _busy = false;

  List<LiveBoy> _boys = [];
  bool _loading = true;
  String? _error;

  // selection
  int? _selId;
  bool _follow = true;
  List<LatLng> _driven = []; // path already driven (from server breadcrumbs)
  List<LatLng> _ahead = []; // road from the truck to the shop
  LatLng? _aheadFrom;

  // map
  MapplsMapController? _map;
  bool _styleReady = false;
  bool _truckOk = false;
  double _truckScale = 0.3;
  bool _framedAll = false;
  final List<Symbol> _symbols = [];
  final List<Circle> _circles = [];
  final List<Line> _lines = [];
  final Map<String, int> _symbolBoy = {}; // map symbol id -> delivery boy id

  LiveBoy? get _sel {
    for (final b in _boys) {
      if (b.id == _selId) return b;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _dio.close();
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────

  Future<void> _refresh() async {
    if (_busy) return; // never two requests at once
    _busy = true;
    try {
      final boys = await TestService.liveBoys();
      if (!mounted) return;
      setState(() {
        _boys = boys;
        _loading = false;
        _error = null;
      });
      await _updateSelectedPath();
      await _redraw();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = testErr(e);
        });
      }
    } finally {
      _busy = false;
    }
  }

  /// Driven path (server breadcrumbs) + road ahead for the selected boy.
  Future<void> _updateSelectedPath() async {
    final b = _sel;
    final trip = b?.trip;
    if (b == null || trip == null) {
      _driven = [];
      _ahead = [];
      _aheadFrom = null;
      return;
    }
    try {
      final pts = await TestService.livePath(trip.assignmentId);
      _driven = pts.map((p) => LatLng(p[0], p[1])).toList();
    } catch (_) {}

    if (!b.hasPosition || trip.destLat == null || trip.destLng == null) {
      _ahead = [];
      return;
    }
    final me = LatLng(b.lat!, b.lng!);
    if (_aheadFrom != null && _ahead.isNotEmpty && _meters(_aheadFrom!, me) < 30) {
      return; // barely moved, keep the road we have
    }
    _aheadFrom = me;
    final dest = LatLng(trip.destLat!, trip.destLng!);
    final coords =
        '${me.longitude},${me.latitude};${dest.longitude},${dest.latitude}';
    Map? best;
    for (final base in [
      'https://routing.openstreetmap.de/routed-car',
      'https://router.project-osrm.org',
    ]) {
      try {
        final res = await _dio.get<dynamic>('$base/route/v1/driving/$coords',
            queryParameters: {'overview': 'full', 'geometries': 'polyline'},
            options: Options(
                sendTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8)));
        final r = res.data is Map ? (res.data as Map)['routes'] : null;
        if (r is List) {
          for (final x in r.whereType<Map>()) {
            if (best == null ||
                ((x['duration'] as num?) ?? double.infinity) <
                    ((best['duration'] as num?) ?? double.infinity)) {
              best = x;
            }
          }
        }
      } catch (_) {}
    }
    if (best != null) {
      _ahead = [me, ..._decode(best['geometry'] as String)];
    }
  }

  static double _meters(LatLng a, LatLng b) {
    final dy = (b.latitude - a.latitude) * 110574.0;
    final dx = (b.longitude - a.longitude) *
        111320.0 *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
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

  // ───────────────────────── selection ─────────────────────────

  Future<void> _select(LiveBoy b) async {
    setState(() {
      _selId = b.id;
      _follow = true;
      _driven = [];
      _ahead = [];
      _aheadFrom = null;
    });
    await _updateSelectedPath();
    await _redraw(moveCamera: true);
  }

  Future<void> _clearSelection() async {
    setState(() {
      _selId = null;
      _driven = [];
      _ahead = [];
      _aheadFrom = null;
    });
    await _redraw();
    _frameAll();
  }

  // ───────────────────────── map ─────────────────────────

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _loadTruck();
    try {
      _map?.onSymbolTapped.add((Symbol s) {
        final id = _symbolBoy[s.id];
        if (id == null) return;
        for (final b in _boys) {
          if (b.id == id) {
            _select(b);
            return;
          }
        }
      });
    } catch (_) {}
    await _redraw();
    _frameAll();
  }

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
    _symbolBoy.clear();
  }

  Future<void> _redraw({bool moveCamera = false}) async {
    final c = _map;
    if (c == null || !_styleReady || !mounted) return;
    await _clear();

    final sel = _sel;
    final trip = sel?.trip;

    // driven path (grey) + road ahead (blue, white casing)
    if (_driven.length > 1) {
      _lines.add(await c.addLine(LineOptions(
        geometry: _driven,
        lineColor: '#5F6368',
        lineWidth: 5.0,
        lineOpacity: 0.85,
      )));
    }
    if (_ahead.length > 1) {
      _lines.add(await c.addLine(LineOptions(
        geometry: _ahead,
        lineColor: '#FFFFFF',
        lineWidth: 10.0,
      )));
      _lines.add(await c.addLine(LineOptions(
        geometry: _ahead,
        lineColor: '#4285F4',
        lineWidth: 6.0,
      )));
    }
    // shop pin
    if (trip != null && trip.destLat != null && trip.destLng != null) {
      final d = LatLng(trip.destLat!, trip.destLng!);
      _circles.add(await c.addCircle(CircleOptions(
        geometry: d,
        circleRadius: 10,
        circleColor: '#E53935',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      )));
      _symbols.add(await c.addSymbol(SymbolOptions(
        geometry: d,
        textField: trip.retailerName,
        textSize: 12.0,
        textOffset: const Offset(0, 1.8),
      )));
    }
    // trucks: every online boy
    for (final b in _boys) {
      if (!b.isOnline || !b.hasPosition) continue;
      final pos = LatLng(b.lat!, b.lng!);
      final Symbol sym;
      if (_truckOk) {
        sym = await c.addSymbol(SymbolOptions(
          geometry: pos,
          iconImage: 'truck',
          iconSize: _truckScale,
          iconRotate: ((b.heading ?? 0) + _truckImageOffsetDeg) % 360,
          textField: b.name,
          textSize: 12.0,
          textOffset: const Offset(0, 4.6),
        ));
      } else {
        _circles.add(await c.addCircle(CircleOptions(
          geometry: pos,
          circleRadius: 12,
          circleColor: b.id == _selId ? '#1A73E8' : '#0C831F',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3.5,
        )));
        sym = await c.addSymbol(SymbolOptions(
          geometry: pos,
          textField: b.name,
          textSize: 12.0,
          textOffset: const Offset(0, 1.9),
        ));
      }
      _symbols.add(sym);
      _symbolBoy[sym.id] = b.id;
    }

    // camera
    if (sel != null && sel.hasPosition && _follow) {
      c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(sel.lat!, sel.lng!), 16.0));
    } else if (!_framedAll && _selId == null) {
      _frameAll();
    }
    if (moveCamera && sel != null && sel.hasPosition) {
      c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(sel.lat!, sel.lng!), 16.0));
    }
  }

  void _frameAll() {
    final c = _map;
    if (c == null || !_styleReady) return;
    final pts = _boys
        .where((b) => b.isOnline && b.hasPosition)
        .map((b) => LatLng(b.lat!, b.lng!))
        .toList();
    if (pts.isEmpty) return;
    _framedAll = true;
    if (pts.length == 1) {
      c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15.0));
      return;
    }
    var minLa = pts.first.latitude, maxLa = minLa;
    var minLo = pts.first.longitude, maxLo = minLo;
    for (final p in pts) {
      minLa = math.min(minLa, p.latitude);
      maxLa = math.max(maxLa, p.latitude);
      minLo = math.min(minLo, p.longitude);
      maxLo = math.max(maxLo, p.longitude);
    }
    c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLa, minLo), northeast: LatLng(maxLa, maxLo)),
      left: 60,
      right: 60,
      top: 60,
      bottom: 300,
    ));
  }

  void _fitSelected() {
    final c = _map, b = _sel;
    if (c == null || b == null || !b.hasPosition) return;
    final pts = <LatLng>[LatLng(b.lat!, b.lng!), ..._driven];
    final t = b.trip;
    if (t?.destLat != null && t?.destLng != null) {
      pts.add(LatLng(t!.destLat!, t.destLng!));
    }
    var minLa = pts.first.latitude, maxLa = minLa;
    var minLo = pts.first.longitude, maxLo = minLo;
    for (final p in pts) {
      minLa = math.min(minLa, p.latitude);
      maxLa = math.max(maxLa, p.latitude);
      minLo = math.min(minLo, p.longitude);
      maxLo = math.max(maxLo, p.longitude);
    }
    c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLa, minLo), northeast: LatLng(maxLa, maxLo)),
      left: 60,
      right: 60,
      top: 60,
      bottom: 320,
    ));
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final online = _boys.where((b) => b.isOnline).length;
    return Scaffold(
      appBar: testAppBar(context, title: 'Live Tracking'),
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          MapplsMap(
            initialCameraPosition:
                const CameraPosition(target: _india, zoom: 11.0),
            onMapCreated: (c) => _map = c,
            onStyleLoadedCallback: _onStyleLoaded,
            compassEnabled: false,
          ),

          // top chips
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4)
                  ]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle,
                    size: 10,
                    color: online > 0 ? const Color(0xFF0C831F) : Colors.grey),
                const SizedBox(width: 6),
                Text('$online online  •  ${_boys.length} delivery boys',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (_sel != null)
            Positioned(
              right: 12,
              top: 12,
              child: Column(
                children: [
                  _roundBtn(Icons.close, 'Stop tracking', _clearSelection),
                  const SizedBox(height: 10),
                  _roundBtn(Icons.zoom_out_map, 'Show full path', () {
                    setState(() => _follow = false);
                    _fitSelected();
                  }),
                  const SizedBox(height: 10),
                  _roundBtn(Icons.my_location, 'Follow truck', () {
                    setState(() => _follow = true);
                    final b = _sel;
                    if (b != null && b.hasPosition) {
                      _map?.animateCamera(CameraUpdate.newLatLngZoom(
                          LatLng(b.lat!, b.lng!), 16.0));
                    }
                  }, active: _follow),
                ],
              ),
            ),

          // bottom sheet: every delivery boy + today's stats
          DraggableScrollableSheet(
            initialChildSize: 0.34,
            minChildSize: 0.14,
            maxChildSize: 0.88,
            builder: (context, scroll) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
              ),
              child: _sheetBody(scroll),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap,
          {bool active = false}) =>
      Material(
        color: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tip,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon,
                  size: 22,
                  color: active ? const Color(0xFF1A73E8) : Colors.black87),
            ),
          ),
        ),
      );

  Widget _sheetBody(ScrollController scroll) {
    final totalDeliveries = _boys.fold<int>(0, (a, b) => a + b.today.deliveries);
    final totalDist = _boys.fold<int>(0, (a, b) => a + b.today.distanceM);

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: Colors.black26, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Row(
          children: [
            const Expanded(
              child: Text('Delivery boys',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
            ),
            Text('Today: $totalDeliveries delivered • ${fmtDistanceM(totalDist)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!,
                style: const TextStyle(color: AppColors.dangerText, fontSize: 13)),
          )
        else if (_boys.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No delivery boys yet. Create one first.',
                style: TextStyle(color: AppColors.muted)),
          )
        else
          ..._boys.map(_boyCard),
      ],
    );
  }

  Widget _boyCard(LiveBoy b) {
    final selected = b.id == _selId;
    final Color dot = b.isOnline
        ? const Color(0xFF0C831F)
        : (b.onTrip ? const Color(0xFFF59E0B) : Colors.grey);
    final String status = b.isOnline
        ? 'Online • on delivery'
        : (b.onTrip ? 'On delivery • no signal' : 'Idle');
    final t = b.trip;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: selected ? const Color(0xFF1A73E8) : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => selected ? _clearSelection() : _select(b),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 22, color: AppColors.text),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        Row(children: [
                          Icon(Icons.circle, size: 9, color: dot),
                          const SizedBox(width: 5),
                          Text(
                              b.isOnline && b.ageS != null
                                  ? '$status • ${b.ageS}s ago'
                                  : status,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                        ]),
                      ],
                    ),
                  ),
                  if (b.mobile.isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Call',
                      onPressed: () async {
                        try {
                          await launchUrl(Uri.parse('tel:${b.mobile}'));
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.call, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // today's record
              Row(
                children: [
                  _stat('Delivered', '${b.today.deliveries}'),
                  _stat('Distance', fmtDistanceM(b.today.distanceM)),
                  _stat('Time', fmtDurationS(b.today.durationS)),
                ],
              ),
              if (t != null) ...[
                const Divider(height: 18),
                Text('Order #${t.orderNumber}  →  ${t.retailerName}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (t.address.isNotEmpty)
                  Text(t.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 4),
                Text(
                    'This trip: ${fmtDistanceM(t.distanceM)} • ${fmtDurationS(t.elapsedS)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.text)),
              ],
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Tracking live • tap again to stop',
                      style: TextStyle(fontSize: 11, color: Color(0xFF1A73E8))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
          ],
        ),
      );
}