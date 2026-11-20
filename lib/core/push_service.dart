import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/notifications_screen.dart';
import 'api_client.dart';
import 'config.dart';
import 'debug_log.dart';
import 'notification_router.dart';
import 'router.dart';

class PushService {
  PushService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ozie_default',
    'Ozie Notifications',
    description: 'Orders, schemes, returns and other updates',
    importance: Importance.high,
  );

  static bool _inited = false;
  static bool _initializing = false;
  static bool _pendingOpen = false;
  static String? _lastSent;
  static String? _pendingLink;

  static String? _linkOf(RemoteMessage m) {
    final l = m.data['link']?.toString().trim();
    return (l == null || l.isEmpty) ? null : l;
  }

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// App start pe ek baar (main). Listeners lagata hai.
  /// Har step alag try/catch me: ek fail ho to baaki ruke nahi.
  static Future<void> init() async {
    if (_inited || _initializing || !AppConfig.firebaseReady) {
      // DebugLog.log('init skipped inited=$_inited initializing=$_initializing fbReady=${AppConfig.firebaseReady}');
      return;
    }
    _initializing = true;
    // DebugLog.log('push init start');

    // 1. Local notifications (foreground display + local tap)
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          // DebugLog.log('local tap payload=${r.payload}');
          _openNotifications(link: r.payload);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (e, st) {
      DebugLog.error('push init: local notifications', e, st);
    }

    // 2. iOS foreground banner
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);
    } catch (e, st) {
      DebugLog.error('push init: ios presentation', e, st);
    }

    // 3. FCM listeners (independent of local notifications)
    try {
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        // DebugLog.log('onMessageOpenedApp data=${m.data}');
        _openNotifications(link: _linkOf(m));
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        if (ApiClient.instance.hasToken) _send(t);
      });
    } catch (e, st) {
      DebugLog.error('push init: listeners', e, st);
    }

    // 4. App killed thi, notification tap se khuli
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      // DebugLog.log('getInitialMessage = ${initial == null ? 'null' : initial.data}');
      if (initial != null) {
        _pendingOpen = true;
        _pendingLink = _linkOf(initial);
        // DebugLog.log('pending set link=$_pendingLink');
      }
    } catch (e, st) {
      DebugLog.error('push init: initial message', e, st);
    }

    _inited = true;
    _initializing = false;
    // DebugLog.log('push init done');
  }

  /// Login / me() ke baad. force=true => server ko phir bhejo (user badal sakta hai).
  static Future<void> register({bool force = false}) async {
    if (!AppConfig.firebaseReady) return;
    try {
      await init();
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final t = await FirebaseMessaging.instance.getToken();
      if (t == null) return; // iOS: APNs token late aaye to onTokenRefresh sambhal lega
      if (!force && t == _lastSent) return;
      await _send(t);
      // DebugLog.log('token registered');
    } catch (e, st) {
      DebugLog.error('register', e, st);
    }
  }

  /// Logout se PEHLE call. Server se token hatao + device token reset.
  static Future<void> unregister() async {
    if (!AppConfig.firebaseReady) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && ApiClient.instance.hasToken) {
        await ApiClient.instance.post('v1/auth/device-token', body: {
          'token': t,
          'platform': _platform,
          'action': 'delete',
        });
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _lastSent = null;
  }

  /// MainShell khulne ke baad call: killed-state tap ko handle karta hai.
  static void openPendingIfAny() {
    // DebugLog.log('openPendingIfAny pending=$_pendingOpen link=$_pendingLink');
    if (_pendingOpen) {
      _pendingOpen = false;
      final l = _pendingLink;
      _pendingLink = null;
      _openNotifications(link: l);
    }
  }

  static Future<void> _send(String token) async {
    await ApiClient.instance.post('v1/auth/device-token', body: {
      'token': token,
      'platform': _platform,
    });
    _lastSent = token;
  }

  /// Image URL se bytes (timeout 8s). Fail => null (text-only notification).
  static Future<Uint8List?> _downloadImage(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final bytes = await res.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (b, d) => b..add(d),
      );
      return bytes.takeBytes();
    } catch (e) {
      // DebugLog.log('image download failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _onForeground(RemoteMessage m) async {
    // Android foreground mein system tray nahi dikhata, local dikhao.
    // iOS ko upar wali presentation options handle karti hain.
    final n = m.notification;
    // DebugLog.log('foreground msg data=${m.data}');
    if (n == null || !Platform.isAndroid) return;

    // Image: data['image'] ya notification.android.imageUrl
    final imgUrl = (m.data['image']?.toString() ?? n.android?.imageUrl ?? '').trim();
    StyleInformation? style;
    if (imgUrl.startsWith('http')) {
      final bytes = await _downloadImage(imgUrl);
      if (bytes != null) {
        final bmp = ByteArrayAndroidBitmap(bytes);
        style = BigPictureStyleInformation(
          bmp,
          largeIcon: bmp,
          hideExpandedLargeIcon: true,
          contentTitle: n.title,
          summaryText: n.body,
        );
      }
    }

    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          styleInformation: style,
        ),
      ),
      payload: m.data['link']?.toString(),
    );
  }

  static void _openNotifications({String? link}) {
    final nav = navigatorKey.currentState;
    // DebugLog.log('_openNotifications link=$link nav=${nav != null} token=${ApiClient.instance.hasToken}');
    // App abhi boot ho rahi / login nahi => baad mein khulega
    if (nav == null || !ApiClient.instance.hasToken) {
      _pendingOpen = true;
      _pendingLink = link;
      return;
    }
    // list first so Back returns to notifications, then the linked screen
    nav.push(MaterialPageRoute<void>(
      builder: (_) => const NotificationsScreen(),
    ));
    if (link != null && link.isNotEmpty) {
      try {
        final ok = openNotificationLink(nav, link);
        // DebugLog.log('openNotificationLink($link) -> $ok');
      } catch (e, st) {
        DebugLog.error('openNotificationLink', e, st);
      }
    } else {
      // DebugLog.log('no link in message -> only list opened');
    }
  }
}