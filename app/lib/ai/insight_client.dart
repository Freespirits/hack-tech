/// Client for the Supabase `insight` Edge Function.
///
/// We don't call the Anthropic API from the phone — the API key would
/// have to ship in the bundle. Instead the phone sends a JSON payload
/// of the session + pet + baseline + recent history to the Edge
/// Function, which calls Claude (with prompt caching on the static
/// system prompt) and returns the parsed insight.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/env.dart';
import '../data/models/insight.dart';
import '../data/models/pet.dart';
import '../data/models/session.dart';
import 'prompts.dart';

class InsightClient {
  InsightClient({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 90),
        ));

  final Dio _dio;

  Future<SessionInsight> generate({
    required Pet pet,
    required MonitoringSession session,
    required List<MonitoringSession> recentSessions,
    required String accessToken,
    String locale = 'en',
  }) async {
    final body = InsightRequest(
      pet: pet,
      session: session,
      recentSessions: recentSessions,
      locale: locale,
    ).toJson();

    final res = await _dio.post<String>(
      '${Env.supabaseUrl}/functions/v1/insight',
      data: jsonEncode(body),
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'apikey': Env.supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.plain,
      ),
    );

    if (res.statusCode != 200) {
      throw Exception('Insight API ${res.statusCode}: ${res.data}');
    }
    final parsed = InsightResponse.fromJson(
      jsonDecode(res.data!) as Map<String, Object?>,
    );

    return SessionInsight(
      id: '${session.id}-${DateTime.now().millisecondsSinceEpoch}',
      sessionId: session.id,
      petId: pet.id,
      summary: parsed.summary,
      findings: parsed.findings,
      recommendations: parsed.recommendations,
      urgency: parsed.urgency,
      thinking: parsed.thinking,
      modelId: parsed.modelId,
      inputTokens: parsed.inputTokens,
      outputTokens: parsed.outputTokens,
      cacheReadTokens: parsed.cacheReadTokens,
      generatedAt: DateTime.now().toUtc(),
    );
  }
}
