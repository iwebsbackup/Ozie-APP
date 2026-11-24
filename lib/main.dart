import 'dart:ui' show PlatformDispatcher;

// import 'package:device_lab/device_lab.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/foundation.dart' show kReleaseMode; // only for DeviceLab
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'core/debug_log.dart';
import 'core/location_tracker.dart';
import 'core/push_service.dart';
import 'core/responsive.dart';
import 'core/router.dart';
import 'core/test_mode.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_widgets.dart';

/// Background / killed state mein push aane pe chalta hai. Top-level hona zaroori.
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // phones: portrait only. Tablets/foldables unlock rotation (see ResponsiveScope).
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);

  // show every uncaught error in the on-screen log box
  FlutterError.onError = (d) => DebugLog.error('flutter', d.exception, d.stack);
  PlatformDispatcher.instance.onError = (e, st) {
    DebugLog.error('platform', e, st);
    return true;
  };

  // Firebase is needed for Google sign-in and push. App still works without it.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppConfig.firebaseReady = true;
    DebugLog.log('firebase ready');
    FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);
    await PushService.init();
  } catch (e, st) {
    AppConfig.firebaseReady = false;
    DebugLog.error('firebase init', e, st);
  }

  // Salesman background location service (config only; starts after salesman login)
  try {
    await LocationTracker.initialize();
  } catch (e, st) {
    DebugLog.error('tracker init', e, st);
  }

  // Token expired / revoked -> back to login from anywhere.
  ApiClient.instance.onUnauthorized = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };

  await TestMode.load();

  // Device Lab disabled. To bring it back: uncomment this block, remove the
  // plain runApp below, and uncomment device_lab in pubspec.yaml + import above.
  // runApp(
  //   DeviceLab(
  //     enabled: !kReleaseMode,
  //     builder: (_) => const OzieApp(),
  //   ),
  // );
  runApp(const OzieApp());
}

class OzieApp extends StatelessWidget {
  const OzieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ozie',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildTheme(),
      // locale: DeviceLab.localeOf(context),
      builder: (context, child) {
        // Device Lab disabled (was the OUTER layer around the lines below).
        // return DeviceLab.appBuilder(
        //   context,
        //   DebugBoxOverlay(
        //     child: ResponsiveScope(
        //       child: child ?? const SizedBox.shrink(),
        //     ),
        //   ),
        // );
        return DebugBoxOverlay(
          child: ResponsiveScope(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}