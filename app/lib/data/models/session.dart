import 'package:meta/meta.dart';

/// A single monitoring session for one pet — start to stop.
@immutable
class MonitoringSession {
  const MonitoringSession({
    required this.id,
    required this.petId,
    required this.clinicId,
    required this.startedAt,
    required this.endedAt,
    required this.startedBy,
    required this.notes,
    required this.deviceId,
    required this.deviceName,
    required this.summary,
  });

  final String id;
  final String petId;
  final String clinicId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String startedBy;
  final String notes;
  final String deviceId;
  final String deviceName;
  final SessionSummary summary;

  Duration? get duration =>
      endedAt == null ? null : endedAt!.difference(startedAt);

  bool get isOngoing => endedAt == null;

  Map<String, Object?> toJson() => {
        'id': id,
        'pet_id': petId,
        'clinic_id': clinicId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'started_by': startedBy,
        'notes': notes,
        'device_id': deviceId,
        'device_name': deviceName,
        'summary': summary.toJson(),
      };
}

/// The aggregated stats over a session — used for fast list rendering and
/// also serialized into the AI insight prompt.
@immutable
class SessionSummary {
  const SessionSummary({
    required this.minHr,
    required this.maxHr,
    required this.meanHr,
    required this.minSpo2,
    required this.maxSpo2,
    required this.meanSpo2,
    required this.minTempC,
    required this.maxTempC,
    required this.meanTempC,
    required this.respMean,
    required this.nibpSystolic,
    required this.nibpDiastolic,
    required this.nibpMean,
    required this.beatCount,
    required this.rmssdMs,
    required this.sdnnMs,
    required this.signalQuality,
    required this.alarmTriggers,
  });

  final double? minHr;
  final double? maxHr;
  final double? meanHr;
  final double? minSpo2;
  final double? maxSpo2;
  final double? meanSpo2;
  final double? minTempC;
  final double? maxTempC;
  final double? meanTempC;
  final double? respMean;
  final int? nibpSystolic;
  final int? nibpDiastolic;
  final int? nibpMean;
  final int beatCount;
  final double rmssdMs;
  final double sdnnMs;

  /// 0–1, mean pleth perfusion-index quality across the session.
  final double signalQuality;

  /// Per-vital count of how many alarm thresholds the session breached.
  final Map<String, int> alarmTriggers;

  static const empty = SessionSummary(
    minHr: null,
    maxHr: null,
    meanHr: null,
    minSpo2: null,
    maxSpo2: null,
    meanSpo2: null,
    minTempC: null,
    maxTempC: null,
    meanTempC: null,
    respMean: null,
    nibpSystolic: null,
    nibpDiastolic: null,
    nibpMean: null,
    beatCount: 0,
    rmssdMs: 0,
    sdnnMs: 0,
    signalQuality: 0,
    alarmTriggers: <String, int>{},
  );

  Map<String, Object?> toJson() => {
        'min_hr': minHr,
        'max_hr': maxHr,
        'mean_hr': meanHr,
        'min_spo2': minSpo2,
        'max_spo2': maxSpo2,
        'mean_spo2': meanSpo2,
        'min_temp_c': minTempC,
        'max_temp_c': maxTempC,
        'mean_temp_c': meanTempC,
        'resp_mean': respMean,
        'nibp_systolic': nibpSystolic,
        'nibp_diastolic': nibpDiastolic,
        'nibp_mean': nibpMean,
        'beat_count': beatCount,
        'rmssd_ms': rmssdMs,
        'sdnn_ms': sdnnMs,
        'signal_quality': signalQuality,
        'alarm_triggers': alarmTriggers,
      };
}
