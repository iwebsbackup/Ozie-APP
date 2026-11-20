import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';

import '../../core/config.dart';
import '../../widgets/app_widgets.dart';
import 'salesman_models.dart';

/// In-app Mappls (MapmyIndia) map: shop pin + salesman live location
/// + live straight-line distance to the shop.
class SalesmanMapplsNavScreen extends StatefulWidget {
  final SalesmanAddress target;

  const SalesmanMapplsNavScreen({super.key, required this.target});

  @override
  State<SalesmanMapplsNavScreen> createState() =>
      _SalesmanMapplsNavScreenState();
}

class _SalesmanMapplsNavScreenState extends State<SalesmanMapplsNavScreen> {
  MapplsMapController? _map;
  StreamSubscription<Position>? _sub;

  LatLng? _me;
  bool _loading = true;
  String? _error;
  String _distance = 'Calculating...';
  String _eta = '--';

  final Dio _dio = Dio();
  Line? _routeLine;
  bool _styleReady = false;
  bool _fetching = false;
  bool _fitted = false;
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteAt;

  LatLng get _dest => LatLng(widget.target.latitude, widget.target.longitude);

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
      _onPosition(LatLng(p.latitude, p.longitude));
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
    final m = Geolocator.distanceBetween(
        me.latitude, me.longitude, _dest.latitude, _dest.longitude);
    setState(() {
      _me = me;
      _loading = false;
      _error = null;
      _distance =
          m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
    });
    _maybeFetchRoute(me);
  }

  /// Road route line + road distance + ETA.
  /// Refetch only after 50 m moved or 20 s (saves quota).
  Future<void> _maybeFetchRoute(LatLng me) async {
    if (!_styleReady || _map == null || _fetching) return;
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
      // Keyless road routing (OSRM). Mappls map + license files are used for
      // the map only; Mappls route REST needs a key which this app doesn't have.
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${me.longitude},${me.latitude};${_dest.longitude},${_dest.latitude}';
      final res = await _dio.get<dynamic>(url, queryParameters: {
        'overview': 'full',
        'geometries': 'polyline',
      });
      final data = res.data;
      final routes = data is Map ? data['routes'] : null;
      if (routes is! List || routes.isEmpty) {
        debugPrint('Mappls route: empty/bad response: $data');
        return;
      }
      final route = routes.first as Map;
      final pts = _decodePolyline(route['geometry'] as String);
      if (pts.length < 2) return;

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
      if (!_fitted) {
        _fitted = true;
        _fitBoth();
      }
    } catch (e) {
      debugPrint('Mappls route error: ${e is DioException ? e.response?.data : e}');
    } finally {
      _fetching = false;
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

  /// Runs once the map style is ready (overlays need a loaded style).
  Future<void> _addShopPin() async {
    final c = _map;
    if (c == null) return;
    await c.addCircle(CircleOptions(
      geometry: _dest,
      circleRadius: 9,
      circleColor: '#E53935',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3,
    ));
    await c.addSymbol(SymbolOptions(
      geometry: _dest,
      textField: widget.target.shopName,
      textSize: 12.0,
      textOffset: const Offset(0, 1.6),
    ));
    _styleReady = true;
    if (_me != null) _maybeFetchRoute(_me!);
  }

  void _fitBoth() {
    final me = _me;
    if (me == null || _map == null) return;
    final sw = LatLng(
      me.latitude < _dest.latitude ? me.latitude : _dest.latitude,
      me.longitude < _dest.longitude ? me.longitude : _dest.longitude,
    );
    final ne = LatLng(
      me.latitude > _dest.latitude ? me.latitude : _dest.latitude,
      me.longitude > _dest.longitude ? me.longitude : _dest.longitude,
    );
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: sw, northeast: ne),
      left: 80,
      right: 80,
      top: 160,
      bottom: 80,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.target.shopName.isEmpty
        ? 'Retailer #${widget.target.retailerId}'
        : widget.target.shopName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Show me + shop',
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _fitBoth,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : Stack(
                  children: [
                    MapplsMap(
                      initialCameraPosition: CameraPosition(
                        target: _me ?? _dest,
                        zoom: 15.0,
                      ),
                      onMapCreated: (c) => _map = c,
                      onStyleLoadedCallback: _addShopPin,
                      myLocationEnabled: true,
                      myLocationTrackingMode: MyLocationTrackingMode.tracking,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on,
                                  color: AppColors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.target.displayAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.text),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Distance',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                  Text(_distance,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  Text('ETA $_eta',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}