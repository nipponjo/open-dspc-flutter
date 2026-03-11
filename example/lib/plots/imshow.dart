import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';

double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

Uint8List viridisRgb(double t) {
  t = _clamp01(t);

  final r = _clamp01(
    0.280268003 + t * (0.230519 + t * (-0.143510 + t * 0.044824)),
  );

  final g = _clamp01(
    0.165368003 + t * (0.504129 + t * (-0.148000 + t * 0.030000)),
  );

  final b = _clamp01(
    0.476031 + t * (-0.906000 + t * (1.090000 + t * -0.365000)),
  );

  return Uint8List.fromList([
    (255 * r).round(),
    (255 * g).round(),
    (255 * b).round(),
  ]);
}

Future<ui.Image> stftToImage(
  List<Float32List> frames, {
  double? minDb,
  double? maxDb,
}) async {
  if (frames.isEmpty) throw StateError('No frames');
  final height = frames.first.length; // bins (frequency)
  final width = frames.length; // time frames
  for (final frame in frames) {
    if (frame.length != height) {
      throw ArgumentError('All frames must have equal bin count');
    }
  }

  var lo = minDb ?? double.infinity;
  var hi = maxDb ?? double.negativeInfinity;
  if (minDb == null || maxDb == null) {
    for (final frame in frames) {
      for (var i = 0; i < frame.length; i++) {
        final v = frame[i];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
  }
  if (!lo.isFinite || !hi.isFinite || lo == hi) {
    lo = lo.isFinite ? lo : -120.0;
    hi = hi.isFinite ? hi : 0.0;
    if (lo == hi) hi = lo + 1.0;
  }

  final pixels = Uint8List(width * height * 4);
  final scale = 1.0 / (hi - lo);

  // imshow default: origin='upper' => low freq at bottom usually looks nicer
  // We'll flip vertically so bin 0 is at bottom.
  for (int x = 0; x < width; x++) {
    final col = frames[x];
    for (int y = 0; y < height; y++) {
      final vDb = col[y];
      var t = (vDb - lo) * scale;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
      final rgbList = viridisRgb(t);

      final yy = (height - 1 - y); // flip
      final idx = (yy * width + x) * 4;
      pixels[idx + 0] = rgbList.elementAt(0); // R
      pixels[idx + 1] = rgbList.elementAt(1); // G
      pixels[idx + 2] = rgbList.elementAt(2); // B
      pixels[idx + 3] = 255; // A
    }
  }

  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (img) => c.complete(img),
  );
  return c.future;
}

class StftView extends StatelessWidget {
  final ui.Image image;
  const StftView(this.image, {super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ImagePainter(image),
      size: Size(image.width.toDouble(), image.height.toDouble()),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image img;
  _ImagePainter(this.img);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(img, src, dst, Paint());
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) =>
      oldDelegate.img != img;
}
