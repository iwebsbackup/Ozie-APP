import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mappls_gl/mappls_gl.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import '../salesman/salesman_models.dart';
import 'distributor_models.dart';
import 'distributor_service.dart';
import 'salesman_tracking_screen.dart' show statusColor, statusLabel;

/// One salesman's tracking (same features as web view-reports):
/// date presets, Live Track, Route, Visits, Assigned Route, Map only,
/// View Salesman. All controls live in the box under the map.
class SalesmanTrackMapScreen extends StatefulWidget {
  final SalesmanLive salesman;
  const SalesmanTrackMapScreen({super.key, required this.salesman});

  @override
  State<SalesmanTrackMapScreen> createState() => _SalesmanTrackMapScreenState();
}

class _SalesmanTrackMapScreenState extends State<SalesmanTrackMapScreen> {
  // ---- scooty marker -------------------------------------------------
  static const String _scootyAsset = 'assets/icons/deliveryscotty-top-view.png';
  static const String _scootyId = 'scooty';
  static const double _bitmapPx = 128; // longest side of the marker bitmap
  /// MARKER SIZE KNOB: 1.0 = normal, 1.5 = bigger, 0.7 = smaller.
  static const double _scootyScale = 1.0;
  bool _scootyOk = false;

  // ---- map -----------------------------------------------------------
  MapplsMapController? _map;
  bool _styleReady = false;
  final Dio _dio = Dio();
  final List<Line> _lines = [];
  final List<Circle> _circles = [];
  final List<Symbol> _symbols = [];

  // ---- data ----------------------------------------------------------
  DateTime _day = DateTime.now();
  DayTrack? _track;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  SalesmanLive? _live; // refreshed for today
  SalesmanLive get _sm => _live ?? widget.salesman;

  // ---- options (checkboxes) ------------------------------------------
  bool _optRoute = true;
  bool _optVisits = true;
  bool _optLive = false;
  bool _optAssigned = false;
  bool _mapOnly = false;

  // assigned route
  List<SalesmanAddress>? _assigned;
  List<LatLng> _plannedPts = [];
  bool _assignedLoading = false;

  bool get _isToday => _sameDay(_day, DateTime.now());
  bool get _liveAvailable => _isToday && _sm.isOnline && _sm.hasPosition;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isToday) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dio.close();
    super.dispose();
  }

  // =====================================================================
  // loading
  // =====================================================================
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final t = await DistributorService.getDayTrack(_sm.userId, _day);
      if (_isToday) {
        try {
          final l = await DistributorService.getSalesmen();
          for (final x in l.salesmen) {
            if (x.userId == _sm.userId) _live = x;
          }
        } catch (_) {/* keep old position */}
      }
      if (!mounted) return;
      if (_optLive && !_liveAvailable) _optLive = false;
      setState(() {
        _track = t;
        _loading = false;
        _error = null;
      });
      await _draw(fit: !silent && !_optLive);
      if (_optLive && _liveAvailable) _followLive();
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadAssigned() async {
    if (_assigned != null) return;
    setState(() => _assignedLoading = true);
    try {
      final list = await DistributorService.getAssignedAddresses(_sm.id);
      _assigned = list.where((a) => a.hasLocation).toList();
      _plannedPts = await _planRoute(_assigned!);
    } on ApiException catch (e) {
      _snack(e.message);
      _optAssigned = false;
    } catch (_) {
      _snack('Could not load assigned route.');
      _optAssigned = false;
    }
    if (mounted) setState(() => _assignedLoading = false);
  }

  // =====================================================================
  // scooty marker
  // =====================================================================
  /// Loads the scooty png (nose UP = north), crops its transparent padding so
  /// the vehicle fills the bitmap, and registers it as a map image.
  Future<void> _registerScooty() async {
    final c = _map;
    if (c == null) return;
    try {
      final data = await rootBundle.load(_scootyAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final src = (await codec.getNextFrame()).image;

      // bounding box of visible pixels
      var minX = src.width, minY = src.height, maxX = 0, maxY = 0;
      final bd = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd != null) {
        final w = src.width, h = src.height;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            if (bd.getUint8((y * w + x) * 4 + 3) > 16) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
      }
      if (maxX <= minX || maxY <= minY) {
        minX = 0;
        minY = 0;
        maxX = src.width - 1;
        maxY = src.height - 1;
      }
      final cw = (maxX - minX + 1).toDouble();
      final ch = (maxY - minY + 1).toDouble();
      final k = _bitmapPx / (cw > ch ? cw : ch);
      final ow = (cw * k).round().clamp(8, 512);
      final oh = (ch * k).round().clamp(8, 512);

      final rec = ui.PictureRecorder();
      final cv = Canvas(rec, Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()));
      cv.drawImageRect(
        src,
        Rect.fromLTWH(minX.toDouble(), minY.toDouble(), cw, ch),
        Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final img = await rec.endRecording().toImage(ow, oh);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw Exception('png encode failed');
      await c.addImage(_scootyId, png.buffer.asUint8List());
      _scootyOk = true;
    } catch (e) {
      debugPrint('scooty image load failed: $e');
      _scootyOk = false; // falls back to a purple dot
    }
  }

  double _bearing(LatLng a, LatLng b) {
    final p1 = a.latitude * math.pi / 180, p2 = b.latitude * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Phone compass heading if present, else bearing of the last route step.
  double _riderHeading(DayTrack t) {
    if (_sm.heading != null) return _sm.heading!;
    if (t.segments.isNotEmpty) {
      final seg = t.segments.last;
      if (seg.length >= 2) return _bearing(seg[seg.length - 2], seg.last);
    }
    return 0;
  }

  Future<void> _addScooty(LatLng p, double heading) async {
    final c = _map!;
    if (!_scootyOk) {
      await _pin(p, '#7C3AED', label: _sm.name, r: 10);
      return;
    }
    _symbols.add(await c.addSymbol(SymbolOptions(
      geometry: p,
      iconImage: _scootyId,
      iconSize: _scootyScale,
      iconRotate: heading,
      textField: _sm.name,
      textSize: 11.0,
      textOffset: const Offset(0, 3.6),
    )));
  }

  // =====================================================================
  // drawing
  // =====================================================================
  Future<void> _clearOverlays() async {
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

  Future<void> _pin(LatLng p, String color,
      {String? label, double r = 8}) async {
    final c = _map!;
    _circles.add(await c.addCircle(CircleOptions(
      geometry: p,
      circleRadius: r,
      circleColor: color,
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3,
    )));
    if (label != null && label.isNotEmpty) {
      _symbols.add(await c.addSymbol(SymbolOptions(
        geometry: p,
        textField: label,
        textSize: 11.0,
        textOffset: const Offset(0, 1.6),
      )));
    }
  }

  bool _drawing = false;
  bool _redraw = false;

  Future<void> _draw({bool fit = true}) async {
    // never run two draws at once (overlapping removes/adds corrupt the list)
    if (_drawing) {
      _redraw = true;
      return;
    }
    _drawing = true;
    try {
      do {
        _redraw = false;
        await _drawOnce(fit: fit);
      } while (_redraw);
    } finally {
      _drawing = false;
    }
  }

  Future<void> _drawOnce({required bool fit}) async {
    final c = _map;
    final t = _track;
    if (c == null || !_styleReady || t == null) return;
    await _clearOverlays();

    final all = <LatLng>[];

    // travelled route
    if (_optRoute) {
      for (final seg in t.segments) {
        _lines.add(await c.addLine(LineOptions(
          geometry: seg,
          lineColor: '#1A6FD4',
          lineWidth: 5.0,
          lineOpacity: 0.9,
        )));
        all.addAll(seg);
      }
      if (t.segments.isNotEmpty) {
        await _pin(t.segments.first.first, '#1CB87A', label: 'Start');
        if (!_isToday || !_sm.hasPosition) {
          await _pin(t.segments.last.last, '#E53935', label: 'End');
        }
      }
    }

    // visits
    if (_optVisits) {
      for (final v in t.visits) {
        if (v.hasPin) {
          final p = LatLng(v.lat!, v.lng!);
          await _pin(p, '#F59E0B', label: v.shop, r: 7);
          all.add(p);
        }
      }
    }

    // assigned route (planned)
    if (_optAssigned && _assigned != null) {
      if (_plannedPts.length > 1) {
        _lines.add(await c.addLine(LineOptions(
          geometry: _plannedPts,
          lineColor: '#7C3AED',
          lineWidth: 4.0,
          lineOpacity: 0.75,
        )));
      }
      for (final a in _assigned!) {
        final p = LatLng(a.latitude, a.longitude);
        await _pin(p, '#0EA5A4', label: a.shopName, r: 6);
        all.add(p);
      }
    }

    // scooty = live position (today only)
    if (_isToday && _sm.hasPosition && _sm.isOnline) {
      final p = LatLng(_sm.lat!, _sm.lng!);
      await _addScooty(p, _riderHeading(t));
      all.add(p);
    }

    if (fit && all.isNotEmpty) await _fit(all);
  }

  Future<void> _fit(List<LatLng> pts) async {
    final c = _map;
    if (c == null || pts.isEmpty) return;
    var minLat = pts.first.latitude, maxLat = minLat;
    var minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if (minLat == maxLat && minLng == maxLng) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 16));
      return;
    }
    await c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      left: 50,
      right: 50,
      top: 60,
      bottom: 50,
    ));
  }

  // =====================================================================
  // actions
  // =====================================================================
  void _followLive() {
    if (_map == null || !_sm.hasPosition) return;
    _map!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_sm.lat!, _sm.lng!), 17));
  }

  void _viewSalesman() {
    if (!_sm.hasPosition) {
      _snack('No location for this salesman yet.');
      return;
    }
    _followLive();
  }

  Future<void> _fitAll() async {
    final t = _track;
    if (t == null) return;
    final pts = <LatLng>[for (final s in t.segments) ...s];
    if (_isToday && _sm.hasPosition) pts.add(LatLng(_sm.lat!, _sm.lng!));
    if (_optAssigned && _assigned != null) {
      pts.addAll(_assigned!.map((a) => LatLng(a.latitude, a.longitude)));
    }
    await _fit(pts);
  }

  void _setDay(DateTime d) {
    if (d.isAfter(DateTime.now())) return;
    setState(() {
      _day = d;
      if (!_isToday) _optLive = false;
    });
    _load();
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (d != null) _setDay(d);
  }

  Future<void> _toggleAssigned(bool on) async {
    setState(() => _optAssigned = on);
    if (on) await _loadAssigned();
    await _draw(fit: on);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // =====================================================================
  // planned route (OSRM, keyless): salesman -> nearest-neighbour stops
  // =====================================================================
  double _km(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  Future<List<LatLng>> _planRoute(List<SalesmanAddress> stops) async {
    if (stops.isEmpty) return [];
    final left = stops.map((a) => LatLng(a.latitude, a.longitude)).toList();
    LatLng cur = _sm.hasPosition ? LatLng(_sm.lat!, _sm.lng!) : left.first;
    final ordered = <LatLng>[cur];
    while (left.isNotEmpty && ordered.length <= 20) {
      left.sort((x, y) => _km(cur, x).compareTo(_km(cur, y)));
      cur = left.removeAt(0);
      ordered.add(cur);
    }
    if (ordered.length < 2) return [];
    try {
      final coords =
          ordered.map((p) => '${p.longitude},${p.latitude}').join(';');
      final res = await _dio.get<dynamic>(
        'https://router.project-osrm.org/route/v1/driving/$coords',
        queryParameters: {'overview': 'full', 'geometries': 'polyline'},
      );
      final data = res.data;
      final routes = data is Map ? data['routes'] : null;
      if (routes is List && routes.isNotEmpty) {
        return _decodePolyline((routes.first as Map)['geometry'] as String);
      }
    } catch (e) {
      debugPrint('planned route error: $e');
    }
    return ordered; // road route failed -> straight lines between stops
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

  // =====================================================================
  // UI
  // =====================================================================
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  int get _dayDiff {
    final n = DateTime.now();
    final a = DateTime(n.year, n.month, n.day);
    final b = DateTime(_day.year, _day.month, _day.day);
    return a.difference(b).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final c = statusColor(_sm.status);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_sm.name, style: const TextStyle(fontSize: 17)),
          Text(statusLabel(_sm.status),
              style: TextStyle(
                  fontSize: 12, color: c, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: Column(children: [
        _filterBox(),
        Expanded(child: _mapView()),
        if (!_mapOnly) _summaryPanel(),
      ]),
    );
  }

  Widget _mapView() => Stack(children: [
        MapplsMap(
          initialCameraPosition: CameraPosition(
            target: _sm.hasPosition
                ? LatLng(_sm.lat!, _sm.lng!)
                : const LatLng(28.6139, 77.2090),
            zoom: 13.0,
          ),
          onMapCreated: (m) => _map = m,
          onStyleLoadedCallback: () async {
            await _registerScooty();
            _styleReady = true;
            _draw();
          },
        ),
        if (_loading || _assignedLoading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x55FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (!_loading && _error == null && _track != null && !_track!.hasData)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No tracking data for this day.'),
              ),
            ),
          ),
      ]);

  Widget _opt(String label, bool value, ValueChanged<bool>? onChanged,
          {IconData? icon}) =>
      FilterChip(
        label: Text(label),
        avatar: icon == null ? null : Icon(icon, size: 16),
        selected: value,
        showCheckmark: true,
        checkmarkColor: AppColors.blue,
        selectedColor: AppColors.blue.withOpacity(0.12),
        onSelected: onChanged,
        visualDensity: VisualDensity.compact,
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
      );

  bool _filtersOpen = true;

  int get _activeFilters =>
      [_optLive, _optRoute, _optVisits, _optAssigned, _mapOnly]
          .where((x) => x)
          .length;

  /// TOP filter box: date + map options + actions. Collapsible.
  Widget _filterBox() {
    final diff = _dayDiff;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => setState(() => _filtersOpen = !_filtersOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.tune, size: 20, color: AppColors.blue),
              const SizedBox(width: 8),
              const Text('Filters',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$_activeFilters on',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue)),
              ),
              const Spacer(),
              Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.muted),
            ]),
          ),
        ),
        if (_filtersOpen)
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          // ---- date presets ----
          _section('DATE'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(
              label: const Text('Today'),
              selected: diff == 0,
              onSelected: (_) => _setDay(DateTime.now()),
            ),
            ChoiceChip(
              label: const Text('Yesterday'),
              selected: diff == 1,
              onSelected: (_) =>
                  _setDay(DateTime.now().subtract(const Duration(days: 1))),
            ),
            ChoiceChip(
              label: const Text('2 Days Ago'),
              selected: diff == 2,
              onSelected: (_) =>
                  _setDay(DateTime.now().subtract(const Duration(days: 2))),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.calendar_today, size: 14),
              label: Text(diff > 2
                  ? '${_day.day} ${_months[_day.month - 1]}'
                  : 'Custom'),
              selected: diff > 2,
              onSelected: (_) => _pickDay(),
            ),
          ]),

          // ---- map options (tick to enable) ----
          _section('SHOW ON MAP'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _opt('Live Track', _optLive, _liveAvailable
                ? (v) {
                    setState(() => _optLive = v);
                    if (v) _followLive();
                  }
                : null,
                icon: Icons.sensors),
            _opt('Route', _optRoute, (v) {
              setState(() => _optRoute = v);
              _draw(fit: false);
            }, icon: Icons.timeline),
            _opt('Visits', _optVisits, (v) {
              setState(() => _optVisits = v);
              _draw(fit: false);
            }, icon: Icons.storefront_outlined),
            _opt('Assigned Route', _optAssigned, _toggleAssigned,
                icon: Icons.alt_route),
            _opt('Map only', _mapOnly, (v) => setState(() => _mapOnly = v),
                icon: Icons.fullscreen),
          ]),
          if (!_liveAvailable)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Live Track works for today while salesman is online.',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ),

          // ---- actions ----
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _viewSalesman,
                icon: const Icon(Icons.person_pin_circle_outlined, size: 18),
                label: const Text('View Salesman'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _fitAll,
                icon: const Icon(Icons.zoom_out_map, size: 18),
                label: const Text('Fit route'),
              ),
            ),
          ]),

                ],
              ),
            ),
          ),
      ]),
    );
  }

  /// BOTTOM: only the summary (+ visits list). Hidden in Map only.
  Widget _summaryPanel() => Container(
        width: double.infinity,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.34),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          children: _data(),
        ),
      );

  List<Widget> _data() {
    if (_error != null) {
      return [
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton(onPressed: _load, child: const Text('Retry')),
      ];
    }
    final t = _track;
    if (t == null) return [];
    return [
      _section('SUMMARY'),
      Row(children: [
        _stat('Distance', '${t.distanceKm.toStringAsFixed(1)} km'),
        const SizedBox(width: 8),
        _stat('Online', t.onlineTotal),
        const SizedBox(width: 8),
        _stat('Avg speed', '${t.avgSpeed.toStringAsFixed(0)} km/h'),
      ]),
      if (t.startTime != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('First ping ${t.startTime}  •  Last ping ${t.endTime ?? '--'}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
      _section('VISITS (${t.visits.length})'),
      if (t.visits.isEmpty)
        const Text('No visits recorded.',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
      for (final v in t.visits) _visitTile(v),
    ];
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        ),
      );

  Widget _visitTile(TrackVisit v) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.storefront_outlined,
              size: 20, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.shop.isEmpty ? 'Visit' : v.shop,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.text)),
                  if (v.address.isNotEmpty)
                    Text(v.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  if (v.purpose.isNotEmpty)
                    Text(v.purpose,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.blue)),
                ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(v.time,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            if (v.amount > 0)
              Text('₹${v.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
      );
}