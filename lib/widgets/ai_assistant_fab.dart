import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/router.dart';
import '../screens/ai_assistant_screen.dart';

/// Floating chat button shown over the whole app (bottom right) once the
/// user is logged in. Drag it to move it. Tap opens "AI Business Assistant".
///
/// Wire-up (main.dart):
///   navigatorObservers: [AiFabNavigatorObserver()]
///   builder: Stack(fit: StackFit.expand, children: [app, const AiAssistantFab()])
class AiAssistantFab extends StatefulWidget {
  const AiAssistantFab({super.key});

  static final ValueNotifier<bool> _loggedIn = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> _assistantOpen = ValueNotifier<bool>(false);

  /// Re-check login state (called on every navigation).
  static void refresh() {
    final v = ApiClient.instance.hasToken;
    if (_loggedIn.value != v) _loggedIn.value = v;
  }

  static void setAssistantOpen(bool open) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_assistantOpen.value != open) _assistantOpen.value = open;
    });
  }

  @override
  State<AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<AiAssistantFab> {
  static const double _size = 54;
  static const double _margin = 12;

  Offset? _pos; // top-left

  void _open() {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/ai-assistant'),
        builder: (_) => const AiAssistantScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AiAssistantFab._loggedIn,
      builder: (context, loggedIn, _) => ValueListenableBuilder<bool>(
        valueListenable: AiAssistantFab._assistantOpen,
        builder: (context, open, __) {
          final mq = MediaQuery.of(context);
          final keyboard = mq.viewInsets.bottom > 0;
          if (!loggedIn || open || keyboard) return const SizedBox.shrink();

          final w = mq.size.width;
          final h = mq.size.height;
          final minX = _margin;
          final maxX = w - _size - _margin;
          final minY = mq.padding.top + _margin;
          final maxY = h - _size - mq.padding.bottom - _margin;
          // Default: bottom right, above the bottom nav / action bars.
          final def = Offset(maxX, maxY - 96);
          final p = _pos ?? def;
          final pos = Offset(
            p.dx.clamp(minX, maxX).toDouble(),
            p.dy.clamp(minY, maxY).toDouble(),
          );

          return Positioned(
            left: pos.dx,
            top: pos.dy,
            child: GestureDetector(
              onTap: _open,
              onPanUpdate: (d) => setState(() => _pos = Offset(
                    (pos.dx + d.delta.dx).clamp(minX, maxX).toDouble(),
                    (pos.dy + d.delta.dy).clamp(minY, maxY).toDouble(),
                  )),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/robot_logo.png',
                      width: _size,
                      height: _size,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Re-checks login state after every navigation, so the button appears after
/// login and disappears after logout / token expiry.
class AiFabNavigatorObserver extends NavigatorObserver {
  void _poke() => WidgetsBinding.instance
      .addPostFrameCallback((_) => AiAssistantFab.refresh());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _poke();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _poke();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _poke();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _poke();
}