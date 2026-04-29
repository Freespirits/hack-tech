import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/signal/hrv.dart';
import 'package:petvitals/signal/pan_tompkins.dart';

QrsDetection beat(int seconds, [int millis = 0, double conf = 0.9]) =>
    QrsDetection(
      sampleIndex: seconds * 250 + (millis * 250 ~/ 1000),
      timestamp:
          DateTime(2026, 1, 1).add(Duration(seconds: seconds, milliseconds: millis)),
      confidence: conf,
    );

void main() {
  test('mean HR of perfectly regular 60 BPM is 60.0', () {
    final beats = <QrsDetection>[
      for (var i = 0; i < 30; i++) beat(i),
    ];
    final hrv = HrvCalculator().compute(beats);
    expect(hrv.meanHrBpm, closeTo(60.0, 0.5));
    expect(hrv.beatCount, 30);
    expect(hrv.rmssdMs, closeTo(0, 1e-9));
    expect(hrv.sdnnMs, closeTo(0, 1e-9));
    expect(hrv.pnn50, 0);
  });

  test('alternating 800 ms / 1200 ms RRs give RMSSD = 400 ms', () {
    final beats = <QrsDetection>[];
    var t = DateTime(2026, 1, 1);
    beats.add(QrsDetection(sampleIndex: 0, timestamp: t, confidence: 0.9));
    var alt = true;
    for (var i = 1; i < 21; i++) {
      t = t.add(Duration(milliseconds: alt ? 800 : 1200));
      alt = !alt;
      beats.add(QrsDetection(sampleIndex: i, timestamp: t, confidence: 0.9));
    }
    final hrv = HrvCalculator().compute(beats);
    expect(hrv.rmssdMs, closeTo(400, 1));
    expect(hrv.pnn50, closeTo(1.0, 1e-9));
  });

  test('low-confidence beats are excluded', () {
    final good = QrsDetection(
      sampleIndex: 0,
      timestamp: DateTime(2026),
      confidence: 0.9,
    );
    final bad = QrsDetection(
      sampleIndex: 1,
      timestamp: DateTime(2026).add(const Duration(milliseconds: 500)),
      confidence: 0.2,
    );
    final hrv = HrvCalculator().compute(<QrsDetection>[good, bad]);
    expect(hrv.beatCount, 0); // dropped by confidence filter
  });

  test('RR outside [200, 2000] ms is excluded', () {
    final beats = <QrsDetection>[
      QrsDetection(
          sampleIndex: 0, timestamp: DateTime(2026), confidence: 0.9),
      QrsDetection(
          sampleIndex: 1,
          timestamp: DateTime(2026).add(const Duration(milliseconds: 100)),
          confidence: 0.9),
    ];
    final hrv = HrvCalculator().compute(beats);
    expect(hrv.beatCount, 0);
  });
}
