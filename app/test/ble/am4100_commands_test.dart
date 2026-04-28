import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/ble/am4100_commands.dart';

void main() {
  test('startNibp builds correct frame with valid checksum', () {
    final bytes = Am4100Commands.startNibp();
    expect(bytes[0], 0xAA);
    expect(bytes[1], 0x10); // CMD_START_NIBP
    expect(bytes[2], 0); // zero-length payload
    expect(bytes.length, 4);
    expect(bytes[3], (0x10 + 0) & 0xFF); // checksum
  });

  test('setEcgGain rejects invalid values', () {
    expect(() => Am4100Commands.setEcgGain(3), throwsArgumentError);
    expect(() => Am4100Commands.setEcgGain(0), throwsArgumentError);
    expect(() => Am4100Commands.setEcgGain(16), throwsArgumentError);
  });

  test('setEcgGain(4) frame and checksum', () {
    final bytes = Am4100Commands.setEcgGain(4);
    expect(bytes[0], 0xAA);
    expect(bytes[1], 0x20);
    expect(bytes[2], 1);
    expect(bytes[3], 4);
    expect(bytes[4], (0x20 + 1 + 4) & 0xFF);
  });

  test('setRespLeadOffDetect toggles correctly', () {
    final on = Am4100Commands.setRespLeadOffDetect(enabled: true);
    final off = Am4100Commands.setRespLeadOffDetect(enabled: false);
    expect(on[3], 1);
    expect(off[3], 0);
  });

  test('setEcgFilter rejects out-of-range mode', () {
    expect(() => Am4100Commands.setEcgFilter(-1), throwsArgumentError);
    expect(() => Am4100Commands.setEcgFilter(3), throwsArgumentError);
    expect(Am4100Commands.setEcgFilter(0)[3], 0);
    expect(Am4100Commands.setEcgFilter(2)[3], 2);
  });
}
