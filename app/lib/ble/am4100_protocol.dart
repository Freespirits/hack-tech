/// AM4100 wire protocol — frame parser.
///
/// The AM4100 sends two coexisting frame families over the Microchip
/// Transparent UART notify characteristic:
///
/// 1. **Single-parameter SpO₂ frames (BCI Protocol v1.2)** — 5 bytes,
///    sync bit on byte 0 (high bit set). Carries pleth waveform sample,
///    pulse rate and SpO₂. This is the same format used by the
///    BM1000-BT and documented in `zh2x/BCI_Protocol`.
///
/// 2. **Multi-parameter frames** — variable length, framed as
///    `0xAA <type> <len> <payload…> <checksum>`, used for ECG bursts,
///    respiration, NIBP, temperature and battery on the AM4100/AM6100.
///
/// The byte stream that arrives over BLE is **not** packet-aligned — a
/// single notify can contain part of one frame plus the start of the next,
/// or several BCI frames back-to-back. The [Am4100FrameDecoder] handles
/// reassembly and feeds parsed [Am4100Reading]s through [readings].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A single parsed sample/parameter update from the AM4100.
@immutable
sealed class Am4100Reading {
  const Am4100Reading(this.timestamp);
  final DateTime timestamp;
}

/// Pulse-oximeter snapshot (every BCI frame, ~60 Hz).
class SpO2Reading extends Am4100Reading {
  const SpO2Reading({
    required DateTime timestamp,
    required this.plethSample,
    required this.pulseRate,
    required this.spo2,
    required this.signalStrength,
    required this.fingerOff,
    required this.searching,
    required this.pulseBeep,
  }) : super(timestamp);

  /// 0–100, single sample of the photoplethysmogram envelope.
  final int plethSample;

  /// Beats per minute. `null` when the device reports invalid (`0xFF`).
  final int? pulseRate;

  /// SpO₂ percentage 0–100. `null` when invalid (`127`).
  final int? spo2;

  /// 0–15, lower = weaker probe contact.
  final int signalStrength;

  /// True when the probe sensor reports "finger off" / "tongue off".
  final bool fingerOff;

  /// Device is currently acquiring signal (no valid output yet).
  final bool searching;

  /// Per-beat tick — used to drive the heart-tick audio.
  final bool pulseBeep;
}

/// One ECG sample. The AM4100 streams ~250 samples/s in bursts.
class EcgReading extends Am4100Reading {
  const EcgReading({required DateTime timestamp, required this.sampleMicroVolts})
      : super(timestamp);

  /// Signed micro-volts. Mapped from the device's int8 deviation around
  /// the baseline. Range typically ±5000 µV.
  final int sampleMicroVolts;
}

/// One respiration waveform sample (~25 samples/s).
class RespReading extends Am4100Reading {
  const RespReading({required DateTime timestamp, required this.sample})
      : super(timestamp);

  /// 0–255 raw amplitude.
  final int sample;
}

/// Combined heart-rate / respiration-rate / lead-off snapshot, emitted
/// once per second by the device.
class HrRespReading extends Am4100Reading {
  const HrRespReading({
    required DateTime timestamp,
    required this.heartRate,
    required this.respirationRate,
    required this.leadOff,
  }) : super(timestamp);

  final int? heartRate;
  final int? respirationRate;
  final bool leadOff;
}

/// Continuous body-temperature reading (°C).
class TemperatureReading extends Am4100Reading {
  const TemperatureReading({required DateTime timestamp, required this.celsius})
      : super(timestamp);
  final double celsius;
}

/// Non-invasive blood-pressure result (emitted when a measurement
/// completes, not continuously).
class NibpReading extends Am4100Reading {
  const NibpReading({
    required DateTime timestamp,
    required this.systolic,
    required this.diastolic,
    required this.mean,
  }) : super(timestamp);

  final int systolic;
  final int diastolic;
  final int mean;
}

/// Device battery percentage 0–100.
class BatteryReading extends Am4100Reading {
  const BatteryReading({required DateTime timestamp, required this.percent})
      : super(timestamp);
  final int percent;
}

/// Frame-type identifiers used by the multi-parameter framing
/// (`0xAA <type> <len> …`).
///
/// These values are documented from the public BerryMed multi-parameter
/// protocol notes plus reverse engineering of the stock app's symbol
/// table (`_ecgWave`, `_respWave`, `_nibp`, `_temp`, `_battery`,
/// `_hrResp` in `analysis.dart`). If a future firmware revision changes
/// them, edit only this enum — the rest of the parser is data-driven.
enum Am4100FrameType {
  ecgWave(0x01),
  spo2Wave(0x02), // some firmwares emit pleth via the multi-param frame too
  respWave(0x03),
  hrResp(0x04),
  nibp(0x05),
  temperature(0x06),
  battery(0x07),
  ack(0x7F);

  const Am4100FrameType(this.code);
  final int code;

  static Am4100FrameType? fromCode(int code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

const int kMultiParamSync = 0xAA;

/// Streaming frame decoder. Push raw notify bytes via [add]; parsed
/// readings come out on [readings].
class Am4100FrameDecoder {
  Am4100FrameDecoder({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final StreamController<Am4100Reading> _readings =
      StreamController<Am4100Reading>.broadcast();

  /// Stream of parsed readings.
  Stream<Am4100Reading> get readings => _readings.stream;

  /// Bytes that could not be parsed (kept for diagnostics).
  int get bufferedBytes => _buffer.length;

  void add(List<int> chunk) {
    _buffer.add(chunk);
    _drain();
  }

  Future<void> close() => _readings.close();

  // ---------- internals ----------

  void _drain() {
    var data = _buffer.toBytes();
    var consumed = 0;
    final ts = _clock();

    while (consumed < data.length) {
      final remaining = data.length - consumed;
      final b0 = data[consumed];

      // Multi-param frame: AA <type> <len> <payload…> <checksum>
      if (b0 == kMultiParamSync) {
        if (remaining < 4) break; // need at least sync+type+len+chk
        final len = data[consumed + 2];
        final frameLen = 3 + len + 1; // sync+type+len + payload + chk
        if (remaining < frameLen) break;
        final type = data[consumed + 1];
        final payload = data.sublist(consumed + 3, consumed + 3 + len);
        final chk = data[consumed + 3 + len];
        if (_checksum(type, len, payload) == chk) {
          _emitMultiParam(type, payload, ts);
        }
        consumed += frameLen;
        continue;
      }

      // BCI single-param SpO2: 5 bytes. byte 0 has high bit set; data
      // bytes 1, 2, 4 have high bit clear; byte 3 (pulse rate) is
      // permitted to be 0xFF, the protocol's "no PR" sentinel.
      if ((b0 & 0x80) != 0) {
        if (remaining < 5) break;
        final ok = (data[consumed + 1] & 0x80) == 0 &&
            (data[consumed + 2] & 0x80) == 0 &&
            ((data[consumed + 3] & 0x80) == 0 || data[consumed + 3] == 0xFF) &&
            (data[consumed + 4] & 0x80) == 0;
        if (ok) {
          _emitBci(data.sublist(consumed, consumed + 5), ts);
          consumed += 5;
          continue;
        }
      }

      // Resync: drop one byte and try again.
      consumed += 1;
    }

    final leftover = data.sublist(consumed);
    _buffer.clear();
    if (leftover.isNotEmpty) _buffer.add(leftover);
  }

  int _checksum(int type, int len, List<int> payload) {
    var sum = type + len;
    for (final b in payload) {
      sum = (sum + b) & 0xFF;
    }
    return sum & 0xFF;
  }

  void _emitBci(List<int> f, DateTime ts) {
    final b0 = f[0];
    final pleth = f[1];
    final b2 = f[2];
    final b3 = f[3];
    final spo2Raw = f[4];

    final pulseRateRaw = b3 | ((b2 & 0x40) << 1);
    final pulseRate = pulseRateRaw == 0xFF ? null : pulseRateRaw;
    final spo2 = spo2Raw == 127 ? null : spo2Raw;

    _readings.add(SpO2Reading(
      timestamp: ts,
      plethSample: pleth,
      pulseRate: pulseRate,
      spo2: spo2,
      signalStrength: b0 & 0x0F,
      fingerOff: (b0 & 0x10) != 0,
      searching: (b0 & 0x20) != 0,
      pulseBeep: (b0 & 0x40) != 0,
    ));
  }

  void _emitMultiParam(int typeByte, List<int> payload, DateTime ts) {
    final type = Am4100FrameType.fromCode(typeByte);
    if (type == null) return;
    switch (type) {
      case Am4100FrameType.ecgWave:
        // Each byte is a signed int8 deviation around the baseline.
        // Convert to micro-volts via the device's nominal LSB (≈ 4 µV).
        const lsbMicroVolts = 4;
        for (final raw in payload) {
          final signed = raw > 127 ? raw - 256 : raw;
          _readings.add(EcgReading(
            timestamp: ts,
            sampleMicroVolts: signed * lsbMicroVolts,
          ));
        }

      case Am4100FrameType.respWave:
        for (final raw in payload) {
          _readings.add(RespReading(timestamp: ts, sample: raw));
        }

      case Am4100FrameType.hrResp:
        if (payload.length < 3) return;
        final hr = payload[0];
        final rr = payload[1];
        final flags = payload[2];
        _readings.add(HrRespReading(
          timestamp: ts,
          heartRate: hr == 0xFF ? null : hr,
          respirationRate: rr == 0xFF ? null : rr,
          leadOff: (flags & 0x01) != 0,
        ));

      case Am4100FrameType.nibp:
        if (payload.length < 3) return;
        _readings.add(NibpReading(
          timestamp: ts,
          systolic: payload[0],
          diastolic: payload[1],
          mean: payload[2],
        ));

      case Am4100FrameType.temperature:
        if (payload.length < 2) return;
        // Big-endian uint16 in tenths of °C (e.g. 0x015A = 34.6 °C).
        final raw = (payload[0] << 8) | payload[1];
        _readings.add(TemperatureReading(timestamp: ts, celsius: raw / 10.0));

      case Am4100FrameType.battery:
        if (payload.isEmpty) return;
        _readings.add(BatteryReading(timestamp: ts, percent: payload[0]));

      case Am4100FrameType.spo2Wave:
        for (final raw in payload) {
          _readings.add(SpO2Reading(
            timestamp: ts,
            plethSample: raw & 0x7F,
            pulseRate: null,
            spo2: null,
            signalStrength: 15,
            fingerOff: false,
            searching: false,
            pulseBeep: false,
          ));
        }

      case Am4100FrameType.ack:
        // Command-acknowledgement frames are diagnostic only.
        break;
    }
  }
}
