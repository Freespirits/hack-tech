/// BLE constants for the SINOHERO/BerryMed AM4100 (and OEM siblings).
///
/// The AM4100 exposes the **Microchip Transparent UART** GATT service
/// (this is the BLE module's default — Microchip BM7x family). All
/// BerryMed-specific framing rides on top of these characteristics.
///
/// These UUIDs were extracted from the Berry Pet Health Android app's
/// compiled Dart (`libapp.so`) by string-matching for the
/// `49535343-…` pattern — see `docs/reverse-engineering.md` for the
/// full procedure.
library;

/// Microchip Transparent UART service (the AM4100's only custom service).
const String kAm4100ServiceUuid = '49535343-fe7d-4ae5-8fa9-9fafd205e455';

/// Notify characteristic — device → app (the stock app calls this `RECEIVE`).
const String kAm4100NotifyCharUuid = '49535343-1e4d-4bd9-ba61-23c647249616';

/// Write characteristic — app → device (the stock app calls this `SEND`).
const String kAm4100WriteCharUuid = '49535343-8841-43f4-a8d4-ecbe34729bb3';

/// Rename characteristic — used to change the BLE advertised name.
const String kAm4100RenameCharUuid = '00005343-0000-1000-8000-00805f9b34fb';

/// Device-name prefixes the AM4100 family advertises with.
///
/// The same OEM hardware ships under multiple brands (SINOHERO, BerryMed,
/// Pepultech, KeeboVet …) but they all keep the same advertised name.
const Set<String> kKnownDeviceNamePrefixes = {
  'AM4100',
  'AM6100',
  'AM6200',
  'BM1000',
  'BerryMed',
};

/// Recommended MTU. The Microchip UART chunks data at 20 B by default, but
/// negotiating up to 247 B reduces packet count for ECG bursts.
const int kPreferredMtu = 247;

/// How long to wait for a notify subscription before considering the
/// connection dead.
const Duration kSubscribeTimeout = Duration(seconds: 5);

/// Target sample rates (per the BCI/BerryMed protocol). Used for buffer
/// sizing and signal processing, not for hard timing assumptions.
class Am4100SampleRates {
  static const int ecgHz = 250;
  static const int plethHz = 60;
  static const int respHz = 25;
}
