/// Public BLE service. Owns the scanner, the active connection, and the
/// frame decoder. UI layers consume [state] and [readings] via Riverpod.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import 'am4100_commands.dart';
import 'am4100_protocol.dart';
import 'ble_constants.dart';
import 'connection_state_machine.dart';

class BleService {
  BleService({Logger? logger, BackoffScheduler? backoff})
      : _logger = logger ?? Logger(),
        _backoff = backoff ?? BackoffScheduler();

  final Logger _logger;
  final BackoffScheduler _backoff;

  final StreamController<BleConnectionState> _stateCtl =
      StreamController<BleConnectionState>.broadcast();
  Am4100FrameDecoder? _decoder;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _notifyChar;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool _explicitDisconnect = false;
  int _attempt = 0;
  Timer? _reconnectTimer;

  Stream<BleConnectionState> get state => _stateCtl.stream;
  Stream<Am4100Reading> get readings =>
      (_decoder ??= Am4100FrameDecoder()).readings;

  /// Scan for AM4100-family devices for [timeout] seconds. Yields each
  /// matching scan result; returns the first match.
  Stream<ScanResult> scanFor({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    _stateCtl.add(const Scanning());
    await FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: [Guid(kAm4100ServiceUuid)],
    );
    await for (final results in FlutterBluePlus.scanResults) {
      for (final r in results) {
        if (_isAm4100(r)) yield r;
      }
    }
  }

  bool _isAm4100(ScanResult r) {
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    return kKnownDeviceNamePrefixes.any((p) => name.startsWith(p));
  }

  /// Connect to a device (cancelling any previous session). Subscribes
  /// to notifications, negotiates MTU, and starts streaming readings.
  Future<void> connect(BluetoothDevice device) async {
    _explicitDisconnect = false;
    _attempt = 0;
    await _disposeActive();
    await _attemptConnect(device);
  }

  Future<void> _attemptConnect(BluetoothDevice device) async {
    _attempt += 1;
    _device = device;
    _stateCtl.add(Connecting(_attempt));
    try {
      await device.connect(autoConnect: false, mtu: kPreferredMtu);
      _connSub = device.connectionState.listen(_onConnectionStateChanged);
      _stateCtl.add(DiscoveringServices(device.remoteId.str));
      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid.str.toLowerCase() == kAm4100ServiceUuid,
        orElse: () => throw StateError('AM4100 service not found'),
      );
      _writeChar = svc.characteristics.firstWhere(
        (c) => c.uuid.str.toLowerCase() == kAm4100WriteCharUuid,
        orElse: () => throw StateError('AM4100 write characteristic missing'),
      );
      _notifyChar = svc.characteristics.firstWhere(
        (c) => c.uuid.str.toLowerCase() == kAm4100NotifyCharUuid,
        orElse: () => throw StateError('AM4100 notify characteristic missing'),
      );

      _stateCtl.add(SubscribingNotifications(device.remoteId.str));
      await _notifyChar!.setNotifyValue(true);
      _decoder ??= Am4100FrameDecoder();
      _notifySub = _notifyChar!.lastValueStream.listen(_decoder!.add);

      _stateCtl.add(Connected(
        deviceId: device.remoteId.str,
        deviceName: device.platformName,
      ));
      _attempt = 0;

      // Friendly hello to nudge any firmwares that hold notifications
      // until the first command.
      await sendCommand(Am4100Commands.requestBattery());
    } catch (e, st) {
      _logger.w('connect failed', error: e, stackTrace: st);
      await _disposeActive();
      if (!_explicitDisconnect) _scheduleReconnect();
    }
  }

  void _onConnectionStateChanged(BluetoothConnectionState s) {
    if (s == BluetoothConnectionState.disconnected && !_explicitDisconnect) {
      _logger.i('disconnected — scheduling reconnect');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    final device = _device;
    if (device == null) {
      _stateCtl.add(const Disconnected());
      return;
    }
    final delay = _backoff.delayFor(_attempt + 1);
    _stateCtl.add(Reconnecting(attempt: _attempt + 1, delay: delay));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _attemptConnect(device));
  }

  Future<void> sendCommand(List<int> bytes) async {
    final ch = _writeChar;
    if (ch == null) throw StateError('Not connected');
    await ch.write(bytes, withoutResponse: false);
  }

  Future<void> disconnect() async {
    _explicitDisconnect = true;
    _reconnectTimer?.cancel();
    await _disposeActive();
    _stateCtl.add(const Idle());
  }

  Future<void> _disposeActive() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    _notifySub = null;
    _connSub = null;
    _notifyChar = null;
    _writeChar = null;
    final dev = _device;
    if (dev != null && dev.isConnected) {
      try {
        await dev.disconnect();
      } catch (_) {/* swallow — we're tearing down */}
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _decoder?.close();
    await _stateCtl.close();
  }
}
