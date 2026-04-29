/// Per-species reference ranges for vitals.
///
/// Sources: Plumb's Veterinary Drug Handbook (10th ed., 2023);
/// Côté's _Clinical Veterinary Advisor: Dogs and Cats_ (4th ed., 2020);
/// AAHA 2020 Anesthesia and Monitoring Guidelines.
///
/// These ranges drive (a) default alarm thresholds for new pets and
/// (b) anomaly-vs-baseline copy in the AI insight prompts. They are
/// **defaults** — every pet's profile in the DB also has a per-pet
/// override row in `alarm_thresholds`.
library;

import 'package:meta/meta.dart';

enum Species { dog, cat, rabbit, ferret, otherSmallMammal }

enum SizeBand { tiny, small, medium, large, giant }

@immutable
class VitalRange {
  const VitalRange({required this.low, required this.high});
  final double low;
  final double high;

  bool contains(double v) => v >= low && v <= high;

  /// 0 = inside range, +/- z-score-ish distance outside.
  double deviation(double v) {
    if (v < low) return (v - low) / (high - low);
    if (v > high) return (v - high) / (high - low);
    return 0;
  }
}

@immutable
class SpeciesBaseline {
  const SpeciesBaseline({
    required this.species,
    required this.size,
    required this.heartRateBpm,
    required this.respirationRateBpm,
    required this.temperatureCelsius,
    required this.spo2Percent,
    required this.systolicMmHg,
    required this.diastolicMmHg,
    required this.meanArterialMmHg,
  });

  final Species species;
  final SizeBand size;
  final VitalRange heartRateBpm;
  final VitalRange respirationRateBpm;
  final VitalRange temperatureCelsius;
  final VitalRange spo2Percent;
  final VitalRange systolicMmHg;
  final VitalRange diastolicMmHg;
  final VitalRange meanArterialMmHg;
}

/// Pick a sensible default size band from species + adult body weight (kg).
SizeBand sizeBandFor(Species species, double weightKg) {
  switch (species) {
    case Species.dog:
      if (weightKg < 5) return SizeBand.tiny;
      if (weightKg < 15) return SizeBand.small;
      if (weightKg < 30) return SizeBand.medium;
      if (weightKg < 45) return SizeBand.large;
      return SizeBand.giant;
    case Species.cat:
      if (weightKg < 3) return SizeBand.tiny;
      if (weightKg < 5) return SizeBand.small;
      return SizeBand.medium;
    case Species.rabbit:
    case Species.ferret:
    case Species.otherSmallMammal:
      return SizeBand.tiny;
  }
}

const Map<(Species, SizeBand), SpeciesBaseline> kSpeciesBaselines = {
  (Species.dog, SizeBand.tiny): SpeciesBaseline(
    species: Species.dog,
    size: SizeBand.tiny,
    heartRateBpm: VitalRange(low: 90, high: 160),
    respirationRateBpm: VitalRange(low: 18, high: 34),
    temperatureCelsius: VitalRange(low: 38.0, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 110, high: 160),
    diastolicMmHg: VitalRange(low: 60, high: 100),
    meanArterialMmHg: VitalRange(low: 80, high: 120),
  ),
  (Species.dog, SizeBand.small): SpeciesBaseline(
    species: Species.dog,
    size: SizeBand.small,
    heartRateBpm: VitalRange(low: 80, high: 140),
    respirationRateBpm: VitalRange(low: 16, high: 30),
    temperatureCelsius: VitalRange(low: 38.0, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 110, high: 160),
    diastolicMmHg: VitalRange(low: 60, high: 100),
    meanArterialMmHg: VitalRange(low: 80, high: 120),
  ),
  (Species.dog, SizeBand.medium): SpeciesBaseline(
    species: Species.dog,
    size: SizeBand.medium,
    heartRateBpm: VitalRange(low: 70, high: 130),
    respirationRateBpm: VitalRange(low: 14, high: 28),
    temperatureCelsius: VitalRange(low: 38.0, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 110, high: 160),
    diastolicMmHg: VitalRange(low: 60, high: 100),
    meanArterialMmHg: VitalRange(low: 80, high: 120),
  ),
  (Species.dog, SizeBand.large): SpeciesBaseline(
    species: Species.dog,
    size: SizeBand.large,
    heartRateBpm: VitalRange(low: 60, high: 110),
    respirationRateBpm: VitalRange(low: 12, high: 24),
    temperatureCelsius: VitalRange(low: 38.0, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 110, high: 160),
    diastolicMmHg: VitalRange(low: 60, high: 100),
    meanArterialMmHg: VitalRange(low: 80, high: 120),
  ),
  (Species.dog, SizeBand.giant): SpeciesBaseline(
    species: Species.dog,
    size: SizeBand.giant,
    heartRateBpm: VitalRange(low: 50, high: 100),
    respirationRateBpm: VitalRange(low: 10, high: 22),
    temperatureCelsius: VitalRange(low: 37.8, high: 39.0),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 110, high: 160),
    diastolicMmHg: VitalRange(low: 60, high: 100),
    meanArterialMmHg: VitalRange(low: 80, high: 120),
  ),
  (Species.cat, SizeBand.tiny): SpeciesBaseline(
    species: Species.cat,
    size: SizeBand.tiny,
    heartRateBpm: VitalRange(low: 140, high: 220),
    respirationRateBpm: VitalRange(low: 20, high: 40),
    temperatureCelsius: VitalRange(low: 38.1, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 120, high: 170),
    diastolicMmHg: VitalRange(low: 70, high: 120),
    meanArterialMmHg: VitalRange(low: 90, high: 130),
  ),
  (Species.cat, SizeBand.small): SpeciesBaseline(
    species: Species.cat,
    size: SizeBand.small,
    heartRateBpm: VitalRange(low: 130, high: 200),
    respirationRateBpm: VitalRange(low: 20, high: 40),
    temperatureCelsius: VitalRange(low: 38.1, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 120, high: 170),
    diastolicMmHg: VitalRange(low: 70, high: 120),
    meanArterialMmHg: VitalRange(low: 90, high: 130),
  ),
  (Species.cat, SizeBand.medium): SpeciesBaseline(
    species: Species.cat,
    size: SizeBand.medium,
    heartRateBpm: VitalRange(low: 120, high: 180),
    respirationRateBpm: VitalRange(low: 18, high: 36),
    temperatureCelsius: VitalRange(low: 38.1, high: 39.2),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 120, high: 170),
    diastolicMmHg: VitalRange(low: 70, high: 120),
    meanArterialMmHg: VitalRange(low: 90, high: 130),
  ),
  (Species.rabbit, SizeBand.tiny): SpeciesBaseline(
    species: Species.rabbit,
    size: SizeBand.tiny,
    heartRateBpm: VitalRange(low: 130, high: 325),
    respirationRateBpm: VitalRange(low: 30, high: 60),
    temperatureCelsius: VitalRange(low: 38.5, high: 40.0),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 92, high: 135),
    diastolicMmHg: VitalRange(low: 64, high: 90),
    meanArterialMmHg: VitalRange(low: 80, high: 110),
  ),
  (Species.ferret, SizeBand.tiny): SpeciesBaseline(
    species: Species.ferret,
    size: SizeBand.tiny,
    heartRateBpm: VitalRange(low: 180, high: 250),
    respirationRateBpm: VitalRange(low: 33, high: 36),
    temperatureCelsius: VitalRange(low: 37.8, high: 40.0),
    spo2Percent: VitalRange(low: 95, high: 100),
    systolicMmHg: VitalRange(low: 95, high: 155),
    diastolicMmHg: VitalRange(low: 51, high: 87),
    meanArterialMmHg: VitalRange(low: 70, high: 110),
  ),
};

SpeciesBaseline baselineFor(Species species, double weightKg) {
  final size = sizeBandFor(species, weightKg);
  return kSpeciesBaselines[(species, size)] ??
      kSpeciesBaselines[(species, SizeBand.medium)] ??
      kSpeciesBaselines[(Species.dog, SizeBand.medium)]!;
}
