# BLE sniffer for the AM4100

A small Python helper that decodes Android `btsnoop_hci.log` files,
filters to the AM4100's GATT service, and prints frames in the same
shape as the unit tests' fixtures.

## Why

Reverse-engineering the BerryMed protocol from the stock app gets
us 95 % of the way there, but the multi-parameter `type` byte
assignments (ECG = 0x01, NIBP = 0x05, etc.) are inferred from
public BerryMed demos rather than read directly from the binary.
Sniffing real traffic from your specific AM4100 unit is a one-line
verification.

## Usage

1. On your Android device, enable **Developer options → Enable
   Bluetooth HCI snoop log**.
2. Open the stock Berry Pet Health app and drive the AM4100 through
   each parameter (let it stream ECG, take a NIBP measurement,
   trigger the temperature reading).
3. Pull the log:
   ```sh
   adb bugreport bugreport.zip
   unzip -p bugreport.zip FS/data/misc/bluetooth/logs/btsnoop_hci.log > btsnoop.log
   # Or, on rooted devices:
   adb pull /data/misc/bluetooth/logs/btsnoop_hci.log .
   ```
4. Decode:
   ```sh
   python decode.py btsnoop.log
   ```

The output prints each parsed frame on its own line, e.g.:

```
2026-04-28T22:10:11.123  notify  type=0x04 len=3 [120, 24, 0]   # hrResp
2026-04-28T22:10:11.171  notify  type=0x06 len=2 [1, 131]       # temperature → 38.7°C
2026-04-28T22:10:11.220  bci     pleth=85 pr=72 spo2=97 sig=5
```

If any frame's `type` byte doesn't match what the test fixtures
expect, edit `app/lib/ble/am4100_protocol.dart::Am4100FrameType`
to match.

## Limitations

* Decodes Android btsnoop format only (the macOS `PacketLogger`
  format is similar but not identical).
* Does not decrypt encrypted GATT writes (the AM4100 doesn't use
  encryption on the Microchip Transparent UART, so this is fine).
