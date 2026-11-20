import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';

import '../../widgets/app_widgets.dart';
import 'salesman_models.dart';

/// "Merge Addresses": ONE route from the salesman's current location through
/// ALL assigned addresses, with live tracking (Google-Maps style).
///
/// - Stops are ordered nearest-neighbour from the current location.
/// - Route is road-based (OSRM, keyless) : me -> stop1 -> stop2 -> ...
/// - As the salesman moves, the blue line is redrawn from the NEW position
///   (throttled: 50 m or 20 s) and the camera follows him.
/// - A stop within [_reachMeters] is marked visited and dropped from the route.
/// - Only the next [_maxRouteStops] stops are routed at a time (OSRM public
///   server limits coordinates); the rest are still shown as pins.
class SalesmanMergedRouteScreen extends StatefulWidget {
  final List<SalesmanAddress> stops;

  const SalesmanMergedRouteScreen({super.key, required this.stops});

  @override
  State<SalesmanMergedRouteScreen> createState() =>
      _SalesmanMergedRouteScreenState();
}

class _SalesmanMergedRouteScreenState extends State<SalesmanMergedRouteScreen> {
  static const double _reachMeters = 40;
  static const int _maxRouteStops = 20;

  MapplsMapController? _map;
  StreamSubscription<Position>? _sub;
  final Dio _dio = Dio();

  LatLng? _me;
  bool _loading = true;
  String? _error;

  bool _styleReady = false;
  bool _fetching = false;
  bool _following = true;
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteAt;

  Line? _routeLine;
  final List<Circle> _pinCircles = [];
  final List<Symbol> _pinLabels = [];

  /// Remaining stops in visiting order.
  List<SalesmanAddress> _remaining = [];
  final List<SalesmanAddress> _visited = [];

  String _distance = '--';
  String _eta = '--';

  LatLng _ll(SalesmanAddress a) => LatLng(a.latitude, a.longitude);

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dio.close();
    super.dispose();
  }

  // ---------------------------------------------------------------- location

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return _fail('Please enable Location Services (GPS).');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return _fail('Location permission denied. Allow it in app settings.');
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final me = LatLng(p.latitude, p.longitude);
      _remaining = _orderNearestFirst(me, widget.stops);
      _onPosition(me);
    } catch (_) {
      return _fail('Could not get your location.');
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((p) => _onPosition(LatLng(p.latitude, p.longitude)),
        onError: (_) {});
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _loading = false;
    });
  }

  void _onPosition(LatLng me) {
    if (!mounted) return;

    // mark reached stops
    final reached = _remaining
        .where((s) =>
            Geolocator.distanceBetween(
                me.latitude, me.longitude, s.latitude, s.longitude) <=
            _reachMeters)
        .toList();

    setState(() {
      _me = me;
      _loading = false;
      _error = null;
      if (reached.isNotEmpty) {
        _visited.addAll(reached);
        _remaining.removeWhere(reached.contains);
      }
    });

    if (reached.isNotEmpty) {
      _redrawPins();
      _lastRouteAt = null; // force route refresh now
    }
    _maybeFetchRoute(me);
  }

  /// Greedy nearest-neighbour ordering starting from [start].
  List<SalesmanAddress> _orderNearestFirst(
      LatLng start, List<SalesmanAddress> input) {
    final left = List<SalesmanAddress>.from(input);
    final out = <SalesmanAddress>[];
    var cur = start;
    while (left.isNotEmpty) {
      var bestI = 0;
      var best = double.infinity;
      for (var i = 0; i < left.length; i++) {
        final d = Geolocator.distanceBetween(
            cur.latitude, cur.longitude, left[i].latitude, left[i].longitude);
        if (d < best) {
          best = d;
          bestI = i;
        }
      }
      final next = left.removeAt(bestI);
      out.add(next);
      cur = _ll(next);
    }
    return out;
  }

  // ------------------------------------------------------------------- route

  Future<void> _maybeFetchRoute(LatLng me) async {
    if (!_styleReady || _map == null || _fetching) return;

    if (_remaining.isEmpty) {
      await _clearRoute();
      if (mounted) {
        setState(() {
          _distance = '0 m';
          _eta = '0 min';
        });
      }
      return;
    }

    if (_lastRouteOrigin != null && _lastRouteAt != null) {
      final moved = Geolocator.distanceBetween(_lastRouteOrigin!.latitude,
          _lastRouteOrigin!.longitude, me.latitude, me.longitude);
      if (moved < 50 &&
          DateTime.now().difference(_lastRouteAt!) <
              const Duration(seconds: 20)) {
        return;
      }
    }

    _fetching = true;
    _lastRouteOrigin = me;
    _lastRouteAt = DateTime.now();
    try {
      final batch = _remaining.take(_maxRouteStops).toList();
      final coords = [
        '${me.longitude},${me.latitude}',
        for (final s in batch) '${s.longitude},${s.latitude}',
      ].join(';');

      final res = await _dio.get<dynamic>(
        'https://router.project-osrm.org/route/v1/driving/$coords',
        queryParameters: {'overview': 'full', 'geometries': 'polyline'},
      );
      final data = res.data;
      final routes = data is Map ? data['routes'] : null;
      if (routes is! List || routes.isEmpty) {
        debugPrint('Merged route: empty/bad response: $data');
        return;
      }
      final route = routes.first as Map;
      final pts = _decodePolyline(route['geometry'] as String);
      if (pts.length < 2 || _map == null) return;

      final old = _routeLine;
      _routeLine = await _map!.addLine(LineOptions(
        geometry: pts,
        lineColor: '#1A6FD4',
        lineWidth: 5.0,
        lineOpacity: 0.85,
      ));
      if (old != null) await _map!.removeLine(old);

      final meters = (route['distance'] as num?)?.toDouble() ?? 0;
      final secs = (route['duration'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() {
        _distance = meters >= 1000
            ? '${(meters / 1000).toStringAsFixed(1)} km'
            : '${meters.round()} m';
        _eta = secs >= 3600
            ? '${secs ~/ 3600} h ${(secs % 3600) ~/ 60} min'
            : '${(secs / 60).ceil()} min';
      });
    } catch (e) {
      debugPrint(
          'Merged route error: ${e is DioException ? e.response?.data : e}');
    } finally {
      _fetching = false;
    }
  }

  Future<void> _clearRoute() async {
    final old = _routeLine;
    _routeLine = null;
    if (old != null && _map != null) {
      try {
        await _map!.removeLine(old);
      } catch (_) {}
    }
  }

  /// Encoded polyline (precision 5) -> points.
  List<LatLng> _decodePolyline(String encoded) {
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

  // -------------------------------------------------------------------- pins

  /// Runs once map style is loaded (overlays need a loaded style).
  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _redrawPins();
    if (_me != null) _maybeFetchRoute(_me!);
  }

  /// Numbered pins: red = pending (number = visiting order), grey = visited.
  Future<void> _redrawPins() async {
    final c = _map;
    if (c == null || !_styleReady) return;

    for (final x in _pinCircles) {
      try {
        await c.removeCircle(x);
      } catch (_) {}
    }
    for (final x in _pinLabels) {
      try {
        await c.removeSymbol(x);
      } catch (_) {}
    }
    _pinCircles.clear();
    _pinLabels.clear();

    for (var i = 0; i < _remaining.length; i++) {
      final s = _remaining[i];
      _pinCircles.add(await c.addCircle(CircleOptions(
        geometry: _ll(s),
        circleRadius: i == 0 ? 12 : 10,
        circleColor: i == 0 ? '#1B8F3A' : '#E53935',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      )));
      _pinLabels.add(await c.addSymbol(SymbolOptions(
        geometry: _ll(s),
        textField: '${_visited.length + i + 1}. ${s.shopName}',
        textSize: 12.0,
        textOffset: const Offset(0, 1.8),
      )));
    }
    for (final s in _visited) {
      _pinCircles.add(await c.addCircle(CircleOptions(
        geometry: _ll(s),
        circleRadius: 8,
        circleColor: '#9E9E9E',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      )));
    }
  }

  // ------------------------------------------------------------------ camera

  void _fitAll() {
    final me = _me;
    if (me == null || _map == null) return;
    final pts = <LatLng>[me, ..._remaining.take(_maxRouteStops).map(_ll)];
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    setState(() => _following = false);
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng)),
      left: 60,
      right: 60,
      top: 160,
      bottom: 200,
    ));
  }

  void _recenter() {
    final me = _me;
    if (me == null || _map == null) return;
    setState(() => _following = true);
    _map!.animateCamera(CameraUpdate.newLatLngZoom(me, 17));
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final total = widget.stops.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Merged Route ($total stops)'),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Show full route',
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _fitAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : Stack(
                  children: [
                    MapplsMap(
                      initialCameraPosition: CameraPosition(
                        target: _me ?? _ll(widget.stops.first),
                        zoom: 15.0,
                      ),
                      onMapCreated: (c) => _map = c,
                      onStyleLoadedCallback: _onStyleLoaded,
                      myLocationEnabled: true,
                      myLocationTrackingMode: _following
                          ? MyLocationTrackingMode.tracking
                          : MyLocationTrackingMode.none,
                    ),
                    Positioned(top: 12, left: 12, right: 12, child: _topCard()),
                    Positioned(
                      right: 12,
                      bottom: 190,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter',
                        backgroundColor: Colors.white,
                        onPressed: _recenter,
                        child: Icon(
                          _following ? Icons.navigation : Icons.my_location,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                    Positioned(left: 0, right: 0, bottom: 0, child: _stopList()),
                  ],
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _startLocation();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _topCard() {
    final next = _remaining.isEmpty ? null : _remaining.first;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.flag, color: AppColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    next == null ? 'All stops done' : 'Next stop',
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  Text(
                    next == null
                        ? '${_visited.length} of ${widget.stops.length} visited'
                        : (next.shopName.isEmpty
                            ? 'Retailer #${next.retailerId}'
                            : next.shopName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_distance,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Text('ETA $_eta',
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stopList() {
    return Container(
      height: 170,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Text(
                  '${_remaining.length} remaining  •  ${_visited.length} visited',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: _remaining.length,
              itemBuilder: (_, i) {
                final s = _remaining[i];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        i == 0 ? AppColors.green : const Color(0xFFE53935),
                    child: Text('${_visited.length + i + 1}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white)),
                  ),
                  title: Text(
                    s.shopName.isEmpty ? 'Retailer #${s.retailerId}' : s.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(s.displayAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                  onTap: () {
                    _map?.animateCamera(
                        CameraUpdate.newLatLngZoom(_ll(s), 17));
                    setState(() => _following = false);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}