#!/usr/bin/env python3
"""
Decode an Android btsnoop_hci.log into AM4100 frames.

Standalone — no third-party dependencies. Filters to GATT operations
on the Microchip Transparent UART characteristics used by the AM4100.

Output format mirrors the unit-test fixtures in
app/test/ble/am4100_protocol_test.dart so a problematic frame can be
copied straight into a regression test.
"""

from __future__ import annotations

import datetime as dt
import struct
import sys
from pathlib import Path

# Same UUIDs as app/lib/ble/ble_constants.dart.
SERVICE_UUID = "49535343-fe7d-4ae5-8fa9-9fafd205e455"
NOTIFY_UUID = "49535343-1e4d-4bd9-ba61-23c647249616"
WRITE_UUID = "49535343-8841-43f4-a8d4-ecbe34729bb3"

BTSNOOP_HEADER = b"btsnoop\x00"


def parse_btsnoop(path: Path):
    """Yield (timestamp, direction, payload_bytes) tuples."""
    with path.open("rb") as f:
        header = f.read(16)
        if not header.startswith(BTSNOOP_HEADER):
            raise SystemExit(f"{path}: not a btsnoop file")
        # Skip remaining 8 bytes (version + datalink).

        while True:
            rec_hdr = f.read(24)
            if len(rec_hdr) < 24:
                return
            (
                orig_len,
                incl_len,
                flags,
                _drops,
                ts_us,
            ) = struct.unpack(">IIIIQ", rec_hdr)
            payload = f.read(incl_len)
            if len(payload) < incl_len:
                return

            # Convert from microseconds since 0000-01-01 to a UTC datetime.
            timestamp = (
                dt.datetime(1, 1, 1)
                + dt.timedelta(microseconds=ts_us)
            )
            direction = "rx" if (flags & 0x01) else "tx"
            yield timestamp, direction, payload


def decode_bci(buf: bytes):
    if len(buf) < 5 or not (buf[0] & 0x80):
        return None
    if any(b & 0x80 for b in buf[1:5]):
        return None
    pleth = buf[1]
    pr = buf[3] | ((buf[2] & 0x40) << 1)
    spo2 = buf[4]
    return f"bci    pleth={pleth} pr={pr if pr != 0xFF else '?'} " \
           f"spo2={spo2 if spo2 != 127 else '?'} sig={buf[0] & 0x0F}"


def decode_multi(buf: bytes):
    if len(buf) < 4 or buf[0] != 0xAA:
        return None
    type_b = buf[1]
    length = buf[2]
    if len(buf) < 4 + length:
        return None
    payload = list(buf[3 : 3 + length])
    chk = buf[3 + length]
    expected = (type_b + length + sum(payload)) & 0xFF
    valid = "✓" if chk == expected else "✗"
    label = {
        0x01: "ecg",
        0x02: "spo2Wave",
        0x03: "respWave",
        0x04: "hrResp",
        0x05: "nibp",
        0x06: "temp",
        0x07: "battery",
        0x7F: "ack",
    }.get(type_b, f"type=0x{type_b:02x}")
    return f"multi  {label:9s} len={length} payload={payload} chk={valid}"


def find_uart_payload(record: bytes):
    """Return the GATT payload if the record is a notify/write on
    the AM4100 UART; else None."""
    # We can't fully parse all of HCI here without state. Instead use
    # a permissive scan: look for the AM4100 UUID bytes in the record
    # (the Microchip UART UUIDs are unusual enough that false
    # positives are unlikely in normal traffic).
    needle = b"\x49\x53\x53\x53"  # ASCII "ISSS" — start of all three UUIDs
    if needle not in record:
        return None
    # GATT notify ATT opcode is 0x1B; write request is 0x12; write
    # without response is 0x52. Find the first one and take the
    # following payload bytes.
    for opcode in (0x1B, 0x12, 0x52):
        idx = record.find(bytes([opcode]))
        while idx != -1 and idx + 3 < len(record):
            payload = record[idx + 3:]
            if 4 <= len(payload) <= 244:
                return payload
            idx = record.find(bytes([opcode]), idx + 1)
    return None


def main(argv):
    if len(argv) != 2:
        print("usage: decode.py <btsnoop_hci.log>", file=sys.stderr)
        return 2
    log = Path(argv[1])
    seen = 0
    for ts, direction, record in parse_btsnoop(log):
        payload = find_uart_payload(record)
        if not payload:
            continue
        decoded = decode_bci(payload) or decode_multi(payload) \
            or f"raw    {payload.hex()}"
        print(f"{ts.isoformat()}  {direction}  {decoded}")
        seen += 1
    print(f"\nDecoded {seen} GATT records.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
