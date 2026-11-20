import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';

import '../../widgets/app_widgets.dart';
import 'test_widgets.dart';

/// Result of the map picker: coordinates + readable address.
class PickedLocation {
  final double lat;
  final double lng;
  final String address;
  const PickedLocation(this.lat, this.lng, this.address);
}

/// Mappls map: TAP the delivery spot -> red pin drops exactly there ->
/// Confirm -> returns [PickedLocation] (lat/lng of the tapped point + address).
/// (Does not read the camera centre, so it can never fall back to "my location".)
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const LocationPickerScreen({super.key, this.initial});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const LatLng _fallback = LatLng(28.6139, 77.2090);

  MapplsMapController? _map;
  LatLng? _start;
  LatLng? _center; // the chosen point (tapped, or initial)
  bool _touched = false; // user actually chose a point
  Circle? _pinCircle;
  bool _styleReady = false;
  String _address = 'Tap on the map to choose the delivery spot';
  bool _resolving = false;
  bool _confirming = false;
  int _gen = 0; // drops stale reverse-geocode results

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    LatLng? s = widget.initial;
    s ??= await _gps();
    if (!mounted) return;
    setState(() {
      _start = s ?? _fallback;
      _center = _start;
      _touched = widget.initial != null;
    });
    if (_touched) _resolve(_start!);
  }

  /// Red dot with white ring at the chosen point (old one removed).
  Future<void> _drawPin(LatLng p) async {
    final c = _map;
    if (c == null || !_styleReady) return;
    final old = _pinCircle;
    _pinCircle = await c.addCircle(CircleOptions(
      geometry: p,
      circleRadius: 10,
      circleColor: '#E53935',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3,
    ));
    if (old != null) await c.removeCircle(old);
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    if (_touched && _center != null) _drawPin(_center!);
  }

  /// Tap = choose this exact point.
  void _onTap(LatLng p) {
    setState(() {
      _center = p;
      _touched = true;
    });
    _drawPin(p);
    _resolve(p);
  }

  Future<LatLng?> _gps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<String> _addressFor(LatLng p) async {
    try {
      final list =
          await Geocoding().placemarkFromCoordinates(p.latitude, p.longitude);
      if (list.isNotEmpty) {
        final m = list.first;
        final parts = <String?>[
          m.street,
          m.subLocality,
          m.locality,
          m.administrativeArea,
          m.postalCode,
        ].where((s) => s != null && s.trim().isNotEmpty).cast<String>().toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}
    return 'Location (${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)})';
  }

  Future<void> _resolve(LatLng p) async {
    final g = ++_gen;
    setState(() => _resolving = true);
    final a = await _addressFor(p);
    if (!mounted || g != _gen) return;
    setState(() {
      _address = a;
      _resolving = false;
    });
  }

  Future<void> _goToMe() async {
    final me = await _gps();
    if (me == null) {
      if (mounted) testToast(context, 'Could not get your location.', error: true);
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngZoom(me, 17.0));
    _onTap(me);
  }

  void _confirm() {
    final c = _center;
    if (c == null || !_touched) return;
    setState(() => _confirming = true);
    Navigator.of(context).pop(PickedLocation(c.latitude, c.longitude, _address));
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick delivery location'),
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
      ),
      body: start == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                MapplsMap(
                  initialCameraPosition:
                      CameraPosition(target: start, zoom: 16.0),
                  onMapCreated: (c) => _map = c,
                  onStyleLoadedCallback: _onStyleLoaded,
                  onMapClick: (point, latLng) => _onTap(latLng),
                  myLocationEnabled: true,
                  myLocationTrackingMode: MyLocationTrackingMode.none,
                ),
                Positioned(
                  right: 12,
                  bottom: 200,
                  child: FloatingActionButton.small(
                    heroTag: 'pick_me',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.blue,
                    onPressed: _goToMe,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 12,
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SELECTED LOCATION',
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.8,
                                  color: AppColors.muted)),
                          const SizedBox(height: 4),
                          Text(!_touched ? _address : (_resolving ? 'Finding address...' : _address),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.text)),
                          if (_touched && _center != null) ...[
                            const SizedBox(height: 4),
                            Text(
                                '${_center!.latitude.toStringAsFixed(6)}, ${_center!.longitude.toStringAsFixed(6)}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  (!_touched || _resolving || _confirming) ? null : _confirm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Confirm location'),
                            ),
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
