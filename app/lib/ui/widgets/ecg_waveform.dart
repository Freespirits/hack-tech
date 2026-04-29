/// Live ECG waveform painter.
///
/// Uses a ring-buffer of the last `windowSeconds` samples and a custom
/// painter to keep redraws cheap (no full re-layout per sample, no
/// per-sample widget). Sweeps left-to-right.
library;

import 'dart:math';

import 'package:flutter/material.dart';

class EcgWaveformPainter extends CustomPainter {
  EcgWaveformPainter({
    required this.samples,
    required this.sampleHz,
    required this.windowSeconds,
    required this.color,
    required this.gridColor,
    this.maxAbsMicroVolts = 2500,
  });

  /// Most-recent samples first.
  final List<int> samples;
  final double sampleHz;
  final double windowSeconds;
  final Color color;
  final Color gridColor;
  final double maxAbsMicroVolts;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    if (samples.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..isAntiAlias = true;

    final path = Path();
    final maxSamples = min(
      samples.length,
      (windowSeconds * sampleHz).floor(),
    );
    final dx = size.width / max(1, maxSamples - 1);
    final mid = size.height / 2;
    final scale = (size.height / 2) / maxAbsMicroVolts;

    for (var i = 0; i < maxSamples; i++) {
      final v = samples[i].toDouble().clamp(
            -maxAbsMicroVolts,
            maxAbsMicroVolts,
          );
      final x = i * dx;
      final y = mid - v * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    final tickHorizontal = size.width / 10;
    final tickVertical = size.height / 6;
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(tickHorizontal * i, 0),
        Offset(tickHorizontal * i, size.height),
        paint,
      );
    }
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(
        Offset(0, tickVertical * i),
        Offset(size.width, tickVertical * i),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant EcgWaveformPainter old) =>
      old.samples != samples;
}

class EcgWaveform extends StatelessWidget {
  const EcgWaveform({
    super.key,
    required this.samples,
    required this.sampleHz,
    this.windowSeconds = 6,
    this.color = const Color(0xFF16A34A),
    this.gridColor = const Color(0x331F2937),
  });

  final List<int> samples;
  final double sampleHz;
  final double windowSeconds;
  final Color color;
  final Color gridColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: EcgWaveformPainter(
          samples: samples,
          sampleHz: sampleHz,
          windowSeconds: windowSeconds,
          color: color,
          gridColor: gridColor,
        ),
        size: Size.infinite,
      ),
    );
  }
}
