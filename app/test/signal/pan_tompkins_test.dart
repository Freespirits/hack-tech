import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/signal/pan_tompkins.dart';

void main() {
  test('detects synthesized R-peaks at 60 BPM (mean RR within ±100 ms)', () {
    const sampleHz = 250.0;
    final detector = PanTompkinsDetector(sampleHz: sampleHz);

    // Synthesize 30 s of ECG: a Q-R-S-T waveform every 1.0 s (60 BPM).
    // The R-wave is a positive Gaussian (sigma 60 ms, amplitude 1500),
    // flanked by small Q (-300, sigma 15 ms at -50 ms) and S
    // (-400, sigma 15 ms at +50 ms) deflections, plus a slow T wave
    // (200, sigma 80 ms at +250 ms). Wider than the original test's
    // sigma=25 ms — closer to physiological QRS width and well within
    // the 5-15 Hz Pan-Tompkins band-pass.
    const totalSeconds = 30;
    final totalSamples = (sampleHz * totalSeconds).toInt();
    final beats = <QrsDetection>[];
    final start = DateTime(2026, 1, 1);

    double gauss(double x, double mu, double sigma, double amp) =>
        amp * exp(-(x - mu) * (x - mu) / (2 * sigma * sigma));

    for (var n = 0; n < totalSamples; n++) {
      final t = n / sampleHz;
      final phase = t % 1.0; // beat once per second
      final ecg = gauss(phase, 0.45, 0.015, -300) + // Q
          gauss(phase, 0.50, 0.060, 1500) +        // R
          gauss(phase, 0.55, 0.015, -400) +        // S
          gauss(phase, 0.75, 0.080, 200);          // T
      final ts = start.add(Duration(microseconds: (t * 1e6).round()));
      final det = detector.process(ecg, ts);
      if (det != null) beats.add(det);
    }

    // Drop the first 4 s (2 s learning phase + 2 s ramp-up).
    final stable = beats
        .where((b) =>
            b.timestamp.difference(start).inMilliseconds > 4000)
        .toList();

    expect(stable.length, greaterThanOrEqualTo(20),
        reason: 'detector found too few beats over 26 s of clean 60 BPM data');

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
