// Supabase Edge Function: POST /functions/v1/insight
//
// Body:  { pet, baseline, session, recent_sessions, locale }
// Auth:  must carry a valid Supabase user JWT
// Response:
//   {
//     summary, findings, recommendations, urgency, thinking,
//     model, usage: { input_tokens, output_tokens, cache_read_input_tokens }
//   }
//
// Calls Claude Opus 4.7 with adaptive thinking (display: "summarized")
// and prompt caching on the static system prompt + species reference
// block. The output is constrained to a JSON schema via
// `output_config.format` so the function never has to apologize for
// invalid JSON to the phone.

import Anthropic from "npm:@anthropic-ai/sdk@0.40.1";
import { createClient } from "npm:@supabase/supabase-js@2.43.5";

import { corsHeaders } from "../_shared/cors.ts";
import { buildSystemBlocks, OUTPUT_SCHEMA } from "./prompts.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const MODEL_ID = Deno.env.get("MODEL_ID") ?? "claude-opus-4-7";

interface InsightPayload {
  pet: Record<string, unknown>;
  baseline: Record<string, unknown>;
  session: Record<string, unknown>;
  recent_sessions: Array<Record<string, unknown>>;
  locale: string;
}

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // ---- Auth: confirm the caller is a real Supabase user.
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) {
    return json({ error: "Missing bearer token" }, 401);
  }
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userResp, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userResp.user) {
    return json({ error: "Invalid user" }, 401);
  }

  // ---- Parse + validate payload.
  let payload: InsightPayload;
  try {
    payload = (await req.json()) as InsightPayload;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!payload.pet || !payload.session || !payload.baseline) {
    return json({ error: "pet, session, baseline are required" }, 400);
  }

  // ---- Authorization: confirm the caller is a member of the pet's clinic.
  const clinicId = (payload.session as { clinic_id?: string }).clinic_id;
  if (!clinicId) {
    return json({ error: "session.clinic_id is required" }, 400);
  }
  const { data: membership, error: membershipErr } = await supabase
    .from("clinic_members")
    .select("clinic_id, role")
    .eq("user_id", userResp.user.id)
    .eq("clinic_id", clinicId)
    .maybeSingle();
  if (membershipErr || !membership) {
    return json({ error: "Forbidden" }, 403);
  }

  // ---- Build the request.
  const { system } = buildSystemBlocks();
  const userContent = JSON.stringify(payload);

  let response;
  try {
    response = await anthropic.messages.create({
      model: MODEL_ID,
      max_tokens: 2048,
      system,
      // Adaptive thinking with summarized display so we can show a
      // brief reasoning trace in the UI without stuffing the response
      // with unredacted internal monologue.
      thinking: { type: "adaptive", display: "summarized" },
      output_config: {
        effort: "high",
        format: {
          type: "json_schema",
          schema: OUTPUT_SCHEMA,
        },
      },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Generate the insight JSON for the following session " +
                `(respond in locale: ${payload.locale ?? "en"}).\n\n` +
                userContent,
            },
          ],
        },
      ],
    });
  } catch (err) {
    if (err instanceof Anthropic.APIError) {
      return json(
        { error: `Anthropic API ${err.status}: ${err.message}` },
        502,
      );
    }
    throw err;
  }

  // ---- Extract text + thinking blocks.
  let bodyText = "";
  let thinkingText = "";
  for (const block of response.content) {
    if (block.type === "text") bodyText += block.text;
    if (block.type === "thinking") thinkingText += block.thinking ?? "";
  }

  // The output_config.format guarantee gives us valid JSON.
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(bodyText);
  } catch {
    return json({
      error: "Model returned non-JSON output (this should not happen)",
      raw: bodyText,
    }, 502);
  }

  return json({
    summary: parsed.summary ?? "",
    findings: parsed.findings ?? [],
    recommendations: parsed.recommendations ?? [],
    urgency: parsed.urgency ?? "routine",
    thinking: parsed.thinking || thinkingText,
    model: response.model,
    usage: {
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      cache_creation_input_tokens: response.usage.cache_creation_input_tokens ??
        0,
      cache_read_input_tokens: response.usage.cache_read_input_tokens ?? 0,
    },
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
