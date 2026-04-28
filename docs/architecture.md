# Architecture

```
┌─────────────────────────────────  Phone (Flutter)  ─────────────────────────────────┐
│                                                                                       │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐               │
│  │ UI (screens +    │  │ Riverpod         │  │ AI insight client      │  ──HTTPS──┐   │
│  │ waveform widgets)│  │ providers (DI)   │  │ (calls Edge Function)  │           │   │
│  └────────┬─────────┘  └────────┬─────────┘  └────────────┬───────────┘           │   │
│           │                     │                          │                       │   │
│           ▼                     ▼                          ▼                       │   │
│  ┌──────────────────────────────────────────────────────────────┐                  │   │
│  │ Repositories (PetRepository, SessionRepository, …)           │                  │   │
│  └────────────┬───────────────────────────────────┬─────────────┘                  │   │
│               │                                   │                                │   │
│               ▼                                   ▼                                │   │
│  ┌──────────────────────────┐         ┌─────────────────────────┐                  │   │
│  │ Local SQLite (Drift)     │         │ Supabase sync service   │  ──HTTPS────────►│   │
│  │ - pets                   │         │ (best-effort upload)    │                  │   │
│  │ - sessions / readings    │         └─────────────────────────┘                  │   │
│  │ - waveform_chunks        │                                                       │   │
│  │ - insights               │                                                       │   │
│  └────────────┬─────────────┘                                                       │   │
│               │                                                                     │   │
│               ▲                                                                     │   │
│  ┌────────────┴──────────────────────────────────────────────────┐                  │   │
│  │ Signal processing (Pan-Tompkins, HRV, pleth quality, filters) │                  │   │
│  └────────────────────────┬──────────────────────────────────────┘                  │   │
│                           ▲                                                         │   │
│  ┌────────────────────────┴────────────────────────┐                                │   │
│  │ BLE service                                     │                                │   │
│  │  - state machine (Idle → Scanning → Connected)  │                                │   │
│  │  - Am4100FrameDecoder (BCI + multi-param)       │                                │   │
│  │  - Am4100Commands (start NIBP, ECG gain, …)     │                                │   │
│  │  - Android foreground service for screen-off    │                                │   │
│  └────────────────────────┬────────────────────────┘                                │   │
│                           │                                                         │   │
│                           │  Microchip Transparent UART                             │   │
│                           ▼                                                         │   │
│              ┌───────────────────────┐                                              │   │
│              │ AM4100 monitor        │                                              │   │
│              │ (SpO₂ + ECG + NIBP +  │                                              │   │
│              │  Resp + Temp + Batt)  │                                              │   │
│              └───────────────────────┘                                              │   │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                                                                       │
                                                                                       ▼
                              ┌──────────────────────  Supabase  ──────────────────────┐
                              │                                                        │
                              │ ┌──────────────┐  ┌────────────────────────────────┐   │
                              │ │ PostgreSQL   │  │ Edge Function: insight         │   │
                              │ │ (RLS per     │◄─┤ • Validates JWT + clinic       │   │
                              │ │  clinic)     │  │ • Calls Claude Opus 4.7        │   │
                              │ │              │  │   - adaptive thinking          │   │
                              │ │              │  │   - prompt caching (system +   │   │
                              │ │              │  │     species ref, ttl=1h)       │   │
                              │ │              │  │   - output_config.format       │   │
                              │ │              │  │     (json_schema)              │   │
                              │ │              │  │ • Returns parsed insight       │   │
                              │ └──────────────┘  └────────────────────────────────┘   │
                              │                                                        │
                              └────────────────────────────────────────────────────────┘
```

## Layer responsibilities

| Layer            | Responsibility                                                            |
|------------------|---------------------------------------------------------------------------|
| BLE              | Speak the AM4100 protocol; never know about pets, sessions, or AI.        |
| Signal           | Pure functions over sample streams. No I/O. Easy to unit-test.            |
| Data — local     | Owns the SQLite source of truth. Tracks `synced_at` for cloud sync.       |
| Data — remote    | Pushes durable state to Supabase. Read path is direct via Postgres + RLS. |
| AI               | Builds JSON for the Edge Function. Never holds an API key.                |
| UI               | Riverpod providers + Material widgets. Reactive to BLE + DB streams.      |
| Edge Function    | Single-shot Claude call with prompt caching, JWT-gated, RLS-aware.        |
| Postgres + RLS   | Multi-tenant data + policies that enforce clinic boundaries.              |

## Why Flutter, not native?

We considered Kotlin Multiplatform (shared logic, native UI) and full
native (best stability). Flutter wins for this project because:

1. **Two platforms with one codebase** — and the live-monitoring UI is
   the same on both.
2. **Reliability is a code concern, not a platform concern** — the
   stock app's drops aren't Flutter's fault, they're
   `flutter_reactive_ble`'s. We swap to `flutter_blue_plus` and add an
   Android `foregroundServiceType="connectedDevice"` and most of the
   gap closes.
3. **Custom waveform painting in Dart at 60 fps is fine** for the data
   rates we're dealing with (250 Hz ECG, 60 Hz pleth).

If clinic feedback later shows we still drop too often we can move
just the BLE layer to Pigeon/native channels without rewriting the
whole app.

## State management

Riverpod 2 with `flutter_riverpod`. Providers live in
`lib/core/di.dart`. Tests can override any provider via
`ProviderScope.overrides`.

## Persistence model

The local SQLite is the source of truth. Each session's vitals are
written every second; waveform chunks are written in 1-second batches
to keep transactions small. Cloud sync is best-effort and runs after
session end + on app resume — failures stay on the device until the
next attempt.
