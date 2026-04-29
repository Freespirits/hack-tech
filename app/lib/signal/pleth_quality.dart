/// Pleth-waveform signal-quality gating for SpO₂ trust.
///
/// The AM4100 reports SpO₂ even when the probe is loose; the resulting
/// numbers can be off by 5–10 percentage points. We compute a simple
/// **perfusion index** (PI) — the AC/DC ratio of the pleth envelope —
/// and reject SpO₂ updates with PI below 0.4 % (the clinical floor for
/// pulse oximetry per ISO 80601-2-61).
library;

import 'dart:math';
import 'dart:collection';

class PlethQualityWindow {
  PlethQualityWindow({this.windowSize = 240});

  final int windowSize;
  final ListQueue<int> _samples = ListQueue();

  void add(int sample) {
    _samples.addLast(sample);
    while (_samples.length > windowSize) {
      _samples.removeFirst();
    }
  }

  /// Perfusion index in **percent** (AC peak-to-peak / DC mean × 100).
  /// Returns 0 when the buffer doesn't have enough samples yet.
  double perfusionIndex() {
    if (_samples.length < windowSize ~/ 2) return 0;
    var dc = 0.0;
    var maxV = -double.infinity;
    var minV = double.infinity;
    for (final s in _samples) {
      dc += s;
      if (s > maxV) maxV = s.toDouble();
      if (s < minV) minV = s.toDouble();
    }
    dc /= _samples.length;
    if (dc <= 0) return 0;
    final ac = maxV - minV;
    return (ac / dc) * 100;
  }

  /// Should the current SpO₂ reading be trusted?
  bool isTrustworthy({double minPiPercent = 0.4}) {
    final pi = perfusionIndex();
    return pi >= minPiPercent && pi.isFinite;
  }

  /// 0–1 quality score for UI display (logistic mapping of PI).
  double qualityScore() {
    final pi = perfusionIndex();
    if (pi <= 0) return 0;
    final x = (pi - 1.0) * 1.5;
    return 1 / (1 + exp(-x));
  }

  void reset() => _samples.clear();
}
