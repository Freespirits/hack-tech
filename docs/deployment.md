# Deployment

## Backend (Supabase)

### One-time setup

1. Create a Supabase project at https://supabase.com.
2. Install the Supabase CLI: `brew install supabase/tap/supabase`.
3. Link the local repo:
   ```sh
   cd backend
   supabase link --project-ref <ref>
   ```
4. Set the Anthropic API key as a function secret:
   ```sh
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase secrets set MODEL_ID=claude-opus-4-7
   ```

### Apply migrations

```sh
supabase db push
```

### Deploy the Edge Function

```sh
supabase functions deploy insight \
  --import-map ./supabase/functions/_shared/import_map.json
```

### Local dev

```sh
supabase start                  # local Postgres + auth + edge runtime
supabase db reset               # apply migrations from scratch
supabase functions serve insight --env-file .env.local
```

`.env.local` (gitignored) should contain:

```
ANTHROPIC_API_KEY=sk-ant-...
MODEL_ID=claude-opus-4-7
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=...
```

## Mobile app

### Android

```sh
cd app
flutter pub get
flutter build apk --release \
    --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
    --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

The app's smallest Android API is 26 (Android 8.0). The
`foregroundServiceType="connectedDevice"` requires API 29+; on
older devices the foreground service still starts but without the
explicit type.

### iOS

```sh
cd app
flutter build ios --release \
    --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
    --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

iOS requires the `NSBluetoothAlwaysUsageDescription`,
`NSBluetoothPeripheralUsageDescription`, and `bluetooth-central`
background mode that are already in `app/ios/Runner/Info.plist`.

### Optional build flags

| Flag | Effect |
|------|--------|
| `--dart-define=BLE_DEBUG_LOGGING=true` | Dump raw BLE traffic to a rotating file in the app's documents directory. ~1 MB / hour during active monitoring. Off by default. |
| `--dart-define=INSIGHT_LOCALE=de` | Default locale the AI insight is generated in. Per-clinic UI override is on the roadmap. |

## CI

Two GitHub Actions workflows:

- `.github/workflows/flutter.yml` — `flutter analyze` + `flutter test`
  with coverage upload.
- `.github/workflows/backend.yml` — `deno lint`, `deno fmt --check`,
  prompt-cache prefix tests, and a Postgres syntax check on the
  migrations.

## Operational runbook

### "AI insights stopped working"

Check (in this order):

1. `supabase functions list` — is `insight` deployed?
2. `supabase functions logs insight` — look for `Anthropic API` errors
   (rate limits, auth failures).
3. Verify the secret: `supabase secrets list`.
4. Try a curl smoke test (replace `<jwt>` with a session JWT):
   ```sh
   curl -X POST https://<ref>.supabase.co/functions/v1/insight \
        -H "Authorization: Bearer <jwt>" \
        -H "apikey: <anon-key>" \
        -H "Content-Type: application/json" \
        -d @backend/tests/fixtures/sample_payload.json
   ```

### "Phone stops getting BLE data when the screen sleeps"

This is the failure mode the foreground service exists to prevent.
Check:

1. `adb shell dumpsys activity services com.petvitals.clinic` —
   is `BleForegroundService` listed as `clientCount=1`?
2. Notification channel "Live monitoring" should be enabled in
   system settings.
3. On Android 14+, confirm `POST_NOTIFICATIONS` was granted at
   runtime.

### "Insights have low cache-hit rate"

Symptom: `usage.cache_read_input_tokens` is consistently 0 across
sequential insights. Most likely a recent commit added something
volatile to the system prompt — run the prompt tests:

```sh
cd backend && deno task --config tests/deno.json test tests/
```

The `system prompt does not contain dynamic content` test is the
guardrail.
