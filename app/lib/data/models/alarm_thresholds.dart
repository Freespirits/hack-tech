import 'package:meta/meta.dart';

import '../../signal/species_baselines.dart';

/// Per-pet alarm thresholds. Defaults derived from species baselines but
/// overridable per pet by the vet.
@immutable
class AlarmThresholds {
  const AlarmThresholds({
    required this.petId,
    required this.spo2Min,
    required this.hrMin,
    required this.hrMax,
    required this.tempMinC,
    required this.tempMaxC,
    required this.respMin,
    required this.respMax,
    required this.alarmBeep,
    required this.autoMonitor,
  });

  final String petId;
  final double spo2Min;
  final double hrMin;
  final double hrMax;
  final double tempMinC;
  final double tempMaxC;
  final double respMin;
  final double respMax;
  final bool alarmBeep;
  final bool autoMonitor;

  factory AlarmThresholds.defaults({
    required String petId,
    required SpeciesBaseline baseline,
  }) =>
      AlarmThresholds(
        petId: petId,
        spo2Min: baseline.spo2Percent.low,
        hrMin: baseline.heartRateBpm.low * 0.85,
        hrMax: baseline.heartRateBpm.high * 1.15,
        tempMinC: baseline.temperatureCelsius.low - 0.5,
        tempMaxC: baseline.temperatureCelsius.high + 0.5,
        respMin: baseline.respirationRateBpm.low,
        respMax: baseline.respirationRateBpm.high * 1.2,
        alarmBeep: true,
        autoMonitor: false,
      );

  Map<String, Object?> toJson() => {
        'pet_id': petId,
        'spo2_min': spo2Min,
        'hr_min': hrMin,
        'hr_max': hrMax,
        'temp_min_c': tempMinC,
        'temp_max_c': tempMaxC,
        'resp_min': respMin,
        'resp_max': respMax,
        'alarm_beep': alarmBeep,
        'auto_monitor': autoMonitor,
      };
}
