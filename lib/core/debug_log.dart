import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Set to false to hide the on-screen log box (final release).
const bool kShowDebugBox = false;

class DebugLog {
  DebugLog._();

  static final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);
  static final ValueNotifier<bool> hasError = ValueNotifier<bool>(false);

  static String _t() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  static void log(String msg) {
    final next = List<String>.from(lines.value)..add('${_t()}  $msg');
    if (next.length > 120) next.removeRange(0, next.length - 120);
    lines.value = next;
    debugPrint('[NOTIF] $msg');
  }

  static void error(String where, Object e, [StackTrace? st]) {
    hasError.value = true;
    final s = st == null ? '' : '\n${st.toString().split('\n').take(3).join('\n')}';
    log('ERROR $where: $e$s');
  }

  static void clear() {
    lines.value = <String>[];
    hasError.value = false;
  }
}

/// Floating "LOG" button. Tap = open box with the log lines.
class DebugBoxOverlay extends StatefulWidget {
  final Widget child;
  const DebugBoxOverlay({super.key, required this.child});

  @override
  State<DebugBoxOverlay> createState() => _DebugBoxOverlayState();
}

class _DebugBoxOverlayState extends State<DebugBoxOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (!kShowDebugBox) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 8,
          bottom: 90,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: _open ? _panel() : _button(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _button() {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugLog.hasError,
      builder: (_, err, __) => GestureDetector(
        onTap: () => setState(() => _open = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: err ? Colors.red : Colors.black87,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('LOG',
              style: TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _panel() {
    final w = MediaQuery.of(context).size.width - 16;
    final h = MediaQuery.of(context).size.height * 0.5;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xEE000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 10),
              const Text('Notification log',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: DebugLog.lines.value.join('\n')));
                },
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: DebugLog.clear,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => setState(() => _open = false),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Close'),
              ),
            ],
          ),
          const Divider(height: 1, color: Colors.white24),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: DebugLog.lines,
              builder: (_, list, __) => ListView.builder(
                padding: const EdgeInsets.all(8),
                reverse: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final line = list[list.length - 1 - i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        color: line.contains('ERROR')
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}