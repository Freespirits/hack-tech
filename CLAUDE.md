# Project context for Claude Code

This is **PetVitals** — an iOS + Android Flutter app + Supabase backend that
replaces the stock _Berry Pet Health_ companion for the SINOHERO / BerryMed
**AM4100** veterinary multi-parameter monitor.

## Architecture in one screen

```
Phone (Flutter)                                       Supabase
┌─────────────────────────────────────────┐         ┌────────────────────┐
│  UI layer (screens + waveform widgets)  │         │  Postgres          │
│       │                                 │         │  (RLS per clinic)  │
│       ▼                                 │         │       ▲            │
│  AI client ──── HTTPS ──────────────────┼────────▶│  Edge Function     │
│       ▲                                 │         │   "insight"        │
│       │                                 │         │       │            │
│  Repositories (local SQLite + sync)     │         │       ▼            │
│       ▲                                 │         │  Claude Opus 4.7   │
│       │                                 │         │   (prompt cached)  │
│  Signal processing (Pan-Tompkins, HRV)  │         └────────────────────┘
│       ▲
│       │
│  BLE service ── Microchip Transparent UART ── AM4100 device
│  (state machine + foreground service)
└─────────────────────────────────────────┘
```

## Conventions

- **Dart code is null-safe and uses sealed `Result<T, E>`**, not exceptions
  across layer boundaries.
- **Waveforms are stored at full sample rate** (raw byte buffer per session)
  and **only downsampled at render time**. Never average before persisting.
- **All BLE traffic is logged to a rotating local file** when
  `Env.bleDebugLogging` is on; never log raw payloads to the cloud.
- **Per-pet thresholds** for SpO2 / HR / Temperature live in the SQLite
  `alarm_thresholds` table and are evaluated client-side on every incoming
  reading; the alarm sound (`assets/sounds/alarm.wav`) plays via
  `just_audio`.
- **Claude API calls happen server-side** (Edge Function) so the API key
  never ships in the app bundle. The function uses **prompt caching** with
  a stable system prompt + species reference block as the cache prefix and
  the per-session vitals JSON as the volatile suffix.

## When working in this repo

- **Never touch the BLE characteristic UUIDs** in `lib/ble/ble_constants.dart`
  unless you've sniffed new traffic from a real AM4100.
- **All vitals math has tests** in `test/signal/` — run `flutter test` after
  any change in `lib/signal/`.
- **The Edge Function model string is `claude-opus-4-7`.** Do not change it
  to a non-Opus model without explicit user approval; if you need to migrate
  to a newer Claude release, follow `shared/model-migration.md` from the
  claude-api skill.
- **Prompts live in two places:** `app/lib/ai/prompts.dart` (client-side
  builder) and `backend/supabase/functions/insight/prompts.ts` (server-side
  cached prefix). Keep them logically aligned.
