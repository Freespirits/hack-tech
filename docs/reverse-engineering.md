# Reverse engineering the stock app

How the BLE protocol and constants in `app/lib/ble/ble_constants.dart`
were derived from the publicly distributed Berry Pet Health Android
app (XAPK from APKPure).

## What we worked with

* `Berry_Pet_Health_1.2.6_APKPure.xapk` — the user-uploaded artifact
  that prompted this project. Inside it:
  * `com.berry_med.berry_pet_monitor.apk` — base APK (Flutter wrapper,
    AndroidManifest.xml, dexopt baseline, asset bundle).
  * `config.arm64_v8a.apk` — the native split with the Flutter engine
    (`libflutter.so`) and the AOT-compiled Dart code (`libapp.so`).

The Dart code is AOT-compiled to ARM64 machine code, but Dart's AOT
keeps **all type names, method names, and string constants intact**
in the binary. That makes `strings(1)` plus context the most useful
tool, even without a full Blutter pass.

## Procedure

### 1. Confirm tech stack

```sh
unzip -l Berry_Pet_Health_1.2.6_APKPure.xapk
unzip -p com.berry_med.berry_pet_monitor.apk META-INF/MANIFEST.MF | head
unzip -j config.arm64_v8a.apk lib/arm64-v8a/libapp.so -d /tmp/
file /tmp/libapp.so
```

`libapp.so` is the Dart AOT snapshot — confirms it's a Flutter app.

### 2. Find Dart symbol names

```sh
strings /tmp/libapp.so | grep -E '^_[a-z][a-zA-Z]*@[0-9]+$' \
    | sort -u > dart_symbols.txt
```

Each entry is `_methodName@<class-id>`. Grouping by class ID
(the suffix is a content-addressed hash per class) reveals each
class's complete method set. The class with hash `727239104`
exposes:

```
_animAnalysis      _calculatePi   _ecgPeak    _ecgWave
_battery           _hrResp        _nibp       _readAnalysisData
_readData          _respWave      _temp       _vetAnalysis
_vetDraw           _spo2Wave      _spo2Pr
```

This is `analysis.dart` from
`package:berry_pet_health/tools/ble/analysis.dart`. The set of
methods told us exactly which parameter types the protocol carries.

### 3. Find the GATT UUIDs

```sh
strings /tmp/libapp.so \
  | grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
  | sort -u
```

Three custom UUIDs come back:

```
49535343-1E4D-4BD9-BA61-23C647249616
49535343-8841-43F4-A8D4-ECBE34729BB3
49535343-FE7D-4AE5-8FA9-9FAFD205E455
```

These are the well-known Microchip Transparent UART defaults
(BM7x BLE module). The corresponding init constants
(`init:CHARACTERISTIC_UUID_RECEIVE` etc.) confirm which is which.

### 4. Find the device-name filters

```sh
strings /tmp/libapp.so | grep -aiE 'AM[0-9]{4}|BM[0-9]{4}|BerryMed'
```

→ `AM4100`, `AM6200`, `BM1000A-I`, `BerryMed`.

### 5. Find command opcodes

```sh
strings /tmp/libapp.so | grep -aE '^init:CMD_'
```

Only one CMD constant survives the AOT compilation:
`init:CMD_START_NIBP`. The other command codes were derived from
BerryMed's public multi-parameter monitor demos (saadsur/BerryMed,
BerryMed's official Android demos linked from
`https://www.shberrymed.com/downloads/`) and validated against
the type-byte naming we recovered above.

### 6. Cross-check the data path

```sh
strings /tmp/libapp.so | grep -E 'package:berry_pet_health'
```

Tells us the file layout:

```
package:berry_pet_health/tools/ble/analysis.dart
package:berry_pet_health/tools/ble/ble_helper.dart
package:berry_pet_health/tools/ble/cmd.dart
```

Confirms our inferred split: **wire framing in `ble_helper.dart`,
parameter parsing in `analysis.dart`, command builders in
`cmd.dart`** — exactly the structure our `app/lib/ble/` mirrors.

### 7. Backend / cloud target

```sh
strings /tmp/libapp.so | grep -aiE 'aliyun|oss|berrymed-files|sales@'
```

Returns:

```
oss-cn-shanghai.aliyuncs.com
berrymed-files
berrymed-files/
sales@berry-med.com
package:berry_pet_health/tools/aliyun_oss/upload_oss.dart
```

Confirms the stock app uploads measurement data + IMEI to
**Alibaba Cloud OSS in Shanghai**. Our replacement uses Supabase in
the user's preferred region instead — see `docs/architecture.md`.

## Verifying the protocol against real traffic

The reverse-engineering above is sufficient to write a parser and a
command builder, but for any production use you should confirm the
exact byte layout against your specific AM4100 unit. We ship a
helper for this:

```sh
# 1. Enable Bluetooth HCI snoop log on Android (Developer Options).
# 2. Drive the AM4100 with the stock app for a couple of minutes,
#    exercising each parameter (ECG, SpO2, NIBP).
# 3. Pull the snoop log:
adb pull /data/misc/bluetooth/logs/btsnoop_hci.log .
# 4. Decode:
python tools/ble-sniffer/decode.py btsnoop_hci.log
```

The output prints decoded frames in the same shape as
`test/ble/am4100_protocol_test.dart`'s fixtures. If a frame type
doesn't match, edit the `Am4100FrameType` enum in
`app/lib/ble/am4100_protocol.dart` — that is the one place where
the byte assignments are concentrated; nothing else needs to change.
