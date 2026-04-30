/// Outgoing-command builders for the AM4100.
///
/// Commands ride the same Microchip Transparent UART write characteristic
/// as the inbound stream, but use the multi-parameter framing
/// (`0xAA <type> <len> <payload…> <checksum>`) so the device can
/// distinguish them from passthrough data.
library;

import 'dart:typed_data';

/// Command-byte assignments. Verified against the stock app's
/// `init:CMD_START_NIBP` symbol; the rest follow the BerryMed
/// multi-parameter convention.
enum Am4100CommandCode {
  startNibp(0x10),
  stopNibp(0x11),
  setEcgGain(0x20),
  setEcgFilter(0x21),
  setRespLeadOffDetect(0x22),
  setTemperatureUnit(0x30),
  requestBattery(0x40),
  requestVersion(0x50);

  const Am4100CommandCode(this.code);
  final int code;
}

class Am4100Commands {
  Am4100Commands._();

  /// Build a multi-parameter command frame.
  static Uint8List build(Am4100CommandCode cmd, [List<int> payload = const []]) {
    final type = cmd.code;
    final len = payload.length;
    var sum = type + len;
    for (final b in payload) {
      sum = (sum + b) & 0xFF;
    }
    final out = Uint8List(3 + len + 1);
    out[0] = 0xAA;
    out[1] = type;
    out[2] = len;
    for (var i = 0; i < len; i++) {
      out[3 + i] = payload[i];
    }
    out[3 + len] = sum & 0xFF;
    return out;
  }

  /// Trigger a one-shot NIBP (non-invasive blood pressure) measurement.
  static Uint8List startNibp() => build(Am4100CommandCode.startNibp);

  /// Cancel an in-progress NIBP cuff inflation.
  static Uint8List stopNibp() => build(Am4100CommandCode.stopNibp);

  /// Request the current battery percentage. The device replies with a
  /// `Am4100FrameType.battery` frame.
  static Uint8List requestBattery() =>
      build(Am4100CommandCode.requestBattery);

  /// `gain` ∈ {1, 2, 4, 8}.
  static Uint8List setEcgGain(int gain) {
    if (![1, 2, 4, 8].contains(gain)) {
      throw ArgumentError('ECG gain must be 1, 2, 4, or 8');
    }
    return build(Am4100CommandCode.setEcgGain, [gain]);
  }

  /// `mode`: 0 = monitor, 1 = diagnostic (wider band), 2 = surgical.
  static Uint8List setEcgFilter(int mode) {
    if (mode < 0 || mode > 2) {
      throw ArgumentError('ECG filter mode must be 0, 1, or 2');
    }
    return build(Am4100CommandCode.setEcgFilter, [mode]);
  }

  /// `enabled` toggles the lead-off detection current on the resp leads.
  static Uint8List setRespLeadOffDetect({required bool enabled}) =>
      build(Am4100CommandCode.setRespLeadOffDetect, [enabled ? 1 : 0]);

  /// `0` = Celsius, `1` = Fahrenheit (display-only; values still come over
  /// the wire in tenths of °C).
  static Uint8List setTemperatureUnit({required bool fahrenheit}) =>
      build(Am4100CommandCode.setTemperatureUnit, [fahrenheit ? 1 : 0]);
}
