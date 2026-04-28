/// Local SQLite schema (Drift).
///
/// We store the **entire** session waveform losslessly here as int16
/// chunks of up to 1 second each. This costs ~7 MB per hour of ECG at
/// 250 Hz — trivial for modern phones — and lets the AI insight layer
/// re-analyze a session offline without round-tripping to the cloud.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Pets extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text()();
  TextColumn get name => text()();
  TextColumn get species => text()();
  TextColumn get breed => text().withDefault(const Constant(''))();
  TextColumn get sex => text()();
  RealColumn get weightKg => real()();
  DateTimeColumn get dateOfBirth => dateTime()();
  TextColumn get ownerName => text().withDefault(const Constant(''))();
  TextColumn get ownerEmail => text().withDefault(const Constant(''))();
  TextColumn get ownerPhone => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AlarmThresholdsTable extends Table {
  @override
  String get tableName => 'alarm_thresholds';

  TextColumn get petId => text()();
  RealColumn get spo2Min => real().withDefault(const Constant(94))();
  RealColumn get hrMin => real()();
  RealColumn get hrMax => real()();
  RealColumn get tempMinC => real()();
  RealColumn get tempMaxC => real()();
  RealColumn get respMin => real()();
  RealColumn get respMax => real()();
  BoolColumn get alarmBeep => boolean().withDefault(const Constant(true))();
  BoolColumn get autoMonitor => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {petId};
}

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get petId => text()();
  TextColumn get clinicId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get startedBy => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  TextColumn get deviceName => text().withDefault(const Constant(''))();

  // JSON-encoded SessionSummary.
  TextColumn get summaryJson =>
      text().withDefault(const Constant('{}'))();

  // Set when the row has been pushed up to Supabase.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class WaveformChunks extends Table {
  @override
  String get tableName => 'waveform_chunks';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();

  // 'ecg' | 'pleth' | 'resp'
  TextColumn get kind => text()();
  DateTimeColumn get startedAt => dateTime()();
  RealColumn get sampleHz => real()();

  // int16 samples, big-endian, length = samples * 2 bytes.
  BlobColumn get samples => blob()();
}

class VitalReadingsTable extends Table {
  @override
  String get tableName => 'vital_readings';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get kind => text()(); // VitalKind.name
  RealColumn get value => real()();
  RealColumn get secondaryValue => real().nullable()();
  RealColumn get tertiaryValue => real().nullable()();
}

class Insights extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get petId => text()();
  TextColumn get summary => text()();
  TextColumn get findingsJson => text().withDefault(const Constant('[]'))();
  TextColumn get recommendationsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get urgency => text().withDefault(const Constant('routine'))();
  TextColumn get thinking => text().withDefault(const Constant(''))();
  TextColumn get modelId => text()();
  IntColumn get inputTokens => integer()();
  IntColumn get outputTokens => integer()();
  IntColumn get cacheReadTokens => integer()();
  DateTimeColumn get generatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Pets,
    AlarmThresholdsTable,
    Sessions,
    WaveformChunks,
    VitalReadingsTable,
    Insights,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor for tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX vital_readings_session_kind_ts '
            'ON vital_readings (session_id, kind, timestamp);',
          );
          await customStatement(
            'CREATE INDEX waveform_chunks_session_kind '
            'ON waveform_chunks (session_id, kind, started_at);',
          );
          await customStatement(
            'CREATE INDEX sessions_pet_started '
            'ON sessions (pet_id, started_at DESC);',
          );
        },
      );

  /// Helper: bulk-insert a waveform chunk.
  Future<void> insertWaveformChunk({
    required String sessionId,
    required String kind,
    required DateTime startedAt,
    required double sampleHz,
    required List<int> samples,
  }) {
    final bytes = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(i * 2, samples[i].clamp(-32768, 32767));
    }
    return into(waveformChunks).insert(WaveformChunksCompanion.insert(
      sessionId: sessionId,
      kind: kind,
      startedAt: startedAt,
      sampleHz: sampleHz,
      samples: bytes.buffer.asUint8List(),
    ));
  }
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'petvitals.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
