/// Client-side helpers for building the JSON payload sent to the
/// `insight` Edge Function.
///
/// The actual prompt template + `cache_control` placement live
/// server-side in `backend/supabase/functions/insight/prompts.ts` so
/// the API key never leaves the server. This file only assembles the
/// **user-turn** content (per-session vitals, baselines, history
/// snippets) — the volatile suffix that intentionally sits *after*
/// the cached prefix.
library;

import '../data/models/insight.dart';
import '../data/models/pet.dart';
import '../data/models/session.dart';
import '../signal/species_baselines.dart';

class InsightRequest {
  const InsightRequest({
    required this.pet,
    required this.session,
    required this.recentSessions,
    required this.locale,
  });

  final Pet pet;
  final MonitoringSession session;

  /// Up to ~30 days of prior session summaries for trend / baseline
  /// reasoning. Older sessions are dropped to keep the payload small.
  final List<MonitoringSession> recentSessions;

  /// IETF language tag for the response (e.g. `en`, `en-GB`, `de`,
  /// `fr`, `es`, `pt`, `zh-Hant`).
  final String locale;

  Map<String, Object?> toJson() => {
        'pet': {
          'id': pet.id,
          'name': pet.name,
          'species': pet.species.name,
          'breed': pet.breed,
          'sex': pet.sex.name,
          'weight_kg': pet.weightKg,
          'age_months': pet.ageMonths,
          'notes': pet.notes,
        },
        'baseline': _baselineJson(pet.baseline),
        'session': session.toJson(),
        'recent_sessions': recentSessions
            .where((s) => s.id != session.id && s.endedAt != null)
            .take(10)
            .map((s) => {
                  'id': s.id,
                  'started_at': s.startedAt.toIso8601String(),
                  'duration_minutes': s.duration?.inMinutes,
                  'summary': s.summary.toJson(),
                })
            .toList(),
        'locale': locale,
      };

  Map<String, Object?> _baselineJson(SpeciesBaseline b) => {
        'species': b.species.name,
        'size': b.size.name,
        'heart_rate_bpm': {'low': b.heartRateBpm.low, 'high': b.heartRateBpm.high},
        'respiration_rate_bpm': {
          'low': b.respirationRateBpm.low,
          'high': b.respirationRateBpm.high,
        },
        'temperature_celsius': {
          'low': b.temperatureCelsius.low,
          'high': b.temperatureCelsius.high,
        },
        'spo2_percent': {'low': b.spo2Percent.low, 'high': b.spo2Percent.high},
        'systolic_mmhg': {'low': b.systolicMmHg.low, 'high': b.systolicMmHg.high},
        'diastolic_mmhg': {
          'low': b.diastolicMmHg.low,
          'high': b.diastolicMmHg.high,
        },
        'mean_arterial_mmhg': {
          'low': b.meanArterialMmHg.low,
          'high': b.meanArterialMmHg.high,
        },
      };
}

class InsightResponse {
  const InsightResponse({
    required this.summary,
    required this.findings,
    required this.recommendations,
    required this.urgency,
    required this.thinking,
    required this.modelId,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
  });

  final String summary;
  final List<String> findings;
  final List<String> recommendations;
  final InsightUrgency urgency;
  final String thinking;
  final String modelId;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;

  factory InsightResponse.fromJson(Map<String, Object?> json) =>
      InsightResponse(
        summary: (json['summary'] as String?) ?? '',
        findings: ((json['findings'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        recommendations: ((json['recommendations'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        urgency: InsightUrgency.values.byName(
          (json['urgency'] as String?) ?? 'routine',
        ),
        thinking: (json['thinking'] as String?) ?? '',
        modelId: (json['model'] as String?) ?? '',
        inputTokens: (json['usage'] as Map?)?['input_tokens'] as int? ?? 0,
        outputTokens: (json['usage'] as Map?)?['output_tokens'] as int? ?? 0,
        cacheReadTokens:
            (json['usage'] as Map?)?['cache_read_input_tokens'] as int? ?? 0,
      );
}
