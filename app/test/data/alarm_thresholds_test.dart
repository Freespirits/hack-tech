import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/data/models/alarm_thresholds.dart';
import 'package:petvitals/signal/species_baselines.dart';

void main() {
  test('defaults derive sensible bounds from a dog baseline', () {
    final baseline = baselineFor(Species.dog, 22);
    final t = AlarmThresholds.defaults(petId: 'p1', baseline: baseline);
    expect(t.spo2Min, baseline.spo2Percent.low);
    // hrMin is 15 % below the species low.
    expect(t.hrMin, closeTo(baseline.heartRateBpm.low * 0.85, 1e-9));
    expect(t.hrMax, closeTo(baseline.heartRateBpm.high * 1.15, 1e-9));
    expect(t.tempMinC, lessThan(baseline.temperatureCelsius.low));
    expect(t.tempMaxC, greaterThan(baseline.temperatureCelsius.high));
    expect(t.alarmBeep, isTrue);
    expect(t.autoMonitor, isFalse);
  });

  test('cat thresholds reflect higher resting HR', () {
    final baseline = baselineFor(Species.cat, 4);
    final t = AlarmThresholds.defaults(petId: 'p2', baseline: baseline);
    expect(t.hrMax, greaterThan(200));
    expect(t.hrMin, greaterThan(80));
  });
}
