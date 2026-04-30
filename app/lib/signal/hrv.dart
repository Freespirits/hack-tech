/// Heart-rate-variability metrics derived from RR-interval series.
///
/// These are the standard short-term time-domain measures (Task Force
/// of the European Society of Cardiology, 1996):
///
///   - **SDNN**:   standard deviation of NN intervals (ms)
///   - **RMSSD**:  root-mean-square of successive differences (ms)
///   - **pNN50**:  proportion of consecutive NN intervals differing > 50 ms
///   - **mean HR**: BPM derived from the mean NN
///
/// We only accept beats with detector confidence ≥ 0.6 and physiologic
/// RR ∈ [200, 2000] ms (i.e. 30–300 BPM, covering cat through giant
/// dog) to keep ectopic beats and motion artifacts from dominating.
library;

import 'dart:math';

import 'pan_tompkins.dart';

class HrvSummary {
  const HrvSummary({
    required this.beatCount,
    required this.meanHrBpm,
    required this.sdnnMs,
    required this.rmssdMs,
    required this.pnn50,
  });

  final int beatCount;
  final double meanHrBpm;
  final double sdnnMs;
  final double rmssdMs;
  final double pnn50;

  bool get isMeaningful => beatCount >= 5;
}

class HrvCalculator {
  HrvCalculator({this.minRrMs = 200, this.maxRrMs = 2000});

  final int minRrMs;
  final int maxRrMs;

  HrvSummary compute(List<QrsDetection> beats) {
    if (beats.length < 2) {
      return const HrvSummary(
        beatCount: 0,
        meanHrBpm: 0,
        sdnnMs: 0,
        rmssdMs: 0,
        pnn50: 0,
      );
    }

    final rr = <double>[];
    for (var i = 1; i < beats.length; i++) {
      if (beats[i].confidence < 0.6 || beats[i - 1].confidence < 0.6) continue;
      final dtMs = beats[i].timestamp.difference(beats[i - 1].timestamp)
          .inMicroseconds /
          1000.0;
      if (dtMs >= minRrMs && dtMs <= maxRrMs) rr.add(dtMs);
    }

    if (rr.isEmpty) {
      return const HrvSummary(
        beatCount: 0,
        meanHrBpm: 0,
        sdnnMs: 0,
        rmssdMs: 0,
        pnn50: 0,
      );
    }

    final mean = rr.reduce((a, b) => a + b) / rr.length;
    final variance =
        rr.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            rr.length;
    final sdnn = sqrt(variance);

    var sumSqDiff = 0.0;
    var nn50 = 0;
    for (var i = 1; i < rr.length; i++) {
      final d = rr[i] - rr[i - 1];
      sumSqDiff += d * d;
      if (d.abs() > 50) nn50 += 1;
    }
    final rmssd = rr.length > 1 ? sqrt(sumSqDiff / (rr.length - 1)) : 0.0;
    final pnn50 = rr.length > 1 ? nn50 / (rr.length - 1) : 0.0;

    return HrvSummary(
      beatCount: rr.length + 1,
      meanHrBpm: 60000.0 / mean,
      sdnnMs: sdnn,
      rmssdMs: rmssd,
      pnn50: pnn50,
    );
  }
}
