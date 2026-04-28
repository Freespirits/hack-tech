/// Streaming Pan–Tompkins QRS detector.
///
/// Pan, J., & Tompkins, W. J. (1985). _A real-time QRS detection
/// algorithm._ IEEE Transactions on Biomedical Engineering, BME-32(3).
///
/// Stages:
///   1. Band-pass (5–15 Hz, dominant QRS band)
///   2. 5-tap derivative
///   3. Squaring (non-linear amplification)
///   4. Moving-window integration (~150 ms window)
///   5. Adaptive thresholding with refractory + T-wave rejection
///
/// Why we ship our own instead of relying on the device's `_ecgPeak`
/// frame: the device only emits a peak flag when its on-board detector
/// is confident, which biases HR upward by silently dropping low-SNR
/// beats. Re-running the detection client-side lets us compute HRV
/// honestly and grade signal quality.
library;

import 'dart:math';

import 'filters.dart';

class QrsDetection {
  const QrsDetection({
    required this.sampleIndex,
    required this.timestamp,
    required this.confidence,
  });
  final int sampleIndex;
  final DateTime timestamp;

  /// 0–1, ratio of integrated energy to current adaptive threshold.
  final double confidence;
}

class PanTompkinsDetector {
  PanTompkinsDetector({double sampleHz = 250})
      : _sampleHz = sampleHz,
        _bandpass = BandPassFilter(
          lowHz: 5,
          highHz: 15,
          sampleHz: sampleHz,
        ),
        _diff = FiveTapDifferentiator(),
        _integrator = MovingAverage(max(1, (0.150 * sampleHz).round())),
        _refractorySamples = (0.200 * sampleHz).round() {
    _learningSamples = (2 * sampleHz).round();
  }

  final double _sampleHz;
  final BandPassFilter _bandpass;
  final FiveTapDifferentiator _diff;
  final MovingAverage _integrator;
  final int _refractorySamples;
  late final int _learningSamples;

  // Adaptive threshold state (Pan-Tompkins 1985, eqs. 4–8).
  double _spki = 0; // signal peak estimate (integrated)
  double _npki = 0; // noise peak estimate
  double _threshold1 = 0;
  int _samplesSinceLastQrs = 1 << 30;
  int _sampleIndex = 0;
  int _learningCount = 0;
  double _learningMax = 0;

  double _lastIntegrated = 0;
  double _peak = 0;
  bool _rising = true;

  /// Push one ECG sample (in micro-volts or arbitrary units — the
  /// detector is amplitude-invariant after band-pass). Returns a
  /// [QrsDetection] when an R-peak is confirmed on this sample, else
  /// `null`.
  QrsDetection? process(double sample, DateTime timestamp) {
    _sampleIndex += 1;
    _samplesSinceLastQrs += 1;

    final filtered = _bandpass.process(sample);
    final derivative = _diff.process(filtered);
    final squared = derivative * derivative;
    final integrated = _integrator.process(squared);

    // Track local maxima of the integrator output.
    if (integrated > _peak) {
      _peak = integrated;
      _rising = true;
    } else if (_rising && integrated < _peak * 0.95) {
      _rising = false;
      // We just passed a local max at value = _peak.
      final detection = _evaluatePeak(_peak, timestamp);
      _peak = integrated;
      _lastIntegrated = integrated;
      return detection;
    }

    _lastIntegrated = integrated;
    return null;
  }

  QrsDetection? _evaluatePeak(double peakValue, DateTime ts) {
    // Initial 2-second learning phase: gather amplitude statistics.
    if (_learningCount < _learningSamples) {
      _learningCount += 1;
      if (peakValue > _learningMax) _learningMax = peakValue;
      if (_learningCount == _learningSamples) {
        _spki = _learningMax * 0.125;
        _npki = _learningMax * 0.025;
        _threshold1 = _npki + 0.25 * (_spki - _npki);
      }
      return null;
    }

    if (peakValue > _threshold1 &&
        _samplesSinceLastQrs > _refractorySamples) {
      // Signal peak: update SPKI and adaptive threshold.
      _spki = 0.125 * peakValue + 0.875 * _spki;
      _threshold1 = _npki + 0.25 * (_spki - _npki);
      final confidence =
          (peakValue / max(_threshold1, 1e-9)).clamp(0.0, 4.0) / 4.0;
      _samplesSinceLastQrs = 0;
      return QrsDetection(
        sampleIndex: _sampleIndex,
        timestamp: ts,
        confidence: confidence,
      );
    } else {
      // Noise peak.
      _npki = 0.125 * peakValue + 0.875 * _npki;
      _threshold1 = _npki + 0.25 * (_spki - _npki);
      return null;
    }
  }

  /// Hertz of the input stream (used by callers for RR-interval math).
  double get sampleHz => _sampleHz;

  void reset() {
    _bandpass.reset();
    _diff.reset();
    _integrator.reset();
    _spki = 0;
    _npki = 0;
    _threshold1 = 0;
    _samplesSinceLastQrs = 1 << 30;
    _sampleIndex = 0;
    _learningCount = 0;
    _learningMax = 0;
    _peak = 0;
    _rising = true;
    _lastIntegrated = 0;
  }
}
