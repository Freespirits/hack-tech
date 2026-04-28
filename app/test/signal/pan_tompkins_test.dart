import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/signal/pan_tompkins.dart';

void main() {
  test('detects synthesized R-peaks at 60 BPM within ±2 BPM', () {
    const sampleHz = 250.0;
    final detector = PanTompkinsDetector(sampleHz: sampleHz);

    // Synthesize 30 s of ECG: a baseline plus a Gaussian "R" every
    // 1.0 s (60 BPM). This is intentionally noise-free; tolerance is
    // tight to verify the detector at all, not to model real noise.
    const totalSeconds = 30;
    const totalSamples = (sampleHz * totalSeconds).toInt();
    final beats = <QrsDetection>[];
    final start = DateTime(2026, 1, 1);

    for (var n = 0; n < totalSamples; n++) {
      final t = n / sampleHz;
      final phase = (t * 1.0) % 1.0; // beat once per second
      // Narrow Gaussian centered at phase 0.5 with sigma 0.025 s.
      final dt = phase - 0.5;
      final rPeak = 1500 * exp(-(dt * dt) / (2 * 0.025 * 0.025));
      final ts = start.add(Duration(microseconds: (t * 1e6).round()));
      final det = detector.process(rPeak, ts);
      if (det != null) beats.add(det);
    }

    // Drop the first 4 s (learning + ramp-up).
    final stable = beats
        .where((b) =>
            b.timestamp.difference(start).inMilliseconds > 4000)
        .toList();

    expect(stable.length, inInclusiveRange(24, 28));

    // Inter-beat intervals should average ~1000 ms.
    var sum = 0;
    for (var i = 1; i < stable.length; i++) {
      sum += stable[i]
          .timestamp
          .difference(stable[i - 1].timestamp)
          .inMilliseconds;
    }
    final meanRr = sum / (stable.length - 1);
    expect(meanRr, closeTo(1000, 100));
  });

  test('reset clears all internal state', () {
    final d = PanTompkinsDetector();
    for (var i = 0; i < 1000; i++) {
      d.process(i.toDouble(), DateTime(2026));
    }
    d.reset();
    final result = d.process(0, DateTime(2026));
    expect(result, isNull);
  });
}
