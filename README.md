# PetVitals — clinical-grade vet monitor app for the AM4100

A vet-clinic-ready iOS + Android companion for the **SINOHERO / BerryMed AM4100**
6-parameter Bluetooth veterinary monitor (and the BM1000A-I, BM1000C, AM6100,
AM6200, and other devices in the same OEM family).

Built as a clean replacement for the stock _Berry Pet Health_ app, with:

- **Native-grade BLE reliability** — `flutter_blue_plus` + a foreground service
  on Android, MTU negotiation, write-queue serialization, and a proper
  reconnection state machine with jittered exponential backoff. No more silent
  drops when the screen sleeps.
- **Higher-precision signal processing** — Pan–Tompkins R-peak detection on
  ECG, IIR band-pass + perfusion-index gating on the pleth waveform before SpO2
  is trusted, RMSSD/SDNN HRV from clean RR intervals, species- and
  weight-aware normal ranges (cat / small dog / large dog / exotic).
- **Multi-tenant vet clinic backend** — Supabase Postgres with row-level
  security per clinic, multi-vet auth, durable measurement uploads, signed
  share links to send a session to an external referrer.
- **AI insights via Claude Opus 4.7** — per-session narrative summaries,
  baseline-aware anomaly detection ("Bella's HR is 18 % above her 30-day
  baseline"), plain-language waveform explanations, and an optional chat that
  can answer questions over a pet's full history. Implemented with prompt
  caching on the static system prompt + species reference data so cost stays
  bounded.
- **Tests + CI** — Dart unit tests for the BLE parser, signal processors,
  data models, and prompt builders; Deno tests for the Edge Function;
  GitHub Actions for both pipelines.

This branch is the complete first cut — see [`docs/architecture.md`](docs/architecture.md)
for the system diagram and [`docs/ble-protocol.md`](docs/ble-protocol.md) for
the reverse-engineered AM4100 wire format.

## Quick start

```sh
# Flutter app
cd app
flutter pub get
flutter test
flutter run                          # iOS or Android, with the device powered on

# Backend (Supabase)
cd backend
supabase start                       # local Postgres + Edge Functions
supabase db reset                    # apply migrations
supabase functions serve insight --env-file .env
deno test --allow-env --allow-net tests/
```

## Repo layout

```
app/                     Flutter app (iOS + Android)
├── lib/ble/             AM4100 BLE protocol + connection state machine
├── lib/signal/          Pan-Tompkins, filters, HRV, species baselines
├── lib/data/            Local SQLite (Drift) + Supabase sync
├── lib/ai/              Claude API client (calls Edge Function)
├── lib/ui/              Screens + waveform widgets
└── test/                Unit tests for every layer

backend/supabase/        Postgres schema + Edge Functions
├── migrations/          Multi-tenant clinic schema with RLS
└── functions/insight/   Claude Opus 4.7 with prompt caching

tools/ble-sniffer/       btsnoop log decoder for verifying the protocol

docs/                    Architecture, BLE protocol, AI design, deployment
```

## License

All code in this repo is original work. The AM4100 wire format is documented
from publicly available BerryMed BCI Protocol references plus reverse
engineering of the (publicly distributed) Berry Pet Health Android app.
