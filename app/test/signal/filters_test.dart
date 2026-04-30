import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/signal/filters.dart';

void main() {
  group('HighPassFilter', () {
    test('attenuates DC', () {
      final hp = HighPassFilter(cutoffHz: 1, sampleHz: 250);
      var last = 0.0;
      for (var i = 0; i < 1000; i++) {
        last = hp.process(5);
      }
      expect(last.abs(), lessThan(0.1));
    });

    test('passes a 10 Hz sine when cutoff is 1 Hz', () {
      final hp = HighPassFilter(cutoffHz: 1, sampleHz: 250);
      var maxAmp = 0.0;
      for (var i = 0; i < 1000; i++) {
        final v = sin(2 * pi * 10 * i / 250);
        final out = hp.process(v);
        if (i > 200 && out.abs() > maxAmp) maxAmp = out.abs();
      }
      expect(maxAmp, greaterThan(0.7));
    });
  });

  group('LowPassFilter', () {
    test('attenuates a 50 Hz sine when cutoff is 5 Hz', () {
      final lp = LowPassFilter(cutoffHz: 5, sampleHz: 250);
      var maxAmp = 0.0;
      for (var i = 0; i < 1000; i++) {
        final v = sin(2 * pi * 50 * i / 250);
        final out = lp.process(v);
        if (i > 200 && out.abs() > maxAmp) maxAmp = out.abs();
      }
      expect(maxAmp, lessThan(0.3));
    });
  });

  group('MovingAverage', () {
    test('mean of constant equals the constant', () {
      final ma = MovingAverage(8);
      double last = 0;
      for (var i = 0; i < 100; i++) {
        last = ma.process(7);
      }
      expect(last, closeTo(7, 1e-9));
    });

    test('reset clears state', () {
      final ma = MovingAverage(4);
      for (var i = 0; i < 10; i++) {
        ma.process(100);
      }
      ma.reset();
      expect(ma.process(0), closeTo(0, 1e-9));
    });
  });

  test('FiveTapDifferentiator produces zero on a constant', () {
    final d = FiveTapDifferentiator();
    double last = 0;
    for (var i = 0; i < 10; i++) {
      last = d.process(42);
    }
    expect(last, closeTo(0, 1e-9));
  });
}
