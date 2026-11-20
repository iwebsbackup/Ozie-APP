import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_widgets.dart';
import 'test_models.dart';
import 'test_service.dart';
import 'test_widgets.dart';

/// Delivery boy is "arrived" inside this radius -> Mark Delivered unlocks.
const double kArriveRadiusM = 100;

/// One road step from the router (turn-by-turn).
class _Step {
  final LatLng at; // where the maneuver happens
  final String type;
  final String modifier;
  final String road;
  _Step(this.at, this.type, this.modifier, this.road);
}

/// Live delivery screen: Mappls map, best road route, turn banner, compass,
/// from/to address, distance travelled + timer. When the delivery boy reaches
/// the destination, "Mark Delivered" appears.
///
/// Pops with `true` when the order was delivered.
class DeliveryNavScreen extends StatefulWidget {
  final String token;
  final DeliveryOrder order;
  const DeliveryNavScreen({super.key, required this.token, required this.order});

  @override
  State<DeliveryNavScreen> createState() => _DeliveryNavScreenState();
}

class _DeliveryNavScreenState extends State<DeliveryNavScreen> {
  // ── map / sensors ──
  MapplsMapController? _map;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _clock;
  Timer? _pingTimer;
  final Dio _dio = Dio();

  // ── state ──
  LatLng? _dest;
  LatLng? _me;
  double? _compass; // phone compass 0-360 (smoothed)
  double _gpsCourse = 0;
  double _gpsSpeed = 0; // m/s
  double? _cSin, _cCos;

  bool _loading = true;
  String? _error;
  bool _styleReady = false;
  bool _follow = true; // camera follows me
  bool _northUp = false; // false = heading-up
  bool _delivering = false;

  // route
  Line? _routeLine;
  Line? _casingLine;
  bool _sheetOpen = false;
  bool _fetching = false;
  bool _fitted = false;
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteAt;
  double? _routeMeters;
  int? _routeSecs;
  List<_Step> _steps = [];
  List<LatLng> _routePts = []; // user -> destination, along the road
  List<int> _stepVertex = []; // polyline index of each maneuver
  int _meSeg = 0; // polyline segment the user is on
  int _stepIdx = 1;

  // trip
  late double _travelled; // metres (server base + this session)
  late DateTime _startedAt;
  int _elapsedS = 0;
  Position? _lastCounted;
  DateTime? _lastCountedAt;

  // addresses
  String _fromAddress = 'Finding your location...';
  LatLng? _lastGeocoded;
  DateTime? _lastGeocodedAt;
  bool _geocoding = false;

  DeliveryOrder get _o => widget.order;

  @override
  void initState() {
    super.initState();
    _travelled = _o.distanceM.toDouble();
    _startedAt = DateTime.now().subtract(Duration(seconds: _o.elapsedS));
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedS = DateTime.now().difference(_startedAt).inSeconds);
    });
    _init();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _clock?.cancel();
    _pingTimer?.cancel();
    _dio.close();
    super.dispose();
  }

  // ───────────────────────── setup ─────────────────────────

  Future<void> _init() async {
    // destination: order GPS, else geocode the address text
    if (_o.lat != null && _o.lng != null) {
      _dest = LatLng(_o.lat!, _o.lng!);
    } else if (_o.address.trim().isNotEmpty) {
      try {
        final r = await Geocoding().locationFromAddress(_o.address);
        if (r.isNotEmpty) _dest = LatLng(r.first.latitude, r.first.longitude);
      } catch (_) {}
    }
    if (_dest == null) {
      return _fail('Delivery address has no map location.');
    }
    await _startLocation();
    _startCompass();
    // live ping to server every 8 s (one at a time) (retailer/distributor tracking + backup distance)
    _pingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _ping());
  }

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
      _onPosition(p);
    } catch (_) {
      return _fail('Could not get your location.');
    }
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(_onPosition, onError: (_) {});
  }

  void _startCompass() {
    try {
      _compassSub = FlutterCompass.events?.listen((e) {
        final h = e.heading;
        if (h == null) return;
        final r = h * math.pi / 180;
        // circular low-pass filter: no jitter, no 359 -> 0 jump
        _cSin = _cSin == null ? math.sin(r) : _cSin! * 0.8 + math.sin(r) * 0.2;
        _cCos = _cCos == null ? math.cos(r) : _cCos! * 0.8 + math.cos(r) * 0.2;
        final c = ((math.atan2(_cSin!, _cCos!) * 180 / math.pi) % 360 + 360) % 360;
        if (!mounted) return;
        setState(() => _compass = c);
      }, onError: (_) {});
    } catch (_) {}
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _loading = false;
    });
  }

  // ───────────────────────── position ─────────────────────────

  /// Heading used for map rotation + arrow:
  /// moving -> GPS course, slow/standing -> phone compass.
  double get _heading {
    if (_gpsSpeed >= 1.5) return _gpsCourse;
    return _compass ?? _gpsCourse;
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    final me = LatLng(p.latitude, p.longitude);

    if (p.speed >= 1.5 && p.heading >= 0) {
      _gpsCourse = p.heading;
    }
    _gpsSpeed = p.speed < 0 ? 0 : p.speed;
    _countDistance(p);

    setState(() {
      _me = me;
      _loading = false;
      _error = null;
    });

    _advanceStep(me);
    _trimRoute(me);
    _maybeFetchRoute(me);
    _maybeGeocode(me);
    _followCamera();
  }

  /// Walked distance: ignores bad accuracy, GPS jitter and teleports.
  void _countDistance(Position p) {
    final last = _lastCounted;
    final lastAt = _lastCountedAt;
    final now = DateTime.now();
    if (p.accuracy > 35) return; // too noisy, skip
    if (last == null || lastAt == null) {
      _lastCounted = p;
      _lastCountedAt = now;
      return;
    }
    final d = Geolocator.distanceBetween(
        last.latitude, last.longitude, p.latitude, p.longitude);
    final dt = math.max(1, now.difference(lastAt).inSeconds);
    if (d < 6) return; // jitter while standing
    _lastCounted = p;
    _lastCountedAt = now;
    if (d / dt > 45) return; // > 160 km/h = GPS jump
    _travelled += d;
  }

  double _distToDest() {
    final me = _me, d = _dest;
    if (me == null || d == null) return double.infinity;
    return Geolocator.distanceBetween(
        me.latitude, me.longitude, d.latitude, d.longitude);
  }

  bool get _arrived => _distToDest() <= kArriveRadiusM;

  bool _pinging = false; // never stack pings if the server is slow

  void _ping() {
    final me = _me;
    if (me == null || _pinging) return;
    _pinging = true;
    TestService.trackPing(widget.token, _o.assignmentId, me.latitude,
            me.longitude, _heading)
        .catchError((_) {})
        .whenComplete(() => _pinging = false);
  }

  // ───────────────────────── camera ─────────────────────────

  void _followCamera() {
    final me = _me;
    if (!_follow || me == null || _map == null || !_styleReady) return;
    _map!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
      target: me,
      zoom: 17.5,
      bearing: _northUp ? 0 : _heading,
      tilt: _northUp ? 0 : 30,
    )));
  }

  void _overview() {
    setState(() => _follow = false);
    _fitBoth();
  }

  void _recenter() {
    setState(() => _follow = true);
    _followCamera();
  }

  void _fitBoth() {
    final me = _me, d = _dest;
    if (me == null || d == null || _map == null) return;
    final sw = LatLng(math.min(me.latitude, d.latitude),
        math.min(me.longitude, d.longitude));
    final ne = LatLng(math.max(me.latitude, d.latitude),
        math.max(me.longitude, d.longitude));
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: sw, northeast: ne),
      left: 80,
      right: 80,
      top: 220,
      bottom: 260,
    ));
  }

  // ───────────────────────── route ─────────────────────────

  /// Best road route (fastest of the alternatives) + turn steps.
  /// Refetch only after 50 m moved or 20 s (saves quota).
  Future<void> _maybeFetchRoute(LatLng me) async {
    final dest = _dest;
    if (!_styleReady || _map == null || _fetching || _trimming || dest == null) return;
    if (_lastRouteOrigin != null && _lastRouteAt != null) {
      final moved = Geolocator.distanceBetween(_lastRouteOrigin!.latitude,
          _lastRouteOrigin!.longitude, me.latitude, me.longitude);
      final offRoute = _routePts.length > 1 && _routeDist(me).$1 > 40;
      final gap = DateTime.now().difference(_lastRouteAt!).inSeconds;
      // off the road -> re-route within 4 s; else after 50 m moved or 20 s
      final should = offRoute ? gap >= 4 : (moved >= 50 || gap >= 20);
      if (!should) return;
    }
    _fetching = true;
    _lastRouteOrigin = me;
    _lastRouteAt = DateTime.now();
    try {
      final best = await _bestRoute(me, dest);
      if (best == null) {
        await _drawFallback(me, dest);
        return;
      }

      final decoded = _decodePolyline(best['geometry'] as String);
      if (decoded.length < 2) return;
      // router snaps to the road; start the line at the user so it is connected
      final pts = <LatLng>[me, ...decoded];

      await _drawRoute(pts, '#4285F4');

      final steps = <_Step>[];
      final legs = best['legs'];
      if (legs is List && legs.isNotEmpty && legs.first is Map) {
        final ss = (legs.first as Map)['steps'];
        if (ss is List) {
          for (final s in ss) {
            if (s is! Map) continue;
            final m = s['maneuver'];
            if (m is! Map) continue;
            final loc = m['location'];
            if (loc is! List || loc.length < 2) continue;
            steps.add(_Step(
              LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
              '${m['type'] ?? ''}',
              '${m['modifier'] ?? ''}',
              '${s['name'] ?? ''}',
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _routeMeters = (best['distance'] as num?)?.toDouble();
        _routeSecs = _routeMeters == null ? null : (_routeMeters! / 6.5).round(); // ~23 km/h
        _routePts = pts;
        _steps = steps;
        _stepVertex = _mapStepsToVertices(steps, pts);
        _meSeg = 0;
        _lastTrimPos = me;
        _stepIdx = steps.length > 1 ? 1 : 0; // 0 = depart
      });
      if (!_fitted) {
        _fitted = true;
        _fitBoth();
        // after a short overview, switch to follow mode
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _follow) _followCamera();
        });
      }
    } catch (e) {
      debugPrint('delivery route error: ${e is DioException ? e.response?.data : e}');
      if (_routeLine == null) await _drawFallback(me, dest);
    } finally {
      _fetching = false;
    }
  }

  /// Asks 3 routing servers and keeps the best road for a delivery bike:
  /// fastest car-road route, unless the bike-profile route is clearly
  /// shorter (>10%). When moving, the travel direction is sent so the route
  /// never starts by sending the rider backwards.
  Future<Map?> _bestRoute(LatLng me, LatLng dest) async {
    final coords =
        '${me.longitude},${me.latitude};${dest.longitude},${dest.latitude}';

    Future<List<Map>> ask(String base, bool withBearing) async {
      try {
        final res = await _dio.get<dynamic>(
          '$base/route/v1/driving/$coords',
          queryParameters: {
            'overview': 'full',
            'geometries': 'polyline',
            'steps': 'true',
            'alternatives': 'true',
            if (withBearing) 'bearings': '${_gpsCourse.round()},90;',
          },
          options: Options(
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        final r = res.data is Map ? (res.data as Map)['routes'] : null;
        if (r is List) return r.whereType<Map>().toList();
      } catch (_) {}
      return <Map>[];
    }

    Future<List<List<Map>>> askAll(bool withBearing) => Future.wait([
          ask('https://routing.openstreetmap.de/routed-car', withBearing),
          ask('https://router.project-osrm.org', withBearing),
          ask('https://routing.openstreetmap.de/routed-bike', withBearing),
        ]);

    final moving = _gpsSpeed >= 1.5;
    var all = await askAll(moving);
    if (moving && all.every((l) => l.isEmpty)) all = await askAll(false);

    double num_(Map r, String k) => ((r[k] as num?) ?? double.infinity).toDouble();

    Map? bestCar;
    for (final r in [...all[0], ...all[1]]) {
      if (bestCar == null || num_(r, 'duration') < num_(bestCar, 'duration')) {
        bestCar = r;
      }
    }
    Map? bestBike;
    for (final r in all[2]) {
      if (bestBike == null || num_(r, 'distance') < num_(bestBike, 'distance')) {
        bestBike = r;
      }
    }
    if (bestBike != null &&
        (bestCar == null ||
            num_(bestBike, 'distance') < num_(bestCar, 'distance') * 0.9)) {
      return bestBike;
    }
    return bestCar ?? bestBike;
  }

  bool _trimming = false;
  LatLng? _lastTrimPos;

  /// Erase the part of the line already driven (like Google): draw only
  /// user -> destination. Refreshed every ~10 m.
  Future<void> _trimRoute(LatLng me) async {
    if (_routePts.length < 3 || _map == null || !_styleReady) return;
    if (_routeLine == null || _fetching || _trimming) return;
    final last = _lastTrimPos;
    if (last != null && _hav(last, me) < 10) return;
    _trimming = true;
    _lastTrimPos = me;
    try {
      final from = (_meSeg + 1).clamp(1, _routePts.length - 1);
      final ahead = <LatLng>[me, ..._routePts.sublist(from)];
      if (ahead.length >= 2) await _drawRoute(ahead, '#4285F4');
    } catch (_) {
    } finally {
      _trimming = false;
    }
  }

  /// Google-style route: white casing under a blue line. Old lines removed after.
  Future<void> _drawRoute(List<LatLng> pts, String color) async {
    final c = _map;
    if (c == null) return;
    final oldMain = _routeLine, oldCase = _casingLine;
    _casingLine = await c.addLine(LineOptions(
      geometry: pts,
      lineColor: '#FFFFFF',
      lineWidth: 10.0,
      lineOpacity: 1.0,
    ));
    _routeLine = await c.addLine(LineOptions(
      geometry: pts,
      lineColor: color,
      lineWidth: 6.5,
      lineOpacity: 1.0,
    ));
    if (oldCase != null) await c.removeLine(oldCase);
    if (oldMain != null) await c.removeLine(oldMain);
  }

  /// Router down -> straight grey line to the target so the boy still sees direction.
  Future<void> _drawFallback(LatLng me, LatLng dest) async {
    try {
      await _drawRoute([me, dest], '#9AA0A6');
      if (mounted && _routeMeters == null) {
        setState(() => _routeMeters = _distToDest());
      }
    } catch (_) {}
  }

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

  // ---- geometry helpers (all in metres) ----
  static double _hav(LatLng a, LatLng b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180, p2 = b.latitude * math.pi / 180;
    final dp = p2 - p1;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.pow(math.sin(dp / 2), 2) +
        math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// Distance from [p] to segment a-b (local flat projection, fine for < few km).
  static double _segDist(LatLng p, LatLng a, LatLng b) {
    final kx = math.cos(p.latitude * math.pi / 180) * 111320.0;
    const ky = 110574.0;
    final ax = (a.longitude - p.longitude) * kx, ay = (a.latitude - p.latitude) * ky;
    final bx = (b.longitude - p.longitude) * kx, by = (b.latitude - p.latitude) * ky;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2);
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }

  /// (distance to the route, index of the nearest segment). Searches around
  /// the last known segment first, so it follows the user along the road.
  (double, int) _routeDist(LatLng me) {
    final n = _routePts.length;
    if (n < 2) return (double.infinity, 0);
    var best = double.infinity, bestI = 0;
    final from = math.max(0, _meSeg - 5);
    final to = math.min(n - 1, _meSeg + 60);
    for (var i = from; i < to; i++) {
      final d = _segDist(me, _routePts[i], _routePts[i + 1]);
      if (d < best) {
        best = d;
        bestI = i;
      }
    }
    // not found nearby (jumped / re-routed) -> scan the whole route
    if (best > 60) {
      for (var i = 0; i < n - 1; i++) {
        final d = _segDist(me, _routePts[i], _routePts[i + 1]);
        if (d < best) {
          best = d;
          bestI = i;
        }
      }
    }
    return (best, bestI);
  }

  /// Polyline vertex index for every maneuver (searched forward only).
  List<int> _mapStepsToVertices(List<_Step> steps, List<LatLng> pts) {
    final out = <int>[];
    var from = 0;
    for (final st in steps) {
      var best = double.infinity, bi = from;
      for (var i = from; i < pts.length; i++) {
        final d = _hav(st.at, pts[i]);
        if (d < best) {
          best = d;
          bi = i;
        }
        // vertices are ordered: once clearly past the best one, stop
        if (best < 3 && d > best + 40) break;
      }
      out.add(bi);
      from = bi;
    }
    return out;
  }

  /// Metres ALONG THE ROAD from the user to the next maneuver
  /// (not a straight line, so the number matches what the user will drive).
  double _metersToStep() {
    final me = _me;
    if (me == null || _routePts.length < 2 || _stepVertex.isEmpty) {
      final s = _steps.isEmpty ? null : _steps[_stepIdx.clamp(0, _steps.length - 1)];
      return (me == null || s == null) ? 0 : _hav(me, s.at);
    }
    final v = _stepVertex[_stepIdx.clamp(0, _stepVertex.length - 1)];
    final i = _meSeg.clamp(0, _routePts.length - 2);
    if (v <= i) return _hav(me, _routePts[v.clamp(0, _routePts.length - 1)]);
    var m = _hav(me, _routePts[i + 1]);
    for (var k = i + 1; k < v; k++) {
      m += _hav(_routePts[k], _routePts[k + 1]);
    }
    return m;
  }

  /// Move to the next maneuver once the user has passed the current one.
  void _advanceStep(LatLng me) {
    if (_routePts.length < 2) return;
    _meSeg = _routeDist(me).$2;
    while (_stepIdx < _steps.length - 1 && _stepIdx < _stepVertex.length) {
      final v = _stepVertex[_stepIdx];
      final passed = _meSeg >= v; // already beyond the maneuver point
      final close = _hav(me, _steps[_stepIdx].at) < 15;
      if (passed || close) {
        _stepIdx++;
      } else {
        break;
      }
    }
  }

  // ───────────────────────── map overlays ─────────────────────────

  Future<void> _onStyleLoaded() async {
    final c = _map, d = _dest;
    if (c == null || d == null) return;
    await c.addCircle(CircleOptions(
      geometry: d,
      circleRadius: 10,
      circleColor: '#E53935',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3,
    ));
    await c.addSymbol(SymbolOptions(
      geometry: d,
      textField: _o.retailerName,
      textSize: 12.0,
      textOffset: const Offset(0, 1.8),
    ));
    _styleReady = true;
    if (_me != null) _maybeFetchRoute(_me!);
  }

  // ───────────────────────── addresses ─────────────────────────

  /// Reverse-geocode "my address" at most every 60 s or 150 m.
  Future<void> _maybeGeocode(LatLng me) async {
    if (_geocoding) return;
    if (_lastGeocoded != null && _lastGeocodedAt != null) {
      final moved = Geolocator.distanceBetween(_lastGeocoded!.latitude,
          _lastGeocoded!.longitude, me.latitude, me.longitude);
      if (moved < 150 &&
          DateTime.now().difference(_lastGeocodedAt!) <
              const Duration(seconds: 60)) {
        return;
      }
    }
    _geocoding = true;
    _lastGeocoded = me;
    _lastGeocodedAt = DateTime.now();
    try {
      final list =
          await Geocoding().placemarkFromCoordinates(me.latitude, me.longitude);
      if (list.isNotEmpty && mounted) {
        final m = list.first;
        final parts = <String?>[
          m.street,
          m.subLocality,
          m.locality,
          m.administrativeArea,
        ].where((s) => s != null && s.trim().isNotEmpty).cast<String>().toList();
        if (parts.isNotEmpty) setState(() => _fromAddress = parts.join(', '));
      }
    } catch (_) {
      if (mounted && _fromAddress.startsWith('Finding')) {
        setState(() => _fromAddress =
            '${me.latitude.toStringAsFixed(5)}, ${me.longitude.toStringAsFixed(5)}');
      }
    } finally {
      _geocoding = false;
    }
  }

  // ───────────────────────── deliver ─────────────────────────

  Future<void> _markDelivered() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mark as delivered?'),
        content: Text('Order #${_o.orderNumber} to ${_o.retailerName}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yes, delivered')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _delivering = true);
    try {
      final r = await TestService.markDelivered(
        widget.token,
        _o.assignmentId,
        lat: _me?.latitude,
        lng: _me?.longitude,
        distanceM: _travelled,
      );
      if (!mounted) return;
      _posSub?.cancel();
      _pingTimer?.cancel();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.check_circle, color: AppColors.green),
            SizedBox(width: 8),
            Text('Delivered'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order #${_o.orderNumber}'),
              const SizedBox(height: 8),
              Text('Distance travelled: ${fmtDistanceM(r.distanceM)}'),
              Text('Time taken: ${fmtDurationS(r.durationS)}'),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _delivering = false);
        testToast(context, testErr(e), error: true);
      }
    }
  }

  // ───────────────────────── UI (Google Maps style) ─────────────────────────

  static const Color _gGreen = Color(0xFF0B8043); // nav banner
  static const Color _gBlue = Color(0xFF1A73E8);
  static const Color _gEta = Color(0xFF188038);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SafeArea(child: _errorView())
              : _mapView(),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back')),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _init();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _mapView() {
    final dest = _dest!;
    return Stack(
      children: [
        MapplsMap(
          initialCameraPosition:
              CameraPosition(target: _me ?? dest, zoom: 15.0),
          onMapCreated: (c) => _map = c,
          onStyleLoadedCallback: _onStyleLoaded,
          myLocationEnabled: true,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          compassEnabled: false, // native compass sat on the notch; we have our own
        ),

        // top: green turn banner (or "arrived")
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              // Top turn banner disabled (commented out):
              // child: _arrived
              //     ? _arrivedBanner()
              //     : (_steps.isNotEmpty ? _turnBanner() : _headingBanner()),
              child: _arrived ? _arrivedBanner() : const SizedBox.shrink(),
            ),
          ),
        ),

        // right: small compass
        Positioned(
          right: 12,
          top: MediaQuery.of(context).padding.top + (_arrived ? 100 : 12),
          child: _compassWidget(),
        ),

        // bottom: floating buttons + sheet
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!_follow)
                      Material(
                        color: Colors.white,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _recenter,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.navigation, size: 18, color: _gBlue),
                                SizedBox(width: 6),
                                Text('Re-center',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _gBlue)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Column(
                      children: [
                        _roundBtn(Icons.route_outlined, 'Route overview',
                            _overview),
                        const SizedBox(height: 10),
                        _roundBtn(Icons.my_location, 'My location', _recenter,
                            active: _follow),
                      ],
                    ),
                  ],
                ),
              ),
              _bottomSheet(),
            ],
          ),
        ),
      ],
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
              padding: const EdgeInsets.all(12),
              child: Icon(icon, size: 22, color: active ? _gBlue : Colors.black87),
            ),
          ),
        ),
      );

  // ---- banners ----
  Widget _bannerShell(Widget child, {Color color = _gGreen}) => Material(
        color: color,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: child,
        ),
      );

  // ignore: unused_element
  Widget _turnBanner() {
    final s = _steps[_stepIdx.clamp(0, _steps.length - 1)];
    final d = _metersToStep();
    return _bannerShell(Row(
      children: [
        Icon(_turnIcon(s), color: Colors.white, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fmtDistanceM(d),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.1)),
              const SizedBox(height: 2),
              Text(_turnText(s),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      ],
    ));
  }

  /// Before the route loads: still show where we are going.
  // ignore: unused_element
  Widget _headingBanner() => _bannerShell(Row(
        children: [
          const Icon(Icons.navigation, color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Head to ${_o.retailerName}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ));

  Widget _arrivedBanner() => _bannerShell(
        const Row(
          children: [
            Icon(Icons.flag, color: Colors.white, size: 40),
            SizedBox(width: 14),
            Expanded(
              child: Text('You have arrived',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  String _turnText(_Step s) {
    final road = s.road.isEmpty ? '' : ' onto ${s.road}';
    final dir = s.modifier;
    switch (s.type) {
      case 'arrive':
        return 'Arrive at destination';
      case 'roundabout':
      case 'rotary':
        return 'Take the roundabout$road';
      case 'fork':
        return 'Keep ${dir.contains('left') ? 'left' : 'right'}$road';
      case 'end of road':
        return 'Turn ${dir.isEmpty ? 'ahead' : dir}$road';
      case 'turn':
      case 'on ramp':
      case 'off ramp':
        return 'Turn ${dir.isEmpty ? 'ahead' : dir}$road';
      case 'depart':
        return 'Head out$road';
      default:
        return dir == 'uturn'
            ? 'Make a U-turn$road'
            : 'Continue ${dir.isEmpty ? 'straight' : dir}$road';
    }
  }

  IconData _turnIcon(_Step s) {
    if (s.type == 'arrive') return Icons.flag;
    if (s.type == 'roundabout' || s.type == 'rotary') return Icons.roundabout_left;
    switch (s.modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

  // ---- compass: small round, Google-style ----
  /// Red tip = North. Tap: heading-up <-> north-up.
  Widget _compassWidget() {
    final northAngle = -_heading * math.pi / 180;
    return Material(
      color: Colors.white,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          setState(() => _northUp = !_northUp);
          _followCamera();
        },
        child: SizedBox(
          width: 46,
          height: 46,
          child: Transform.rotate(
            angle: northAngle,
            child: const Icon(Icons.navigation, size: 28, color: Color(0xFFE53935)),
          ),
        ),
      ),
    );
  }

  // ---- bottom sheet (ETA / destination / details) ----
  String _arrivalClock(int secs) {
    final t = DateTime.now().add(Duration(seconds: secs));
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }

  Future<void> _callRetailer() async {
    if (_o.retailerMobile.isEmpty) return;
    try {
      await launchUrl(Uri.parse('tel:${_o.retailerMobile}'));
    } catch (_) {}
  }

  /// Opens the target address in Google Maps (turn-by-turn). Falls back to the
  /// web directions link, which Android hands to the Google Maps app too.
  Future<void> _openGoogleMaps() async {
    final d = _dest;
    if (d == null) return;
    final ll = '${d.latitude},${d.longitude}';
    final tries = <Uri>[
      Uri.parse('google.navigation:q=$ll&mode=d'),
      Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$ll&travelmode=driving'),
    ];
    for (final u in tries) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (mounted) testToast(context, 'Could not open Google Maps.', error: true);
  }

  Widget _openMapButton({required bool primary}) => SizedBox(
        width: double.infinity,
        child: primary
            ? ElevatedButton.icon(
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open Map', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
              )
            : OutlinedButton.icon(
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open Map', style: TextStyle(fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gBlue,
                  side: const BorderSide(color: _gBlue),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
              ),
      );

  Widget _bottomSheet() {
    final toDest = _distToDest();
    final left = _routeMeters ?? (toDest.isFinite ? toDest : null);
    final arrived = _arrived;

    return Material(
      color: Colors.white,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // drag handle (tap = expand)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _sheetOpen = !_sheetOpen),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),

              // ETA line:  12 min  (4.2 km) · 10:42 am
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _sheetOpen = !_sheetOpen),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                              arrived
                                  ? 'Arrived'
                                  : (_routeSecs == null
                                      ? '--'
                                      : fmtDurationS(_routeSecs! < 60 ? 60 : _routeSecs!)),
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  color: _gEta)),
                          Text(left == null ? '' : '(${fmtDistanceM(left)})',
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.black54)),
                          if (_routeSecs != null && !arrived)
                            Text('· ${_arrivalClock(_routeSecs!)}',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Exit navigation',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F3F4)),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // destination (always visible)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, size: 20, color: Color(0xFFD93025)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_o.retailerName.isEmpty ? 'Destination' : _o.retailerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(_o.address.isEmpty ? '-' : _o.address,
                            maxLines: _sheetOpen ? 4 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black54)),
                      ],
                    ),
                  ),
                  if (_o.retailerMobile.isNotEmpty)
                    IconButton(
                      tooltip: 'Call retailer',
                      onPressed: _callRetailer,
                      icon: const Icon(Icons.call, color: _gBlue),
                    ),
                ],
              ),

              // expanded details
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _sheetOpen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.my_location,
                                  size: 20, color: _gBlue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Your location',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.black54)),
                                    Text(_fromAddress,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _stat('Travelled', fmtDistanceM(_travelled)),
                              _stat('Time', _clockText(_elapsedS)),
                              _stat('To go', toDest.isFinite ? fmtDistanceM(toDest) : '--'),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),

              const SizedBox(height: 10),
              if (arrived) ...[
                // arrived: Mark Delivered on top, Open Map below
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _delivering ? null : _markDelivered,
                    icon: _delivering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle),
                    label: const Text('Mark Delivered',
                        style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gEta,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _openMapButton(primary: false),
              ] else ...[
                // on the way: only Open Map (Google Maps) until arrival
                _openMapButton(primary: true),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    toDest.isFinite
                        ? 'Mark Delivered unlocks within ${kArriveRadiusM.round()} m of the address.'
                        : 'Locating...',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ),
              ],
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
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ],
        ),
      );

  String _clockText(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }
}