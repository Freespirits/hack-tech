# AI insight layer

The AI layer turns a finished monitoring session into a vet-facing
narrative summary, a short set of findings, and actionable
recommendations — framed as decision support for a clinician, never
as a diagnosis.

## Model and capabilities

We use **Claude Opus 4.7** (`claude-opus-4-7`):

- **Adaptive thinking** (`thinking: {type: "adaptive", display: "summarized"}`)
  — the model decides per-call whether and how much to reason. The
  `summarized` display gives us a brief reasoning trace we can show
  behind a "Show reasoning" disclosure in the UI.
- **`output_config.format` (json_schema)** — the response is
  guaranteed to match the schema we hand it; the Edge Function never
  has to apologize to the phone for invalid JSON.
- **`output_config.effort: "high"`** — vet-clinic decision support
  is an intelligence-sensitive workload; the cost vs. quality
  tradeoff lands at `high`.

## Prompt structure (and why)

The Anthropic skill's `shared/prompt-caching.md` doc is explicit:
caching is a prefix match, and any byte change anywhere in the
prefix invalidates everything after it. So the prompt is designed
with a strict stable / volatile split:

```
┌─────────────────────────────  STABLE (cached)  ─────────────────────────────┐
│ system block 1: role, instructions, output contract                          │
│ system block 2: species reference table   ← cache_control: ephemeral, 1h    │
└─────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────  VOLATILE (per call)  ──────────────────────────┐
│ user message: JSON {pet, baseline, session, recent_sessions, locale}         │
└─────────────────────────────────────────────────────────────────────────────┘
```

A single cache write covers a clinic's traffic for an hour, after
which the next call writes a fresh entry. During clinic hours that
amortizes to near-zero on the cached portion (~10 % of input price).

Cache-hit verification: the Edge Function returns
`usage.cache_read_input_tokens` to the phone; if it's zero across
sequential calls that's a signal the prefix has been mutated. The
test suite (`backend/tests/prompts_test.ts`) guards this:

- the system prompt cannot contain timestamps or UUIDs (silent
  invalidators)
- only the **last** system block carries `cache_control`
- block ordering is fixed and asserted

## Output schema

```json
{
  "summary":         "1-2 sentence plain-language synopsis",
  "findings":        ["finding 1", "finding 2", "..."],
  "recommendations": ["actionable next step 1", "..."],
  "urgency":         "routine" | "monitor" | "urgent",
  "thinking":        "optional brief reasoning trace"
}
```

The schema is enforced via `output_config.format: { type: "json_schema",
schema: {...} }` with `additionalProperties: false`.

## Prompting policy

The system prompt encodes:

1. **Role boundary** — decision support, not diagnosis. Output is
   for the licensed clinician.
2. **Signal quality first** — if `signal_quality < 0.4`, the
   summary must lead with that caveat and urgency must be
   downgraded unless independent values clearly justify it.
3. **Compare to species baseline, not human.** A 180 BPM HR is
   normal for a small cat and tachycardic for a Great Dane.
4. **Trends matter.** When `recent_sessions` is non-empty, compare
   the current session's means to the rolling baseline and call
   out percentage drift more strongly than absolute values inside
   the species range.
5. **Specificity in findings.** Bad: "abnormal heart rate". Good:
   "Mean HR of 165 BPM is at the upper end of the small-dog
   reference range and 22 % above this pet's 30-day average".
6. **Urgency calibration.** `urgent` only for life-threatening
   patterns (sustained SpO₂ < 90, HR outside ±50 % species range,
   T > 41 °C, suspected arrhythmia AND high signal quality).

## Authentication and authorization

The Edge Function:

1. Verifies the JWT in `Authorization: Bearer <token>` against
   Supabase Auth.
2. Reads `session.clinic_id` from the body and confirms the user is
   a member of that clinic (`clinic_members` table). 403 otherwise.
3. Forwards the request to Claude.
4. Returns the parsed insight, including model usage so the phone
   can display token counts and cache-hit ratios for transparency.

The Anthropic API key only ever lives in the Edge Function's
environment, set via `supabase secrets set ANTHROPIC_API_KEY=...`.
It never enters the app bundle.

## Cost and latency notes

- Cached prefix is ~1500 tokens. At Opus 4.7 pricing
  (~$5 / 1M input, ~$25 / 1M output) one full session insight runs
  $0.01–$0.04 on a cache miss and ~$0.005 on a hit.
- p50 latency is ~3–5 s; the function's `receive_timeout` on the
  phone client is 90 s.
- `task_budget` is intentionally unset on Opus 4.7 — there's no
  agentic loop here; a single bounded Messages call suffices.

## Why not chat / MCP?

A chat surface ("ask about this pet's history") is an obvious
extension and easy to add: the same Edge Function, with a different
system prompt and the pet's prior insights as the user-turn payload.
For v1 we keep the surface small — one button, one card, one
response — to make the contract trivially observable for a vet.

When chat is added, switch to the Managed Agents API for the
multi-turn flow (per the skill's `shared/managed-agents-overview.md`)
so that we don't have to reimplement event streams and tool-call
loops by hand.
