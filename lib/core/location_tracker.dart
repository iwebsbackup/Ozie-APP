import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'api_client.dart';
import 'config.dart';
import 'debug_log.dart';

/// Salesman live tracking. Runs as an Android foreground service so it keeps
/// reporting when the app is in background or swiped away.
enum TrackState { checking, on, limited, off }

class LocationTracker {
  LocationTracker._();

  /// UI status (home screen card listens to this).
  static final ValueNotifier<TrackState> state =
      ValueNotifier<TrackState>(TrackState.checking);

  static const String _channelId = 'ozie_tracking';
  static const int _notifId = 8841;

  /// Salesman "Online / Offline" switch (home screen toggle).
  /// true  = tracking service should be running
  /// false = salesman offline, nothing is tracked
  /// Persisted so the background isolate (also after reboot) can respect it.
  static final ValueNotifier<bool> online = ValueNotifier<bool>(false);
  static const String _onlineKey = 'ozie_online';
  static const FlutterSecureStorage _store = FlutterSecureStorage();

  static Future<bool> _readOnlineFlag() async =>
      (await _store.read(key: _onlineKey)) == 'true';

  static Future<void> _writeOnlineFlag(bool v) =>
      _store.write(key: _onlineKey, value: v ? 'true' : 'false');

  /// Tells the server (-> web "View Reports" panel) the salesman went online /
  /// offline RIGHT NOW. Without this the panel only guesses from GPS pings
  /// (2 min delay). Never throws; a failed call is fixed by the next resume().
  static Future<void> _postStatus(bool on) async {
    try {
      await ApiClient.instance
          .post('v1/salesman/status', body: {'online': on})
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      DebugLog.log('tracker status post failed: $e');
    }
  }

  /// Load saved online/offline choice into [online]. Call when home opens.
  static Future<void> loadOnline() async {
    try {
      online.value = await _readOnlineFlag();
    } catch (_) {
      online.value = false;
    }
  }

  /// Call once in main() before runApp().
  static Future<void> initialize() async {
    final local = FlutterLocalNotificationsPlugin();
    await local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          'Ozie Location Tracking',
          description: 'Shown while your work location is being shared',
          importance: Importance.low,
        ));

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Ozie',
        initialNotificationContent: 'Location tracking is active',
        foregroundServiceNotificationId: _notifId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Recomputes [state] from real permission / service status.
  static Future<void> refreshState() async {
    try {
      final gps = await Geolocator.isLocationServiceEnabled();
      final always = await Permission.locationAlways.isGranted;
      final fg = await Permission.locationWhenInUse.isGranted;
      final running = await FlutterBackgroundService().isRunning();
      DebugLog.log('tracker gps=$gps fg=$fg always=$always running=$running');
      if (gps && always && running) {
        state.value = TrackState.on;
      } else if (fg) {
        state.value = TrackState.limited;
      } else {
        state.value = TrackState.off;
      }
    } catch (e, st) {
      DebugLog.error('tracker status', e, st);
      state.value = TrackState.off;
    }
  }

  /// App came back to foreground: if salesman is ONLINE but the service is
  /// dead (OEM killed it), start it again silently. Offline = do nothing.
  static Future<void> resume() async {
    try {
      if (await _readOnlineFlag()) {
        final canTrack = (await _missing()) == null; // every permission + GPS
        if (canTrack) {
          await start();
          online.value = true;
          unawaited(_postStatus(true)); // keep server in sync (idempotent)
        } else {
          // any permission taken away / GPS off -> be honest, show offline
          await stop();
        }
      } else {
        online.value = false;
      }
    } catch (e, st) {
      DebugLog.error('tracker resume', e, st);
    }
    await refreshState();
  }

  /// Ask all permissions up-front (notification, location, all-the-time,
  /// battery, GPS on). Does NOT start tracking.
  static Future<void> requestPermissions(BuildContext context) async {
    try {
      await _ensurePermissions(context);
    } catch (e, st) {
      DebugLog.error('tracker permissions', e, st);
    }
    await refreshState();
  }

  /// Toggle ON. Goes online ONLY when every permission is allowed:
  /// notification, location, location "All the time", battery (no
  /// restriction) and GPS on. Returns null on success, otherwise a short
  /// message telling what is still missing (toggle stays OFF).
  static Future<String?> goOnline(BuildContext context) async {
    try {
      final missing = await _ensurePermissions(context);
      if (missing != null) {
        await refreshState();
        return missing;
      }
      await _writeOnlineFlag(true); // before start: background isolate reads it
      await start();
      online.value = true;
      await _postStatus(true); // web panel shows him online immediately
      await refreshState();
      return null;
    } catch (e, st) {
      DebugLog.error('tracker online', e, st);
      await refreshState();
      return 'Location tracking error: $e';
    }
  }

  /// Toggle OFF: salesman is offline, tracking stops.
  static Future<void> goOffline() async {
    await stop();
    await _waitUntilStopped();
    await refreshState();
  }

  /// Old name, kept for existing callers.
  static Future<bool> ensureAndStart(BuildContext context) async =>
      (await goOnline(context)) == null;

  /// First permission that is still not allowed, or null when all are fine.
  static Future<String?> _missing() async {
    if (!await Permission.notification.isGranted) {
      return 'Allow notification permission.';
    }
    if (!await Permission.locationWhenInUse.isGranted) {
      return 'Allow location permission.';
    }
    if (!await Permission.locationAlways.isGranted) {
      return 'Set location to "Allow all the time".';
    }
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      return 'Allow "No restrictions" for battery usage.';
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on GPS (location).';
    }
    return null;
  }

  /// Asks every permission one by one (with explanation / settings dialogs).
  /// Returns null when ALL are allowed, else the first missing one.
  static Future<String?> _ensurePermissions(BuildContext context) async {
    DebugLog.log('tracker permissions start');

    // 1. notification (Android 13+: foreground-service notification)
    final noti = await Permission.notification.request();
    if (!noti.isGranted) {
      if (noti.isPermanentlyDenied && context.mounted) {
        final go = await _ask(context, 'Notification permission needed',
            'Tracking shows a notification while it is running. Enable notifications in app settings.',
            'Open Settings');
        if (go) await openAppSettings();
      }
      return _missing();
    }

    // 2. location (while in use)
    final fg = await Permission.locationWhenInUse.request();
    if (!fg.isGranted) {
      if (fg.isPermanentlyDenied && context.mounted) {
        final go = await _ask(context, 'Location permission needed',
            'Salesman login needs location permission. Enable it in app settings.',
            'Open Settings');
        if (go) await openAppSettings();
      }
      return _missing();
    }

    // 3. location "All the time"
    if (!await Permission.locationAlways.isGranted) {
      if (!context.mounted) return _missing();
      final go = await _ask(
          context,
          'Allow location "All the time"',
          'To record your route even when the app is closed, choose "Allow all the time" on the next screen.',
          'Continue');
      if (go) {
        final always = await Permission.locationAlways.request();
        if (!always.isGranted) await openAppSettings();
      }
      if (!await Permission.locationAlways.isGranted) return _missing();
    }

    // 4. battery: OEMs (Xiaomi/Oppo/Vivo...) kill background apps otherwise
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        return _missing();
      }
    }

    // 5. GPS switch last, so permission dialogs are never skipped
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!context.mounted) return _missing();
      final go = await _ask(context, 'Turn on Location',
          'Location (GPS) is off. Please turn it on so your work route can be recorded.',
          'Open Settings');
      if (go) await Geolocator.openLocationSettings();
      return _missing();
    }

    return _missing(); // null = everything allowed
  }

  static Future<void> start() async {
    final s = FlutterBackgroundService();
    if (!await s.isRunning()) await s.startService();
  }

  /// Offline: clears the online flag and stops the service.
  /// Also called on logout.
  static Future<void> stop() async {
    try {
      await _writeOnlineFlag(false); // first, so a restart cannot revive it
    } catch (_) {}
    online.value = false;
    // tell server first (token still valid, also on logout) -> web shows offline at once
    await _postStatus(false);
    final s = FlutterBackgroundService();
    if (await s.isRunning()) s.invoke('stop');
  }

  /// Service flushes pending points before it quits (max ~5s). Wait for it so
  /// a quick OFF -> ON does not hit a half-dead service.
  static Future<void> _waitUntilStopped() async {
    final s = FlutterBackgroundService();
    for (var i = 0; i < 25; i++) {
      if (!await s.isRunning()) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  static Future<bool> _ask(
      BuildContext c, String title, String msg, String ok) async {
    final r = await showDialog<bool>(
      context: c,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Later')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    );
    return r ?? false;
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async => true;

/// Background isolate entry point.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  const storage = FlutterSecureStorage();
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    contentType: Headers.jsonContentType,
    headers: {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'X-Requested-With': 'XMLHttpRequest',
    },
  ));

  final buffer = <Map<String, dynamic>>[]; // points waiting to be uploaded
  Position? lastPos;
  var lastQueued = DateTime.fromMillisecondsSinceEpoch(0);
  var flushing = false;
  StreamSubscription<Position>? sub;
  StreamSubscription<CompassEvent>? compassSub;
  StreamSubscription<AccelerometerEvent>? accelSub;
  Timer? heartbeat;
  double? compass; // smoothed phone compass, 0-360 (0 = North), null = no sensor
  double? lastSentHeading;
  double? gy, gz; // smoothed gravity (m/s2): tells flat vs upright phone
  double? cSin, cCos; // circular low-pass filter of the compass

  Future<void> shutdown() async {
    heartbeat?.cancel();
    await sub?.cancel();
    await compassSub?.cancel();
    await accelSub?.cancel();
    service.stopSelf();
  }

  // replaced below once flush() exists (send pending points, then quit)
  Future<void> Function() onStop = shutdown;
  service.on('stop').listen((_) => onStop());

  // salesman is OFFLINE (toggle off / after logout / after reboot) -> do not track
  final online = await storage.read(key: 'ozie_online');
  if (online != 'true') {
    await shutdown();
    return;
  }

  // not logged in (e.g. restarted after boot following logout) -> nothing to track
  final firstToken = await storage.read(key: 'ozie_token');
  if (firstToken == null || firstToken.isEmpty) {
    await shutdown();
    return;
  }

  Future<void> flush() async {
    if (flushing || buffer.isEmpty) return;
    flushing = true;
    try {
      final token = await storage.read(key: 'ozie_token');
      if (token == null || token.isEmpty) {
        await shutdown();
        return;
      }
      final batch = buffer.take(100).toList();
      await dio.post<dynamic>(
        'v1/salesman/location',
        data: {'points': batch},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      buffer.removeRange(0, batch.length);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await storage.write(key: 'ozie_online', value: 'false');
        await shutdown(); // token revoked / not a salesman
        return;
      }
      // network down: keep points, retry on next tick
    } catch (_) {
    } finally {
      flushing = false;
    }
  }

  onStop = () async {
    try {
      await flush().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await shutdown();
  };

  void queue(Position p) {
    final kmh = p.speed * 3.6;
    // heading for the web scooty icon:
    //  moving (>= 6 km/h)  -> GPS course (true direction of travel, best accuracy)
    //  slow / standing     -> smoothed compass (GPS course is garbage when slow)
    double? hd;
    if (kmh >= 6 && p.heading >= 0) {
      hd = p.heading;
    } else {
      hd = compass;
    }
    lastSentHeading = hd;
    buffer.add({
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracy': p.accuracy,
      'speed': kmh < 1.5 ? 0 : double.parse(kmh.toStringAsFixed(1)),
      if (hd != null) 'heading': hd.round() % 360,
      'recorded_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    if (buffer.length > 1000) buffer.removeRange(0, buffer.length - 1000);
    lastQueued = DateTime.now();
    flush();
  }

  sub = Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // metres moved before next fix
      intervalDuration: const Duration(seconds: 10),
    ),
  ).listen((p) {
    lastPos = p;
    if (DateTime.now().difference(lastQueued).inSeconds >= 8) queue(p);
  }, onError: (_) {});

  // compass: phone turned (even standing still) -> push a fresh point so the
  // scooty on the web panel turns within seconds. >= 20 deg change, max 1 per 4s.
  // gravity -> is the phone lying flat or held / mounted upright?
  try {
    accelSub = accelerometerEventStream(
            samplingPeriod: SensorInterval.normalInterval)
        .listen((a) {
      gy = gy == null ? a.y : gy! * 0.9 + a.y * 0.1;
      gz = gz == null ? a.z : gz! * 0.9 + a.z * 0.1;
    }, onError: (_) {});
  } catch (_) {}

  try {
    compassSub = FlutterCompass.events?.listen((e) {
      // flat phone -> normal heading. Upright phone (bike mount) -> camera-mode
      // heading = where the back of the phone points = direction of the bike.
      final upright = gy != null && gz != null && gy!.abs() > 6.5 && gz!.abs() < 6.5;
      final h = upright ? (e.headingForCameraMode ?? e.heading) : e.heading;
      if (h == null) return;

      // circular low-pass filter: kills magnetometer jitter, no 359 -> 0 jump
      final r = h * math.pi / 180;
      cSin = cSin == null ? math.sin(r) : cSin! * 0.8 + math.sin(r) * 0.2;
      cCos = cCos == null ? math.cos(r) : cCos! * 0.8 + math.cos(r) * 0.2;
      compass = ((math.atan2(cSin!, cCos!) * 180 / math.pi) % 360 + 360) % 360;

      final p = lastPos;
      if (p == null) return;
      if (p.speed * 3.6 >= 6) return; // moving: GPS course is used instead
      if (DateTime.now().difference(lastQueued).inSeconds < 4) return;
      final last = lastSentHeading;
      var diff = last == null ? 360.0 : (compass! - last).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff >= 15) queue(p);
    }, onError: (_) {});
  } catch (_) {}

  // heartbeat: while standing still the stream is silent -> still ping every 45s
  // so the web panel shows "online" and halts get real timestamps.
  heartbeat = Timer.periodic(const Duration(seconds: 45), (_) async {
    if (DateTime.now().difference(lastQueued).inSeconds >= 40) {
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20)),
        );
        lastPos = p;
        queue(p);
      } catch (_) {
        if (lastPos != null) queue(lastPos!);
      }
    } else {
      flush(); // retry anything stuck in buffer
    }
  });
}