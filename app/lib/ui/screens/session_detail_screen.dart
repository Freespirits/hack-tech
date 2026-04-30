import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/env.dart';
import '../../core/di.dart';
import '../../data/models/insight.dart';
import '../../data/models/reading.dart';
import '../../data/models/session.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _generating = false;
  String? _generateError;

  Future<void> _generateInsight(MonitoringSession s) async {
    setState(() {
      _generating = true;
      _generateError = null;
    });
    try {
      final petRepo = ref.read(petRepositoryProvider);
      final pet = await petRepo.byId(s.petId);
      if (pet == null) throw StateError('Pet missing');
      final recent = await ref.read(sessionRepositoryProvider).forPet(pet.id);
      final supabase = ref.read(supabaseProvider);
      final accessToken =
          supabase.raw.auth.currentSession?.accessToken;
      if (accessToken == null) throw StateError('Not signed in');

      final insight = await ref.read(insightClientProvider).generate(
            pet: pet,
            session: s,
            recentSessions: recent,
            accessToken: accessToken,
            locale: Env.defaultInsightLocale,
          );
      await ref.read(insightRepositoryProvider).save(insight);
    } on Object catch (e) {
      setState(() => _generateError = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync =
        ref.watch(_sessionDetailProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Session not found'));
          }
          final session = data.session;
          final insights = data.insights;
          final hr = data.hr;
          final spo2 = data.spo2;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                DateFormat.yMMMd().add_Hm().format(session.startedAt.toLocal()),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (session.duration != null)
                Text('Duration: ${session.duration!.inMinutes} min'),
              const SizedBox(height: 16),
              _SummaryCard(summary: session.summary),
              const SizedBox(height: 24),
              if (hr.isNotEmpty)
                _ChartSection(
                  title: 'Heart rate (BPM)',
                  series: hr,
                  color: Colors.red,
                ),
              if (spo2.isNotEmpty)
                _ChartSection(
                  title: 'SpO₂ (%)',
                  series: spo2,
                  color: Colors.blue,
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'AI insights',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _generating ? null : () => _generateInsight(session),
                    icon: _generating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(insights.isEmpty ? 'Generate' : 'Regenerate'),
                  ),
                ],
              ),
              if (_generateError != null) ...[
                const SizedBox(height: 8),
                Text(_generateError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              if (insights.isEmpty)
                const Text(
                  'No insights yet. Tap “Generate” to ask Claude to read the '
                  'session and produce a vet-facing summary.',
                ),
              for (final insight in insights) _InsightCard(insight: insight),
            ],
          );
        },
      ),
    );
  }
}

class _SessionDetail {
  const _SessionDetail({
    required this.session,
    required this.insights,
    required this.hr,
    required this.spo2,
  });
  final MonitoringSession session;
  final List<SessionInsight> insights;
  final List<VitalReading> hr;
  final List<VitalReading> spo2;
}

final _sessionDetailProvider =
    FutureProvider.family.autoDispose<_SessionDetail?, String>(
  (ref, id) async {
    final session = await ref.watch(sessionRepositoryProvider).byId(id);
    if (session == null) return null;
    final insights =
        await ref.watch(insightRepositoryProvider).forSession(id);
    final hr = await ref
        .watch(sessionRepositoryProvider)
        .readings(id, VitalKind.heartRate);
    final spo2 = await ref
        .watch(sessionRepositoryProvider)
        .readings(id, VitalKind.spo2);
    return _SessionDetail(
      session: session,
      insights: insights,
      hr: hr,
      spo2: spo2,
    );
  },
);

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final SessionSummary summary;
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _kv('HR (mean)',
                summary.meanHr == null ? '—' : '${summary.meanHr!.round()} bpm'),
            _kv('SpO₂ (mean)',
                summary.meanSpo2 == null ? '—' : '${summary.meanSpo2!.round()} %'),
            _kv('Temp (mean)',
                summary.meanTempC == null ? '—' : '${summary.meanTempC!.toStringAsFixed(1)} °C'),
            _kv('Resp (mean)',
                summary.respMean == null ? '—' : '${summary.respMean!.round()} rpm'),
            _kv('Beats analysed', '${summary.beatCount}'),
            _kv('RMSSD', '${summary.rmssdMs.toStringAsFixed(1)} ms'),
            _kv('Signal quality',
                '${(summary.signalQuality * 100).round()} %'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(v,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      );
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.title,
    required this.series,
    required this.color,
  });
  final String title;
  final List<VitalReading> series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    final start = series.first.timestamp;
    for (final r in series) {
      final t =
          r.timestamp.difference(start).inMilliseconds / 60000.0; // minutes
      spots.add(FlSpot(t, r.value));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                lineTouchData: const LineTouchData(enabled: true),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    color: color,
                    isCurved: true,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final SessionInsight insight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (insight.urgency) {
      InsightUrgency.routine => (Colors.green, 'Routine'),
      InsightUrgency.monitor => (Colors.amber, 'Monitor'),
      InsightUrgency.urgent => (scheme.error, 'Urgent'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Text(
                  '${insight.modelId} • ${insight.outputTokens} tok',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              insight.summary,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (insight.findings.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Findings',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              for (final f in insight.findings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $f'),
                ),
            ],
            if (insight.recommendations.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Recommendations',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              for (final r in insight.recommendations)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $r'),
                ),
            ],
            if (insight.thinking.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                title: const Text('Reasoning',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                children: [
                  Text(insight.thinking,
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
