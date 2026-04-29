import 'package:meta/meta.dart';

/// A single waveform-sample row persisted to SQLite.
///
/// Waveforms are written as int16 batches into a `waveform_chunks`
/// table rather than one row per sample — but the in-memory
/// representation here is what the signal layer consumes.
@immutable
class WaveformChunk {
  const WaveformChunk({
    required this.sessionId,
    required this.kind,
    required this.startedAt,
    required this.sampleHz,
    required this.samples,
  });

  final String sessionId;
  final WaveformKind kind;
  final DateTime startedAt;
  final double sampleHz;
  final List<int> samples;
}

enum WaveformKind { ecg, pleth, respiration }

/// A discrete vital reading (HR / SpO2 / Temp / NIBP / Battery).
@immutable
class VitalReading {
  const VitalReading({
    required this.sessionId,
    required this.timestamp,
    required this.kind,
    required this.value,
    this.secondaryValue,
    this.tertiaryValue,
  });

  final String sessionId;
  final DateTime timestamp;
  final VitalKind kind;
  final double value;
  final double? secondaryValue; // e.g. NIBP diastolic
  final double? tertiaryValue;  // e.g. NIBP MAP
}

enum VitalKind {
  heartRate,
  pulseRate,
  spo2,
  temperatureC,
  respirationRate,
  nibp,
  batteryPercent,
  perfusionIndex,
}
