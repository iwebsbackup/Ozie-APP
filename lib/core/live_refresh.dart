import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// App-wide "data changed on server" signal. Push (FCM) bumps it, screens that
/// show live numbers (credit limit / available credit) listen and refetch.
class LiveRefresh {
  LiveRefresh._();
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void bump() => tick.value++;
}

/// Keeps a screen fresh without spinners:
///  - refetch when a push arrives (instant, needs server to send push)
///  - refetch when app returns to foreground
///  - refetch every [interval] while app is in foreground (fallback)
class LivePoller with WidgetsBindingObserver {
  final Future<void> Function() onTick;
  final Duration interval;
  Timer? _timer;
  bool _running = false;
  bool _busy = false;

  LivePoller({
    required this.onTick,
    this.interval = const Duration(seconds: 15),
  });

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    LiveRefresh.tick.addListener(_fire);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _fire());
  }

  Future<void> _fire() async {
    if (_busy) return;
    _busy = true;
    try {
      await onTick();
    } catch (_) {
      // silent: keep showing last good data
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fire();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  void dispose() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    LiveRefresh.tick.removeListener(_fire);
    WidgetsBinding.instance.removeObserver(this);
  }
}
