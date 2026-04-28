import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/ble/am4100_protocol.dart';

void main() {
  group('Am4100FrameDecoder — BCI single-parameter SpO2', () {
    test('parses a clean 5-byte frame', () async {
      final decoder = Am4100FrameDecoder(
        clock: () => DateTime(2026, 1, 1, 12, 0, 0),
      );
      final frame = <int>[
        0x80 | 0x40 | 0x05, // sync, pulseBeep, signal=5
        0x55,               // pleth = 85
        0x00,               // bargraph=0, no PR high bit
        72,                 // pulse rate = 72 bpm
        97,                 // SpO2 = 97 %
      ];
      final readings = decoder.readings.take(1).toList();
      decoder.add(frame);
      final r = (await readings).single as SpO2Reading;
      expect(r.plethSample, 0x55);
      expect(r.pulseRate, 72);
      expect(r.spo2, 97);
      expect(r.signalStrength, 5);
      expect(r.fingerOff, isFalse);
      expect(r.searching, isFalse);
      expect(r.pulseBeep, isTrue);
      await decoder.close();
    });

    test('PR high bit reconstruction', () async {
      // pulse rate 200 = 0xC8 = bit 7 + 0x48; high bit lives in byte[2] bit 6.
      final decoder = Am4100FrameDecoder();
      final frame = <int>[
        0x80,
        0x10,
        0x40,    // PR high bit set
        0x48,    // PR low bits = 72
        100,
      ];
      final readings = decoder.readings.take(1).toList();
      decoder.add(frame);
      final r = (await readings).single as SpO2Reading;
      expect(r.pulseRate, 200);
      await decoder.close();
    });

    test('invalid sentinels (0xFF / 127) become null', () async {
      final decoder = Am4100FrameDecoder();
      final frame = <int>[0x80, 0x10, 0x00, 0xFF, 127];
      final readings = decoder.readings.take(1).toList();
      decoder.add(frame);
      final r = (await readings).single as SpO2Reading;
      expect(r.pulseRate, isNull);
      expect(r.spo2, isNull);
      await decoder.close();
    });

    test('chunked notify still parses two frames in order', () async {
      final decoder = Am4100FrameDecoder();
      final out = <Am4100Reading>[];
      final sub = decoder.readings.listen(out.add);
      const frame1 = [0x80, 0x10, 0x00, 60, 96];
      const frame2 = [0x80, 0x10, 0x00, 64, 97];
      // Split mid-frame to exercise the buffer.
      decoder.add(frame1.sublist(0, 3));
      decoder.add([...frame1.sublist(3), ...frame2.sublist(0, 2)]);
      decoder.add(frame2.sublist(2));
      await Future<void>.delayed(Duration.zero);
      expect(out.length, 2);
      expect((out[0] as SpO2Reading).pulseRate, 60);
      expect((out[1] as SpO2Reading).pulseRate, 64);
      await sub.cancel();
      await decoder.close();
    });
  });

  group('Am4100FrameDecoder — multi-parameter framing', () {
    int chksum(List<int> bytes) {
      var s = 0;
      for (final b in bytes) {
        s = (s + b) & 0xFF;
      }
      return s;
    }

    test('parses an HR/Resp frame', () async {
      final decoder = Am4100FrameDecoder();
      final readings = decoder.readings.take(1).toList();
      const type = 0x04;
      const len = 3;
      const payload = <int>[120, 24, 0];
      final frame = <int>[
        0xAA,
        type,
        len,
        ...payload,
        chksum(<int>[type, len, ...payload]),
      ];
      decoder.add(frame);
      final r = (await readings).single as HrRespReading;
      expect(r.heartRate, 120);
      expect(r.respirationRate, 24);
      expect(r.leadOff, isFalse);
      await decoder.close();
    });

    test('temperature payload (big-endian tenths of °C)', () async {
      final decoder = Am4100FrameDecoder();
      final readings = decoder.readings.take(1).toList();
      // 38.7 °C -> 387 -> 0x01 0x83
      const type = 0x06;
      const payload = <int>[0x01, 0x83];
      final frame = <int>[0xAA, type, payload.length, ...payload, chksum(<int>[type, payload.length, ...payload])];
      decoder.add(frame);
      final r = (await readings).single as TemperatureReading;
      expect(r.celsius, closeTo(38.7, 1e-9));
      await decoder.close();
    });

    test('checksum mismatch is dropped silently', () async {
      final decoder = Am4100FrameDecoder();
      final out = <Am4100Reading>[];
      final sub = decoder.readings.listen(out.add);
      decoder.add([0xAA, 0x07, 0x01, 50, /* bad chk */ 0xFF]);
      await Future<void>.delayed(Duration.zero);
      expect(out, isEmpty);
      await sub.cancel();
      await decoder.close();
    });

    test('ECG burst yields one reading per byte', () async {
      final decoder = Am4100FrameDecoder();
      final out = <Am4100Reading>[];
      final sub = decoder.readings.listen(out.add);
      const type = 0x01;
      // Six samples: signed int8 deviations.
      const payload = <int>[10, 20, 30, 250 /* -6 */, 0, 5];
      final frame = <int>[0xAA, type, payload.length, ...payload, chksum(<int>[type, payload.length, ...payload])];
      decoder.add(frame);
      await Future<void>.delayed(Duration.zero);
      expect(out.length, 6);
      expect((out[3] as EcgReading).sampleMicroVolts, -6 * 4);
      await sub.cancel();
      await decoder.close();
    });

    test('resyncs after garbage bytes', () async {
      final decoder = Am4100FrameDecoder();
      final out = <Am4100Reading>[];
      final sub = decoder.readings.listen(out.add);
      // Garbage bytes (no high bit set, not 0xAA), then a valid BCI frame.
      decoder.add([0x05, 0x06, 0x07]);
      decoder.add([0x80, 0x10, 0x00, 70, 96]);
      await Future<void>.delayed(Duration.zero);
      expect(out.length, 1);
      expect((out.single as SpO2Reading).pulseRate, 70);
      await sub.cancel();
      await decoder.close();
    });
  });
}
