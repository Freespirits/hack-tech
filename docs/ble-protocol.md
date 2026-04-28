# AM4100 BLE Protocol

This document describes the wire protocol the **SINOHERO / BerryMed
AM4100** veterinary multi-parameter monitor speaks over Bluetooth Low
Energy. Both the inbound (device → app) and outbound (app → device)
direction are documented, plus how those bytes were verified.

The same OEM hardware ships under multiple brand names — SINOHERO,
BerryMed, Pepultech, KeeboVet — but the BLE stack is identical
across them. The same protocol decoder also handles the related
**AM6100, AM6200, BM1000A-I**, and **BM1000C** devices.

## GATT layout

The AM4100 exposes a single custom service. It's the **Microchip
Transparent UART** GATT service that comes with the BLE module Berry
uses (Microchip BM7x family).

| Element | UUID | Properties |
|---|---|---|
| Service | `49535343-fe7d-4ae5-8fa9-9fafd205e455` | — |
| RX (app → device) | `49535343-8841-43f4-a8d4-ecbe34729bb3` | write |
| TX (device → app) | `49535343-1e4d-4bd9-ba61-23c647249616` | notify |
| Rename | `00005343-0000-1000-8000-00805f9b34fb` | write |

The Berry Pet Health app calls these `SEND` (write) and `RECEIVE`
(notify) — the names from `init:CHARACTERISTIC_UUID_*` symbols in
the app's compiled Dart binary.

The advertised name always starts with one of `AM4100`, `AM6100`,
`AM6200`, `BM1000`, or `BerryMed`. Scan filters use this prefix in
addition to the service UUID for robustness — some firmware
revisions take a couple of seconds before the service is fully
advertised.

## Frame families

The AM4100 mixes **two coexisting frame formats** on the same notify
characteristic. Both must be handled by the decoder, and a single
notify packet can contain bytes from either or both. The decoder is
in `app/lib/ble/am4100_protocol.dart`.

### 1. BCI single-parameter SpO₂ frames (5 bytes)

Documented in `zh2x/BCI_Protocol`. Used for the SpO₂ pleth waveform
and per-beat status updates.

| Byte | Bits | Meaning |
|------|------|---------|
| 0    | 7 (set) | sync flag — distinguishes header from payload |
| 0    | 6 | pulse beep — flips on each detected beat |
| 0    | 5 | searching — device is acquiring signal |
| 0    | 4 | finger off — probe is not in contact |
| 0    | 3:0 | signal strength 0–15 |
| 1    | 6:0 | pleth waveform sample 0–100 |
| 2    | 6 | high bit of pulse rate (combined with byte 3 to form 0–255) |
| 2    | 5:0 | bargraph value (unused by us) |
| 3    | 6:0 | low 7 bits of pulse rate; together with byte 2's bit 6 yields 0–255 BPM |
| 4    | 6:0 | SpO₂ percentage 0–100 |

**Sentinel values:** pulse rate `0xFF` and SpO₂ `127` mean "invalid"
— the decoder maps them to `null` so the UI can render "—".

### 2. Multi-parameter frames (variable length)

The format used for ECG bursts, respiration, NIBP, temperature, and
battery on the AM4100/AM6100/AM6200.

```
+------+------+------+----------+-----+
| 0xAA | type |  len | payload… | chk |
+------+------+------+----------+-----+
```

| Byte | Meaning |
|------|---------|
| 0    | Sync byte = `0xAA` |
| 1    | Frame type code (see table) |
| 2    | Payload length in bytes |
| 3..  | Payload (`len` bytes) |
| last | Checksum: `(type + len + sum(payload)) & 0xFF` |

| Type | Hex | Payload |
|------|-----|---------|
| `ecgWave`     | `0x01` | One signed-int8 sample per byte (~250 samples/s, ~4 µV/LSB after the device's nominal gain) |
| `spo2Wave`    | `0x02` | Pleth samples (alternative to BCI single-param frames; some firmwares emit both) |
| `respWave`    | `0x03` | Respiration waveform samples 0–255 |
| `hrResp`      | `0x04` | `[hr, rr, flags]` — heart rate BPM, respiration BPM, lead-off flag in bit 0 |
| `nibp`        | `0x05` | `[systolic, diastolic, MAP]` in mmHg |
| `temperature` | `0x06` | Big-endian uint16 in tenths of °C (e.g. `0x015A` → 34.6 °C) |
| `battery`     | `0x07` | Single byte 0–100 |
| `ack`         | `0x7F` | Command-acknowledgement (diagnostic only) |

**Resync:** if the decoder sees a byte that's neither `0xAA` nor a
BCI sync byte, it drops it and tries the next one. The 5-byte BCI
format is also validated by checking that bytes 1–4 all have their
high bit clear.

### 3. Outgoing commands

Built by `Am4100Commands`. Same multi-parameter framing as inbound:
`0xAA <code> <len> <payload> <chk>`.

| Command | Code | Payload |
|---------|------|---------|
| `startNibp`              | `0x10` | none |
| `stopNibp`               | `0x11` | none |
| `setEcgGain`             | `0x20` | `[gain]` where gain ∈ {1, 2, 4, 8} |
| `setEcgFilter`           | `0x21` | `[mode]` 0 = monitor, 1 = diagnostic, 2 = surgical |
| `setRespLeadOffDetect`   | `0x22` | `[0|1]` |
| `setTemperatureUnit`     | `0x30` | `[0|1]` (display-only — wire format is unchanged) |
| `requestBattery`         | `0x40` | none |
| `requestVersion`         | `0x50` | none |

The `startNibp` code value is the only one verified directly from a
symbol in the stock app (`init:CMD_START_NIBP`); the others follow
the BerryMed multi-parameter convention. Adjust the `Am4100CommandCode`
enum if a future firmware sniff turns up different values.

## Source attribution & verification

* **GATT UUIDs:** read from `string` output of the stock app's
  `lib/arm64-v8a/libapp.so`. Only three `49535343-…` matches; they
  align with the Microchip Transparent UART defaults.
* **Device-name prefixes:** read from the same binary —
  `'AM4100'`, `'AM6100'`, `'AM6200'`, `'BM1000A-I'`, `'BerryMed'`.
* **Symbol table inside `analysis.dart`:** `_ecgWave`, `_ecgPeak`,
  `_spo2Wave`, `_spo2Pr`, `_respWave`, `_hrResp`, `_nibp`, `_temp`,
  `_battery`, `_calculatePi` — together these named the frame types.
* **BCI 5-byte format:** documented in `zh2x/BCI_Protocol` and
  matched by Adafruit's CircuitPython driver
  (`adafruit/Adafruit_CircuitPython_BLE_BerryMed_Pulse_Oximeter`).
  Our parser is byte-for-byte compatible.
* **Multi-parameter framing:** documented in BerryMed's public
  product literature and matches the same shape as the older
  saadsur/BerryMed JS port. The exact `type` byte assignments above
  are the BerryMed convention; in the unlikely event that SINOHERO's
  AM4100 firmware ships with a different mapping, edit the
  `Am4100FrameType` enum in `app/lib/ble/am4100_protocol.dart` —
  no other code change required.

## Sniffing your own AM4100

If you want to verify the parser against your specific unit:

1. Enable Android's **Bluetooth HCI snoop log** in developer
   options.
2. Run the stock Berry Pet Health app, drive the device through
   each parameter (ECG, SpO₂, NIBP, etc.).
3. Pull the `btsnoop_hci.log`:
   ```sh
   adb pull /data/misc/bluetooth/logs/btsnoop_hci.log .
   ```
4. Decode with the helper:
   ```sh
   python tools/ble-sniffer/decode.py btsnoop_hci.log
   ```
   The script filters to writes/notifies on the AM4100 service and
   prints frames in the same format as `am4100_protocol_test.dart`'s
   fixtures.
