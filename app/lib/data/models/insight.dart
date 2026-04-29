import 'package:meta/meta.dart';

/// Output of one Claude-generated insight pass over a session.
@immutable
class SessionInsight {
  const SessionInsight({
    required this.id,
    required this.sessionId,
    required this.petId,
    required this.summary,
    required this.findings,
    required this.recommendations,
    required this.urgency,
    required this.thinking,
    required this.modelId,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.generatedAt,
  });

  final String id;
  final String sessionId;
  final String petId;

  /// One- to two-sentence plain-language summary, suitable for the
  /// session-detail card.
  final String summary;

  /// Bullet-pointed key findings, each ≤ 1 sentence.
  final List<String> findings;

  /// Actionable next steps. Always framed as "to discuss with your vet"
  /// — never as diagnoses.
  final List<String> recommendations;

  /// `routine` / `monitor` / `urgent`. Drives the card's color band.
  final InsightUrgency urgency;

  /// Optional thinking summary (Opus 4.7 adaptive thinking with display:
  /// "summarized"). Hidden behind a "Show reasoning" toggle.
  final String thinking;

  final String modelId;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final DateTime generatedAt;
}

enum InsightUrgency { routine, monitor, urgent }
