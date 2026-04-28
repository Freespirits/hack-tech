/// Lightweight DSP filters for the AM4100 waveform streams.
///
/// All filters are zero-allocation per sample (state held on the
/// instance), so they're cheap to run inside a stream listener at
/// 250 Hz on a phone.
library;

import 'dart:math';

/// One-pole high-pass IIR filter. Removes baseline wander from ECG and
/// pleth waveforms.
///
///   H(z) = (1 + a) / 2 · (1 − z⁻¹) / (1 − a·z⁻¹)
///
/// where `a = exp(−2π·f_c / f_s)`.
class HighPassFilter {
  HighPassFilter({required double cutoffHz, required double sampleHz})
      : _alpha = exp(-2 * pi * cutoffHz / sampleHz);

  final double _alpha;
  double _prevIn = 0;
  double _prevOut = 0;

  double process(double sample) {
    final out = _alpha * (_prevOut + sample - _prevIn);
    _prevIn = sample;
    _prevOut = out;
    return out;
  }

  void reset() {
    _prevIn = 0;
    _prevOut = 0;
  }
}

/// One-pole low-pass IIR. Smooths the pleth envelope before SpO2
/// validity gating.
class LowPassFilter {
  LowPassFilter({required double cutoffHz, required double sampleHz})
      : _alpha = 1 - exp(-2 * pi * cutoffHz / sampleHz);

  final double _alpha;
  double _prev = 0;

  double process(double sample) {
    _prev = _prev + _alpha * (sample - _prev);
    return _prev;
  }

  void reset() => _prev = 0;
}

/// Cascade of [HighPassFilter] then [LowPassFilter] — a passable
/// band-pass for ECG (5–15 Hz is the standard QRS-energy band).
class BandPassFilter {
  BandPassFilter({
    required double lowHz,
    required double highHz,
    required double sampleHz,
  })  : _hp = HighPassFilter(cutoffHz: lowHz, sampleHz: sampleHz),
        _lp = LowPassFilter(cutoffHz: highHz, sampleHz: sampleHz);

  final HighPassFilter _hp;
  final LowPassFilter _lp;

  double process(double sample) => _lp.process(_hp.process(sample));

  void reset() {
    _hp.reset();
    _lp.reset();
  }
}

/// 5-tap differentiator (Pan–Tompkins step 3).
///
///   y[n] = (1/8)·(2·x[n] + x[n-1] − x[n-3] − 2·x[n-4])
class FiveTapDifferentiator {
  final List<double> _w = List.filled(5, 0);

  double process(double sample) {
    _w
      ..removeAt(0)
      ..add(sample);
    return (2 * _w[4] + _w[3] - _w[1] - 2 * _w[0]) / 8;
  }

  void reset() {
    for (var i = 0; i < _w.length; i++) {
      _w[i] = 0;
    }
  }
}

/// Moving-average integrator over `windowSize` samples.
class MovingAverage {
  MovingAverage(this.windowSize) : _ring = List.filled(windowSize, 0);
  final int windowSize;
  final List<double> _ring;
  int _idx = 0;
  double _sum = 0;

  double process(double sample) {
    _sum -= _ring[_idx];
    _sum += sample;
    _ring[_idx] = sample;
    _idx = (_idx + 1) % windowSize;
    return _sum / windowSize;
  }

  void reset() {
    _sum = 0;
    _idx = 0;
    for (var i = 0; i < _ring.length; i++) {
      _ring[i] = 0;
    }
  }
}
