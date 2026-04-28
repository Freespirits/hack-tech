import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/signal/species_baselines.dart';

void main() {
  test('size band is correct for canonical weights', () {
    expect(sizeBandFor(Species.dog, 2), SizeBand.tiny);
    expect(sizeBandFor(Species.dog, 10), SizeBand.small);
    expect(sizeBandFor(Species.dog, 22), SizeBand.medium);
    expect(sizeBandFor(Species.dog, 35), SizeBand.large);
    expect(sizeBandFor(Species.dog, 60), SizeBand.giant);

    expect(sizeBandFor(Species.cat, 2), SizeBand.tiny);
    expect(sizeBandFor(Species.cat, 4), SizeBand.small);
    expect(sizeBandFor(Species.cat, 7), SizeBand.medium);
  });

  test('VitalRange.contains and deviation', () {
    const r = VitalRange(low: 60, high: 120);
    expect(r.contains(80), isTrue);
    expect(r.contains(50), isFalse);
    expect(r.deviation(120), closeTo(0, 1e-9));
    expect(r.deviation(150), closeTo(0.5, 1e-9));
    expect(r.deviation(30), closeTo(-0.5, 1e-9));
  });

  test('baselineFor returns species-appropriate ranges', () {
    final dog = baselineFor(Species.dog, 22);
    expect(dog.heartRateBpm.contains(100), isTrue);
    final cat = baselineFor(Species.cat, 4);
    expect(cat.heartRateBpm.contains(180), isTrue);
    expect(cat.heartRateBpm.contains(80), isFalse);
  });
}
