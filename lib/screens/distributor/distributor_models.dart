import 'package:mappls_gl/mappls_gl.dart';

double? _d(dynamic v) => v == null ? null : double.tryParse('$v');
int _i(dynamic v) => v == null ? 0 : (int.tryParse('$v') ?? 0);

/// One salesman row from GET v1/distributor/salesmen.
class SalesmanLive {
  final int id;
  final int userId;
  final String name;

  /// moving | stop | offline
  final String status;
  final double speed;
  final String lastActive;
  final double? lat;
  final double? lng;

  /// phone compass 0-359 (0 = North), null if unknown
  final double? heading;

  const SalesmanLive({
    required this.id,
    required this.userId,
    required this.name,
    required this.status,
    required this.speed,
    required this.lastActive,
    this.lat,
    this.lng,
    this.heading,
  });

  bool get isOnline => status != 'offline';
  bool get hasPosition => lat != null && lng != null;

  factory SalesmanLive.fromJson(Map<String, dynamic> j) => SalesmanLive(
        id: _i(j['id']),
        userId: _i(j['user_id']),
        name: (j['name'] ?? '').toString(),
        status: (j['status'] ?? 'offline').toString(),
        speed: _d(j['speed']) ?? 0,
        lastActive: (j['last_active'] ?? '').toString(),
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        heading: _d(j['heading']),
      );
}

class SalesmanListResult {
  final List<SalesmanLive> salesmen;
  final int moving;
  final int stop;
  final int offline;
  const SalesmanListResult({
    required this.salesmen,
    required this.moving,
    required this.stop,
    required this.offline,
  });

  factory SalesmanListResult.fromJson(Map<String, dynamic> j) {
    final c = j['counts'] is Map ? Map<String, dynamic>.from(j['counts']) : {};
    return SalesmanListResult(
      salesmen: (j['salesmen'] as List? ?? [])
          .map((e) => SalesmanLive.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      moving: _i(c['moving']),
      stop: _i(c['stop']),
      offline: _i(c['offline']),
    );
  }
}

class TrackVisit {
  final String time;
  final String shop;
  final String address;
  final String purpose;
  final double amount;
  final double? lat;
  final double? lng;
  const TrackVisit({
    required this.time,
    required this.shop,
    required this.address,
    required this.purpose,
    required this.amount,
    this.lat,
    this.lng,
  });

  bool get hasPin => lat != null && lng != null;

  factory TrackVisit.fromJson(Map<String, dynamic> j) => TrackVisit(
        time: (j['time'] ?? '').toString(),
        shop: (j['shop'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        purpose: (j['purpose'] ?? '').toString(),
        amount: _d(j['amount']) ?? 0,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
      );
}

class TrackSession {
  final String from;
  final String to;
  final String duration;
  final bool live;
  const TrackSession({
    required this.from,
    required this.to,
    required this.duration,
    required this.live,
  });

  factory TrackSession.fromJson(Map<String, dynamic> j) => TrackSession(
        from: (j['from_time'] ?? '').toString(),
        to: (j['to_time'] ?? '').toString(),
        duration: (j['duration'] ?? '').toString(),
        live: j['live'] == true,
      );
}

/// One day of tracking for one salesman.
class DayTrack {
  final String date;
  final bool hasData;
  final int pingCount;
  final List<List<LatLng>> segments;
  final double distanceKm;
  final String? startTime;
  final String? endTime;
  final String onlineTotal;
  final double avgSpeed;
  final double maxSpeed;
  final List<TrackSession> sessions;
  final List<TrackVisit> visits;

  const DayTrack({
    required this.date,
    required this.hasData,
    required this.pingCount,
    required this.segments,
    required this.distanceKm,
    required this.startTime,
    required this.endTime,
    required this.onlineTotal,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.sessions,
    required this.visits,
  });

  static LatLng? _pt(dynamic p) {
    if (p is List && p.length >= 2) {
      final lng = _d(p[0]);
      final lat = _d(p[1]);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null; // API sends [lng, lat]
  }

  factory DayTrack.fromJson(Map<String, dynamic> j) {
    final segs = <List<LatLng>>[];
    for (final s in (j['segments'] as List? ?? [])) {
      final pts = <LatLng>[];
      for (final p in (s as List)) {
        final ll = _pt(p);
        if (ll != null) pts.add(ll);
      }
      if (pts.length > 1) segs.add(pts);
    }
    return DayTrack(
      date: (j['date'] ?? '').toString(),
      hasData: j['has_data'] == true,
      pingCount: _i(j['ping_count']),
      segments: segs,
      distanceKm: _d(j['distance_km']) ?? 0,
      startTime: j['start_time']?.toString(),
      endTime: j['end_time']?.toString(),
      onlineTotal: (j['online_total'] ?? '0m').toString(),
      avgSpeed: _d(j['avg_speed']) ?? 0,
      maxSpeed: _d(j['max_speed']) ?? 0,
      sessions: (j['sessions'] as List? ?? [])
          .map((e) => TrackSession.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      visits: (j['visits'] as List? ?? [])
          .map((e) => TrackVisit.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
