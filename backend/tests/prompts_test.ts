// Tests for the static prompt-cache prefix.
//
// We do NOT call the live Anthropic API here — we only verify that
// the cached prefix is shaped correctly, so a future refactor that
// silently moves volatile content into the prefix gets caught.

import {
  assertEquals,
  assertExists,
  assertStringIncludes,
} from "std/assert/mod.ts";
import {
  buildSystemBlocks,
  OUTPUT_SCHEMA,
  SPECIES_REFERENCE,
  SYSTEM_PROMPT,
} from "../supabase/functions/insight/prompts.ts";

Deno.test("system prompt does not contain dynamic content", () => {
  // No ISO dates, no UUIDs, no Date.now(). These would silently
  // invalidate the prompt cache on every call.
  const isoDateRegex = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;
  const uuidRegex = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/;
  if (isoDateRegex.test(SYSTEM_PROMPT)) {
    throw new Error("system prompt contains an ISO timestamp");
  }
  if (uuidRegex.test(SYSTEM_PROMPT)) {
    throw new Error("system prompt contains a UUID");
  }
  if (SYSTEM_PROMPT.includes("Date.now")) {
    throw new Error("system prompt references Date.now");
  }
});

Deno.test("system blocks are ordered: instructions first, reference second", () => {
  const { system } = buildSystemBlocks();
  assertEquals(system.length, 2);
  assertEquals(system[0].text, SYSTEM_PROMPT);
  assertEquals(system[1].text, SPECIES_REFERENCE);
});

Deno.test("only the LAST system block carries cache_control (1h ttl)", () => {
  const { system } = buildSystemBlocks();
  // Per shared/prompt-caching.md: a cache_control marker on the last
  // cacheable block caches everything before it (tools + system).
  assertEquals(system[0].cache_control, undefined);
  assertExists(system[1].cache_control);
  assertEquals(system[1].cache_control?.type, "ephemeral");
  assertEquals(system[1].cache_control?.ttl, "1h");
});

Deno.test("system prompt contains the JSON shape contract", () => {
  assertStringIncludes(SYSTEM_PROMPT, "summary");
  assertStringIncludes(SYSTEM_PROMPT, "findings");
  assertStringIncludes(SYSTEM_PROMPT, "recommendations");
  assertStringIncludes(SYSTEM_PROMPT, "urgency");
  // It also tells the model to never wrap output in markdown.
  assertStringIncludes(SYSTEM_PROMPT, "no markdown");
});

Deno.test("OUTPUT_SCHEMA is strict and complete", () => {
  assertEquals(OUTPUT_SCHEMA.type, "object");
  assertEquals(OUTPUT_SCHEMA.additionalProperties, false);
  assertEquals(OUTPUT_SCHEMA.required, [
    "summary",
    "findings",
    "recommendations",
    "urgency",
  ]);
  // Urgency is enum-constrained.
  assertEquals(
    (OUTPUT_SCHEMA.properties as Record<string, { enum?: string[] }>).urgency
      .enum,
    ["routine", "monitor", "urgent"],
  );
});

Deno.test("species reference covers dog, cat, rabbit, ferret", () => {
  for (const species of ["DOG", "CAT", "RABBIT", "FERRET"]) {
    assertStringIncludes(SPECIES_REFERENCE, species);
  }
  // PI gating thresholds are documented for the model.
  assertStringIncludes(SPECIES_REFERENCE, "PI < 0.4");
});
