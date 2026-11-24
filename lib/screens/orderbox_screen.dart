import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api_client.dart';
import '../core/voice_order_service.dart';
import 'checkout_screen.dart';

/// Bottom-nav mic -> "ORDERBOX by Ozie" (AI voice ordering agent).
///
/// API: v1/retailer/voice-order
///   speak / upload voice note -> process_audio
///   qty / product / promo     -> preview
///   Save to Cart / Checkout   -> confirm
class OrderboxScreen extends StatefulWidget {
  const OrderboxScreen({super.key});

  @override
  State<OrderboxScreen> createState() => _OrderboxScreenState();
}

class _OrderboxScreenState extends State<OrderboxScreen>
    with TickerProviderStateMixin {
  // Palette (cyber-navy).
  static const Color _bg1 = Color(0xFF020716);
  static const Color _bg2 = Color(0xFF050E28);
  static const Color _bg3 = Color(0xFF020612);
  static const Color _blue = Color(0xFF0088FF);
  static const Color _cyan = Color(0xFF00B0FF);
  static const Color _sky = Color(0xFF38BDF8);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _slate = Color(0xFF94A3B8);
  static const Color _ocean = Color(0xFF0284C7);
  static const Color _teal = Color(0xFF0D9488);

  static const int _maxSeconds = 90;
  static const int _maxUploadBytes = 25 * 1024 * 1024;

  final AudioRecorder _rec = AudioRecorder();
  String _transcript = ''; // sent back to server on preview
  final TextEditingController _promo = TextEditingController();

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(seconds: 6))
    ..repeat();
  late final AnimationController _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  Timer? _tick;
  Timer? _debounce;

  bool _recording = false;
  bool _processing = false;
  bool _busy = false; // preview / confirm in flight
  int _seconds = 0;

  final List<VoiceItem> _items = [];
  String _notes = '';
  double _subtotal = 0;
  double _discount = 0;
  double _total = 0;
  String _couponMsg = '';

  bool get _hasResult => _items.isNotEmpty;
  List<VoiceItem> get _lines =>
      _items.where((e) => e.isMatched && e.quantity > 0).toList();

  @override
  void dispose() {
    _tick?.cancel();
    _debounce?.cancel();
    _pulse.dispose();
    _spin.dispose();
    _wave.dispose();
    _promo.dispose();
    _rec.dispose();
    super.dispose();
  }

  /* ----------------------------- helpers ----------------------------- */

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFF9F1239) : const Color(0xFF047857),
        behavior: SnackBarBehavior.floating,
      ));
  }

  String _mmss(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  /// ₹ with Indian digit grouping: ₹1,23,456.00
  String _inr(double v) {
    final neg = v < 0;
    final p = v.abs().toStringAsFixed(2).split('.');
    final n = p[0];
    String g;
    if (n.length <= 3) {
      g = n;
    } else {
      final last = n.substring(n.length - 3);
      var rest = n.substring(0, n.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      g = '${parts.join(',')},$last';
    }
    return '${neg ? '-' : ''}₹$g.${p[1]}';
  }

  /* ----------------------------- recording ----------------------------- */

  Future<void> _startRecording() async {
    if (_processing || _recording) return;
    HapticFeedback.mediumImpact();
    try {
      if (!await _rec.hasPermission()) {
        _toast('Microphone permission is required. Please allow it in Settings.',
            error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/orderbox_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _seconds = 0;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stopAndProcess();
      });
      setState(() => _recording = true);
    } catch (_) {
      _toast('Could not start recording.', error: true);
    }
  }

  Future<void> _cancelRecording() async {
    _tick?.cancel();
    try {
      await _rec.cancel();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _recording = false;
        _seconds = 0;
      });
    }
  }

  Future<void> _stopAndProcess() async {
    if (!_recording) return;
    _tick?.cancel();
    HapticFeedback.lightImpact();
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (!mounted) return;
    final secs = _seconds;
    setState(() {
      _recording = false;
      _seconds = 0;
    });
    if (path == null || secs < 1) {
      _toast("Didn't catch that. Please try again.", error: true);
      return;
    }
    final filePath = path;
    await _process(() async {
      final bytes = await File(filePath).readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw ApiException('Recording is too long. Please keep the order shorter.');
      }
      return VoiceOrderService.processAudio(base64Encode(bytes), mime: 'audio/mp4');
    });
    try {
      File(filePath).delete();
    } catch (_) {}
  }

  Future<void> _pickAudioFile() async {
    if (_processing || _recording) return;
    try {
      // file_picker v13: static pickFile(), bytes read lazily from PlatformFile.
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'opus', 'ogg', 'mp3', 'm4a', 'aac', 'wav', 'mp4', 'webm'
        ],
      );
      if (f == null) return;
      final size = await f.length() ?? 0;
      if (size > _maxUploadBytes) {
        _toast('File is larger than 25MB.', error: true);
        return;
      }
      final dot = f.name.lastIndexOf('.');
      final ext = dot >= 0 ? f.name.substring(dot + 1).toLowerCase() : '';
      const mimes = {
        'opus': 'audio/ogg',
        'ogg': 'audio/ogg',
        'mp3': 'audio/mp3',
        'wav': 'audio/wav',
        'webm': 'audio/webm',
      };
      final mime = mimes[ext] ?? 'audio/mp4'; // m4a / aac / mp4
      await _process(() async {
        final bytes = await f.readAsBytes();
        return VoiceOrderService.processAudio(base64Encode(bytes), mime: mime);
      });
    } catch (_) {
      _toast('Could not open the file.', error: true);
    }
  }

  /// Runs an API job that returns a draft, with shared loading + error UI.
  Future<void> _process(Future<VoiceDraft> Function() job) async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      _applyDraft(await job());
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not process the order. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /* ------------------------------- draft ------------------------------- */

  void _applyDraft(VoiceDraft d) {
    if (!mounted) return;
    if (d.items.isEmpty) {
      _toast('No products found in the order. Please try again.', error: true);
      return;
    }
    setState(() {
      _items
        ..clear()
        ..addAll(d.items);
      _transcript = d.transcript;
      _notes = d.notes;
      _subtotal = d.subtotal;
      _discount = d.discount;
      _total = d.total;
      _couponMsg = d.couponMessage;
    });
  }

  void _reset() {
    _debounce?.cancel();
    setState(() {
      _items.clear();
      _notes = '';
      _subtotal = _discount = _total = 0;
      _couponMsg = '';
      _promo.clear();
      _transcript = '';
    });
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _preview);
  }

  Future<void> _preview() async {
    final lines = _lines;
    if (lines.isEmpty) {
      if (!mounted) return;
      setState(() => _subtotal = _discount = _total = 0);
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await VoiceOrderService.preview(
        lines,
        promoCode: _promo.text.trim(),
        transcript: _transcript,
        notes: _notes,
      );
      if (!mounted) return;
      setState(() {
        _subtotal = d.subtotal;
        _discount = d.discount;
        _total = d.total;
        _couponMsg = d.couponMessage;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _subtotal = lines.fold<double>(0, (a, e) => a + e.quantity * e.price);
        _discount = 0;
        _total = _subtotal;
        _busy = false;
      });
      _toast(e.message, error: true);
    }
  }

  void _changeQty(VoiceItem it, int delta) {
    final next = it.quantity + delta;
    if (next < 1 || next > 9999) return;
    HapticFeedback.selectionClick();
    setState(() => it.quantity = next);
    _schedulePreview();
  }

  void _remove(VoiceItem it) {
    setState(() => _items.remove(it));
    if (_items.isEmpty) {
      _reset();
    } else {
      _schedulePreview();
    }
  }

  Future<VoiceProduct?> _pickProduct() => showModalBottomSheet<VoiceProduct>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _navy,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => const _ProductSearchSheet(),
      );

  Future<void> _assign(VoiceItem it) async {
    final p = await _pickProduct();
    if (p == null || !mounted) return;
    setState(() => it.assign(p));
    _schedulePreview();
  }

  Future<void> _addProduct() async {
    final p = await _pickProduct();
    if (p == null || !mounted) return;
    for (final e in _items) {
      if (e.productId == p.id) {
        _changeQty(e, 1);
        return;
      }
    }
    setState(() => _items.add(VoiceItem.fromProduct(p)));
    _schedulePreview();
  }

  /// Saves lines to the cart. [checkout] true -> open Checkout after.
  Future<void> _save({required bool checkout}) async {
    final lines = _lines;
    if (lines.isEmpty || _busy) return;
    _debounce?.cancel();
    setState(() => _busy = true);
    try {
      final msg =
          await VoiceOrderService.confirm(lines, promoCode: _promo.text.trim());
      if (!mounted) return;
      setState(() => _busy = false);
      if (checkout) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()),
        );
      } else {
        _toast(msg);
        _reset();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.message, error: true);
    }
  }

  Future<void> _close() async {
    if (_recording) await _cancelRecording();
    if (mounted) Navigator.of(context).maybePop();
  }

  /* -------------------------------- UI -------------------------------- */

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: !_recording,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _cancelRecording();
        },
        child: Scaffold(
          backgroundColor: _bg1,
          resizeToAvoidBottomInset: true,
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bg1, _bg2, _bg3],
                stops: [0, 0.5, 1],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _header(),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                          20, 20, 20, _hasResult ? 16 : 32),
                      children: [
                        _avatar(_hasResult ? 96 : 150),
                        const SizedBox(height: 16),
                        _speechPill(),
                        const SizedBox(height: 14),
                        const Text(
                          'How can I help you today?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFFCBD5E1),
                              letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 22),
                        _statusPill(),
                        const SizedBox(height: 22),
                        _micRow(),
                        const SizedBox(height: 14),
                        _tapAndTimer(),
                        const SizedBox(height: 18),
                        _uploadButton(),
                        if (_hasResult) ..._resultSection(),
                      ],
                    ),
                  ),
                  if (_hasResult) _bottomBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ----------------------------- header ----------------------------- */

  Widget _header() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: const Color(0xD9020716), // rgba(2,7,22,.85)
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.smart_toy_rounded, color: _cyan, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: 'ORDER',
                                style: TextStyle(color: Colors.white)),
                            TextSpan(
                                text: 'BOX', style: TextStyle(color: _blue)),
                          ]),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            height: 1.05,
                          ),
                        ),
                        const Text(
                          'by Ozie',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: _cyan,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x3300B0FF))),
                ),
                child: const Text(
                  '— AI VOICE ORDERING AGENT FOR RETAILERS —',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    color: _slate,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ----------------------------- avatar ----------------------------- */

  Widget _avatar(double size) {
    final outer = size + 26;
    return Center(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        child: SizedBox(
          width: outer,
          height: outer,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: _spin,
                child: CustomPaint(
                  size: Size(outer, outer),
                  painter: _RingPainter(),
                ),
              ),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF020716)],
                    ),
                    border: Border.all(color: _cyan, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: _cyan.withOpacity(0.35 + 0.45 * _pulse.value),
                        blurRadius: 18 + 22 * _pulse.value,
                      ),
                    ],
                  ),
                  child: child,
                ),
                child: Center(child: _robotFace(size * 0.62)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _robotFace(double s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: s * 0.1,
          height: s * 0.12,
          color: const Color(0xFFE2E8F0),
        ),
        Container(
          width: s * 0.16,
          height: s * 0.16,
          decoration: const BoxDecoration(color: _cyan, shape: BoxShape.circle),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: s * 0.1,
              height: s * 0.26,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Container(
              width: s,
              height: s * 0.74,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFCBD5E1)],
                ),
                borderRadius: BorderRadius.circular(s * 0.3),
              ),
              child: Center(
                child: Container(
                  width: s * 0.78,
                  height: s * 0.46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1B3F),
                    borderRadius: BorderRadius.circular(s * 0.2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _eye(s * 0.17),
                      _eye(s * 0.17),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: s * 0.1,
              height: s * 0.26,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _eye(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: _cyan,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: _cyan.withOpacity(0.8), blurRadius: 8)],
        ),
        child: Align(
          alignment: const Alignment(-0.35, -0.35),
          child: Container(
            width: d * 0.28,
            height: d * 0.28,
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      );

  Widget _speechPill() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
                color: Color(0x4000B0FF), blurRadius: 24, offset: Offset(0, 6)),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hi! I’m Ozie 👋',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF020617)),
            ),
            SizedBox(height: 2),
            Text(
              'Your Voice Agent',
              style: TextStyle(fontSize: 14, color: Color(0xFF334155)),
            ),
          ],
        ),
      ),
    );
  }

  /* ------------------------------ voice ------------------------------ */

  Widget _statusPill() {
    final String msg;
    if (_processing) {
      msg = 'Ozie is understanding your order…';
    } else if (_recording) {
      msg = 'Listening… tap the microphone again to stop';
    } else {
      msg = 'Tap the microphone and speak your order clearly (Hindi / Hinglish / English)';
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xE60F172A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x2638BDF8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _processing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _sky),
                  )
                : Icon(
                    _recording ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                    size: 16,
                    color: _sky,
                  ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: _slate, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eqBars({required bool mirror}) {
    return SizedBox(
      height: 52,
      child: AnimatedBuilder(
        animation: _wave,
        builder: (_, __) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(4, (i) {
              final idx = mirror ? 3 - i : i;
              final phase = (_wave.value + idx * 0.18) % 1.0;
              final s = math.sin(phase * 2 * math.pi).abs();
              final amp = _recording ? 36.0 : 8.0;
              return Container(
                width: 4,
                height: 10 + amp * s,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFA855F7), _cyan],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _micRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _eqBars(mirror: false),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _processing
              ? null
              : (_recording ? _stopAndProcess : _startRecording),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [_blue, Color(0xFF0040B0)],
                ),
                border: Border.all(color: _sky, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _sky.withOpacity(
                        (_recording ? 0.45 : 0.28) + 0.4 * _pulse.value),
                    blurRadius: 16 + 22 * _pulse.value,
                    spreadRadius: 1 + 3 * _pulse.value,
                  ),
                ],
              ),
              child: child,
            ),
            child: Center(
              child: _processing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        _eqBars(mirror: true),
      ],
    );
  }

  Widget _tapAndTimer() {
    return Column(
      children: [
        Text(
          _recording ? '👆 Tap to stop' : '👆 Tap to speak',
          style: const TextStyle(fontSize: 14, color: _slate),
        ),
        const SizedBox(height: 6),
        Text(
          '⏱️ ${_mmss(_seconds)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _sky,
            letterSpacing: 1,
            shadows: [Shadow(color: _sky, blurRadius: 12)],
          ),
        ),
      ],
    );
  }

  Widget _uploadButton() {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: (_processing || _recording) ? null : _pickAudioFile,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: const Text(
                '☁️  Upload Voice Note',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'WhatsApp voice notes supported (.opus, .ogg, .mp3, max 25MB)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: _slate),
        ),
      ],
    );
  }

  /* ------------------------------- result ------------------------------- */

  List<Widget> _resultSection() {
    final unmatched = _items.where((e) => !e.isMatched).length;
    return [
      const SizedBox(height: 22),
      Row(
        children: [
          const Icon(Icons.shopping_cart_outlined, color: _cyan, size: 18),
          const SizedBox(width: 8),
          const Text('Your voice order',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton(
            onPressed: _reset,
            child: const Text('Clear', style: TextStyle(color: _slate)),
          ),
        ],
      ),
      if (_notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Note: $_notes',
              style: const TextStyle(fontSize: 12, color: _slate)),
        ),
      if (unmatched > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x26FF8A00),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x66FF8A00)),
          ),
          child: Text(
            '$unmatched item${unmatched > 1 ? 's' : ''} could not be matched. Tap "Choose product" to fix.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFFDBA74)),
          ),
        ),
      for (final it in _items) _lineCard(it),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addProduct,
          icon: const Icon(Icons.add_rounded, color: _sky),
          label: const Text('Add product',
              style: TextStyle(color: _sky, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promo,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white),
              cursorColor: _cyan,
              decoration: InputDecoration(
                hintText: 'Promo code',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                isDense: true,
                filled: true,
                fillColor: const Color(0xF20F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x6600B0FF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x6600B0FF)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _preview,
            style: OutlinedButton.styleFrom(
              foregroundColor: _sky,
              side: const BorderSide(color: _sky),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
      if (_couponMsg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_couponMsg,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF34D399))),
        ),
    ];
  }

  Widget _thumb(VoiceItem it) {
    final url = it.imageUrl;
    final placeholder = Container(
      width: 60,
      height: 60,
      color: const Color(0xFFF1F5F9),
      child: const Icon(Icons.liquor_rounded, color: Color(0xFF94A3B8), size: 28),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.startsWith('http')
          ? Image.network(
              url,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            )
          : placeholder,
    );
  }

  Widget _badge(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600)),
      );

  Widget _lineCard(VoiceItem it) {
    final ok = it.isMatched;
    final badges = <String>[
      if (it.packingType.isNotEmpty) it.packingType,
      if (it.unitSize.isNotEmpty) it.unitSize,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: ok ? null : Border.all(color: const Color(0xFFFF8A00), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000), blurRadius: 15, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(it),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.displayName.isEmpty ? 'Unknown item' : it.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A)),
                    ),
                    if (ok && it.spoken.isNotEmpty && it.spoken != it.name)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('You said: ${it.spoken}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF64748B))),
                      ),
                    if (!ok && it.spoken.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Couldn’t match "${it.spoken}"',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFB45309))),
                      ),
                    if (ok && badges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [for (final b in badges) _badge(b)],
                        ),
                      ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _remove(it),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 20, color: Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!ok)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _assign(it),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ocean,
                  side: const BorderSide(color: _ocean),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Choose product'),
              ),
            )
          else
            Row(
              children: [
                _stepper(it),
                TextButton(
                  onPressed: () => _assign(it),
                  style: TextButton.styleFrom(
                      foregroundColor: _ocean,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${_inr(it.price)} / case',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _teal)),
                    Text('Total ${_inr(it.quantity * it.price)}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF64748B))),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stepper(VoiceItem it) {
    Widget btn(IconData i, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(i, size: 18, color: _ocean),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ocean, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, () => _changeQty(it, -1)),
          SizedBox(
            width: 32,
            child: Text('${it.quantity}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A))),
          ),
          btn(Icons.add_rounded, () => _changeQty(it, 1)),
        ],
      ),
    );
  }

  /* ----------------------------- bottom bar ----------------------------- */

  Widget _bottomBar() {
    final count = _lines.length;
    final canSave = count > 0 && !_busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00020716), Color(0xFF020716)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x6600B0FF)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Text('$count item${count == 1 ? '' : 's'} • Subtotal',
                        style: const TextStyle(fontSize: 13, color: _slate), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Flexible(child: Text(_inr(_subtotal),
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                if (_discount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x3310B981),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${_inr(_discount)} Savings applied',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF34D399))),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Grand Total',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    Flexible(child: Text(_inr(_total),
                        style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _gradBtn(
                  'Save to Cart',
                  const [Color(0xFF059669), Color(0xFF047857)],
                  canSave ? () => _save(checkout: false) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _gradBtn(
                  'Confirm & Checkout',
                  const [_blue, Color(0xFF0055CC)],
                  canSave ? () => _save(checkout: true) : null,
                  glow: true,
                  loading: _busy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gradBtn(String label, List<Color> colors, VoidCallback? onTap,
      {bool glow = false, bool loading = false}) {
    return Opacity(
      opacity: onTap == null && !loading ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onTap,
          child: Ink(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: colors),
              boxShadow: glow
                  ? const [
                      BoxShadow(color: Color(0x6600B0FF), blurRadius: 16),
                    ]
                  : null,
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(label,
                            maxLines: 1,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin rotating cyan ring around the avatar.
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0x0000B0FF), Color(0xFF38BDF8), Color(0x0000B0FF)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect.deflate(1), 0, math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bottom sheet: catalog search via action=search_products.
class _ProductSearchSheet extends StatefulWidget {
  const _ProductSearchSheet();

  @override
  State<_ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends State<_ProductSearchSheet> {
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  List<VoiceProduct> _results = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await VoiceOrderService.searchProducts(q.trim());
      if (!mounted || q != _q.text) return; // stale response
      setState(() {
        _results = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.75;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x4D94A3B8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _onChanged,
                style: const TextStyle(color: Colors.white),
                cursorColor: const Color(0xFF00B0FF),
                decoration: InputDecoration(
                  hintText: 'Search products',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF020716),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x6600B0FF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x6600B0FF)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Color(0xFF94A3B8))))
                      : _results.isEmpty
                          ? const Center(
                              child: Text('No products found',
                                  style: TextStyle(color: Color(0xFF94A3B8))))
                          : ListView.separated(
                              itemCount: _results.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 1, color: Color(0x1FFFFFFF)),
                              itemBuilder: (_, i) {
                                final p = _results[i];
                                return ListTile(
                                  title: Text(p.name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    [
                                      if (p.brand.isNotEmpty) p.brand,
                                      if (p.unitSize.isNotEmpty) p.unitSize,
                                    ].join(' • '),
                                    style: const TextStyle(
                                        color: Color(0xFF94A3B8)),
                                  ),
                                  trailing: Text(
                                    '₹${p.price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontWeight: FontWeight.w700),
                                  ),
                                  onTap: () => Navigator.of(context).pop(p),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}