/// Best-effort upload of local sessions + waveforms to Supabase.
///
/// Strategy: enqueue a sync attempt at session-end and on app resume.
/// Failed pushes stay marked unsynced (`syncedAt IS NULL`) and retry on
/// the next opportunity. We never block the UI on a sync — local SQLite
/// is the source of truth.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';
import 'supabase_client.dart';

class SyncService {
  SyncService(this._db, this._supabase);
  final AppDatabase _db;
  final SupabaseGateway _supabase;

  /// Push every locally-completed session that hasn't been synced yet.
  /// Returns the number of sessions pushed.
  Future<int> pushPendingSessions() async {
    if (!_supabase.isAuthenticated) return 0;
    final pending = await (_db.select(_db.sessions)
          ..where((t) => t.endedAt.isNotNull() & t.syncedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.endedAt)]))
        .get();

    var pushed = 0;
    for (final s in pending) {
      try {
        await _supabase.raw.from('sessions').upsert({
          'id': s.id,
          'pet_id': s.petId,
          'clinic_id': s.clinicId,
          'started_at': s.startedAt.toIso8601String(),
          'ended_at': s.endedAt?.toIso8601String(),
          'started_by_user_id': _supabase.userId,
          'notes': s.notes,
          'device_id': s.deviceId,
          'device_name': s.deviceName,
          'summary': jsonDecode(s.summaryJson),
        });

        // Vital readings as JSON-batched rows.
        final vitals = await (_db.select(_db.vitalReadingsTable)
              ..where((t) => t.sessionId.equals(s.id)))
            .get();
        if (vitals.isNotEmpty) {
          await _supabase.raw.from('vital_readings').upsert(vitals
              .map((v) => {
                    'session_id': v.sessionId,
                    'timestamp': v.timestamp.toIso8601String(),
                    'kind': v.kind,
                    'value': v.value,
                    'secondary_value': v.secondaryValue,
                    'tertiary_value': v.tertiaryValue,
                  })
              .toList());
        }

        await (_db.update(_db.sessions)..where((t) => t.id.equals(s.id)))
            .write(SessionsCompanion(syncedAt: Value(DateTime.now().toUtc())));
        pushed += 1;
      } on Object catch (_) {
        // Leave unsynced and break — next opportunity will retry.
        // Don't poison the queue with one bad row.
        break;
      }
    }
    return pushed;
  }
}
