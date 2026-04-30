import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/signal/pleth_quality.dart';

void main() {
  test('returns 0 PI before window is half-full', () {
    final q = PlethQualityWindow(windowSize: 100);
    for (var i = 0; i < 10; i++) {
      q.add(50);
    }
    expect(q.perfusionIndex(), 0);
    expect(q.isTrustworthy(), isFalse);
  });

  test('strong sine pleth → high PI', () {
    final q = PlethQualityWindow(windowSize: 240);
    for (var i = 0; i < 240; i++) {
      // mean ~50, AC ~30 peak-to-peak → PI ~60 %
      q.add((50 + 15 * sin(2 * pi * i / 60)).round());
    }
    final piValue = q.perfusionIndex();
    expect(piValue, greaterThan(50));
    expect(q.isTrustworthy(), isTrue);
    expect(q.qualityScore(), greaterThan(0.9));
  });

  test('flat pleth → low PI, untrustworthy', () {
    final q = PlethQualityWindow(windowSize: 240);
    for (var i = 0; i < 240; i++) {
      q.add(50);
    }
    final piValue = q.perfusionIndex();
    expect(piValue, lessThan(0.1));
    expect(q.isTrustworthy(), isFalse);
  });
}
