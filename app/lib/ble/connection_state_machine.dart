/// BLE connection state machine with jittered exponential backoff.
///
/// This is the layer that fixes the stock app's biggest reliability gap:
/// Berry Pet Health relies on `flutter_reactive_ble`'s implicit reconnect,
/// which silently gives up after a few attempts on Android when the screen
/// sleeps. We model the connection explicitly so the UI can render
/// "reconnecting (3/∞)" instead of "device disconnected, please reopen".
library;

import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

@immutable
sealed class BleConnectionState {
  const BleConnectionState();
}

class Idle extends BleConnectionState {
  const Idle();
}

class Scanning extends BleConnectionState {
  const Scanning();
}

class Connecting extends BleConnectionState {
  const Connecting(this.attempt);
  final int attempt;
}

class DiscoveringServices extends BleConnectionState {
  const DiscoveringServices(this.deviceId);
  final String deviceId;
}

class NegotiatingMtu extends BleConnectionState {
  const NegotiatingMtu(this.deviceId);
  final String deviceId;
}

class SubscribingNotifications extends BleConnectionState {
  const SubscribingNotifications(this.deviceId);
  final String deviceId;
}

class Connected extends BleConnectionState {
  const Connected({required this.deviceId, required this.deviceName});
  final String deviceId;
  final String deviceName;
}

class Reconnecting extends BleConnectionState {
  const Reconnecting({required this.attempt, required this.delay});
  final int attempt;
  final Duration delay;
}

class Disconnected extends BleConnectionState {
  const Disconnected({this.error});
  final Object? error;
}

/// Jittered exponential-backoff scheduler. Used by [BleService] to
/// retry connection attempts without thundering-herd behavior.
class BackoffScheduler {
  BackoffScheduler({
    Duration initial = const Duration(seconds: 1),
    Duration max = const Duration(minutes: 2),
    double multiplier = 1.8,
    Random? random,
  })  : _initial = initial,
        _max = max,
        _multiplier = multiplier,
        _rand = random ?? Random();

  final Duration _initial;
  final Duration _max;
  final double _multiplier;
  final Random _rand;

  /// Compute the delay for `attempt` ≥ 1 (1, 2, 3, …) with full jitter.
  Duration delayFor(int attempt) {
    if (attempt < 1) {
      throw ArgumentError('attempt must be >= 1');
    }
    final raw = _initial.inMilliseconds * pow(_multiplier, attempt - 1);
    final capped = min(raw, _max.inMilliseconds.toDouble());
    final jittered = capped * (0.5 + _rand.nextDouble() * 0.5);
    return Duration(milliseconds: jittered.round());
  }
}
