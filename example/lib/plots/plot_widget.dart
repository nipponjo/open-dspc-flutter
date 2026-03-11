import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class PlotWidget extends StatelessWidget {
  final Float32List y;
  final double? width;
  final double? height;
  final String xLabel;
  final String yLabel;

  const PlotWidget({
    super.key,
    required this.y,
    this.width,
    this.height,
    this.xLabel = '',
    this.yLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 400,
      height: height ?? 250,
      child: CustomPaint(
        painter: _AxesPlotPainter(
          y: y,
          xLabel: xLabel,
          yLabel: yLabel,
          textStyle: Theme.of(context).textTheme.bodySmall!,
        ),
      ),
    );
  }
}

class _AxesPlotPainter extends CustomPainter {
  final Float32List y;
  final String xLabel;
  final String yLabel;
  final TextStyle textStyle;

  _AxesPlotPainter({
    required this.y,
    required this.xLabel,
    required this.yLabel,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (y.isEmpty) return;

    const leftMargin = 50.0;
    const bottomMargin = 35.0;
    const topMargin = 15.0;
    const rightMargin = 15.0;

    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;

    final plotRect = Rect.fromLTWH(
      leftMargin,
      topMargin,
      plotWidth,
      plotHeight,
    );

    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw border
    canvas.drawRect(plotRect, axisPaint);

    // Compute min/max
    double minY = y.first.toDouble();
    double maxY = y.first.toDouble();
    for (final v in y) {
      final d = v.toDouble();
      if (d < minY) minY = d;
      if (d > maxY) maxY = d;
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    // ---------- Draw X ticks ----------
    const xTicks = 6;
    for (int i = 0; i <= xTicks; i++) {
      final t = i / xTicks;
      final x = plotRect.left + t * plotWidth;

      // Tick line
      canvas.drawLine(
        Offset(x, plotRect.bottom),
        Offset(x, plotRect.bottom + 5),
        axisPaint,
      );

      // Label
      final value = (t * (y.length - 1)).toStringAsFixed(0);
      _drawText(canvas, value, Offset(x - 10, plotRect.bottom + 8));
    }

    // ---------- Draw Y ticks ----------
    const yTicks = 5;
    for (int i = 0; i <= yTicks; i++) {
      final t = i / yTicks;
      final yPos = plotRect.bottom - t * plotHeight;

      canvas.drawLine(
        Offset(plotRect.left - 5, yPos),
        Offset(plotRect.left, yPos),
        axisPaint,
      );

      final value = (minY + t * (maxY - minY)).toStringAsFixed(2);

      _drawText(canvas, value, Offset(2, yPos - 6));
    }

    // ---------- Draw axis labels ----------
    _drawText(
      canvas,
      xLabel,
      Offset(plotRect.left + plotWidth / 2 - 20, size.height - 20),
    );

    _drawTextRotated(canvas, yLabel, Offset(15, plotRect.top + plotHeight / 2));

    // ---------- Draw data curve ----------
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    bool first = true;

    final stride = (y.length / plotWidth).ceil().clamp(1, y.length);

    for (int i = 0; i < y.length; i += stride) {
      final xNorm = i / (y.length - 1);
      final yNorm = (y[i] - minY) / (maxY - minY);

      final x = plotRect.left + xNorm * plotWidth;
      final yCanvas = plotRect.bottom - yNorm * plotHeight;

      if (first) {
        path.moveTo(x, yCanvas);
        first = false;
      } else {
        path.lineTo(x, yCanvas);
      }
    }

    canvas.drawPath(path, linePaint);
  }

  void _drawText(Canvas canvas, String text, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, offset);
  }

  void _drawTextRotated(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AxesPlotPainter oldDelegate) {
    return oldDelegate.y != y;
  }
}
