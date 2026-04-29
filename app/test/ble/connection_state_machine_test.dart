import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/ble/connection_state_machine.dart';

void main() {
  group('BackoffScheduler', () {
    test('grows monotonically up to the cap', () {
      final s = BackoffScheduler(
        initial: const Duration(milliseconds: 100),
        max: const Duration(seconds: 10),
        multiplier: 2,
        random: Random(42),
      );
      Duration prev = Duration.zero;
      for (var i = 1; i <= 8; i++) {
        final d = s.delayFor(i);
        // Jitter is ±50 %, so allow some looseness.
        expect(d.inMilliseconds, greaterThanOrEqualTo(prev.inMilliseconds ~/ 2));
        prev = d;
      }
      // Final attempt is capped under the max + jitter.
      expect(s.delayFor(20).inMilliseconds, lessThanOrEqualTo(10000));
    });

    test('rejects attempt < 1', () {
      final s = BackoffScheduler();
      expect(() => s.delayFor(0), throwsArgumentError);
    });

    test('different RNG seeds yield different jittered delays', () {
      final a = BackoffScheduler(random: Random(1));
      final b = BackoffScheduler(random: Random(2));
      expect(a.delayFor(3), isNot(equals(b.delayFor(3))));
    });
  });
}
