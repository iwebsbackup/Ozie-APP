import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Truck PNG cleaned for the map: background / halo / checkerboard around the
/// truck is made transparent and the image is cropped tight to the truck.
class TruckIcon {
  final Uint8List png;
  final int width;
  final int height;
  const TruckIcon(this.png, this.width, this.height);

  int get longestSide => width > height ? width : height;

  static final Map<String, Future<TruckIcon>> _cache = {};

  static Future<TruckIcon> load(String asset) =>
      _cache.putIfAbsent(asset, () => _build(asset));

  static Future<TruckIcon> _build(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();

    // decode (shrunk if huge, keeps flood-fill fast)
    var codec = await ui.instantiateImageCodec(bytes);
    var img = (await codec.getNextFrame()).image;
    if (img.width > 512) {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
      img = (await codec.getNextFrame()).image;
    }
    final w = img.width, h = img.height;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return TruckIcon(bytes, w, h);
    final px = Uint8List.fromList(bd.buffer.asUint8List());

    _removeBackground(px, w, h);

    // tight crop around what is left
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[(y * w + x) * 4 + 3] > 10) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return TruckIcon(bytes, w, h); // nothing left -> keep original
    const pad = 2;
    minX = (minX - pad).clamp(0, w - 1);
    minY = (minY - pad).clamp(0, h - 1);
    maxX = (maxX + pad).clamp(0, w - 1);
    maxY = (maxY + pad).clamp(0, h - 1);
    final cw = maxX - minX + 1, ch = maxY - minY + 1;
    final out = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      final src = ((minY + y) * w + minX) * 4;
      out.setRange(y * cw * 4, (y + 1) * cw * 4, px, src);
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(out, cw, ch, ui.PixelFormat.rgba8888, completer.complete);
    final cropped = await completer.future;
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return TruckIcon(bytes, w, h);
    return TruckIcon(png.buffer.asUint8List(), cw, ch);
  }

  /// Flood-fill from the border: every pixel connected to the edge that looks
  /// like the background colour(s) becomes transparent. Truck pixels inside
  /// are never touched. Handles plain, shadow and checkerboard backgrounds.
  static void _removeBackground(Uint8List px, int w, int h) {
    // 1) background colours = the most common colours on the border
    final hist = <int, int>{};
    final sums = <int, List<int>>{};
    void sample(int x, int y) {
      final i = (y * w + x) * 4;
      if (px[i + 3] < 20) return; // already transparent
      final key = ((px[i] >> 4) << 8) | ((px[i + 1] >> 4) << 4) | (px[i + 2] >> 4);
      hist[key] = (hist[key] ?? 0) + 1;
      final s = sums.putIfAbsent(key, () => [0, 0, 0]);
      s[0] += px[i];
      s[1] += px[i + 1];
      s[2] += px[i + 2];
    }

    var borderCount = 0;
    for (var x = 0; x < w; x++) {
      sample(x, 0);
      sample(x, h - 1);
      borderCount += 2;
    }
    for (var y = 1; y < h - 1; y++) {
      sample(0, y);
      sample(w - 1, y);
      borderCount += 2;
    }

    final keys = hist.keys.toList()..sort((a, b) => hist[b]!.compareTo(hist[a]!));
    final bg = <List<int>>[];
    for (final k in keys) {
      if (bg.length >= 4) break;
      if (hist[k]! < borderCount * 0.03) break;
      final s = sums[k]!, n = hist[k]!;
      bg.add([s[0] ~/ n, s[1] ~/ n, s[2] ~/ n]);
    }

    const tol = 38;
    bool isBg(int i) {
      if (px[i + 3] < 20) return true;
      for (final c in bg) {
        if ((px[i] - c[0]).abs() <= tol &&
            (px[i + 1] - c[1]).abs() <= tol &&
            (px[i + 2] - c[2]).abs() <= tol) {
          return true;
        }
      }
      return false;
    }

    // 2) flood from every border pixel that is background
    final seen = Uint8List(w * h);
    final q = Queue<int>();
    void push(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final p = y * w + x;
      if (seen[p] == 1) return;
      if (!isBg(p * 4)) return;
      seen[p] = 1;
      q.add(p);
    }

    for (var x = 0; x < w; x++) {
      push(x, 0);
      push(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      push(0, y);
      push(w - 1, y);
    }
    while (q.isNotEmpty) {
      final p = q.removeFirst();
      px[p * 4 + 3] = 0;
      final x = p % w, y = p ~/ w;
      push(x + 1, y);
      push(x - 1, y);
      push(x, y + 1);
      push(x, y - 1);
    }
  }
}