import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../models/alarm_thresholds.dart';
import '../models/insight.dart';
import '../models/pet.dart';
import '../models/reading.dart';
import '../models/session.dart';
import '../../signal/species_baselines.dart';
import 'database.dart';

class PetRepository {
  PetRepository(this._db);
  final AppDatabase _db;

  Future<List<Pet>> all(String clinicId) async {
    final rows = await (_db.select(_db.pets)
          ..where((t) => t.clinicId.equals(clinicId)))
        .get();
    return rows.map(_toModel).toList();
  }

  Stream<List<Pet>> watchAll(String clinicId) =>
      (_db.select(_db.pets)..where((t) => t.clinicId.equals(clinicId)))
          .watch()
          .map((rows) => rows.map(_toModel).toList());

  Future<Pet?> byId(String id) async {
    final row =
        await (_db.select(_db.pets)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<Pet> create({
    required String clinicId,
    required String name,
    required Species species,
    required String breed,
    required PetSex sex,
    required double weightKg,
    required DateTime dateOfBirth,
    String ownerName = '',
    String ownerEmail = '',
    String ownerPhone = '',
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc();
    final pet = Pet(
      id: const Uuid().v4(),
      clinicId: clinicId,
      name: name,
      species: species,
      breed: breed,
      sex: sex,
      weightKg: weightKg,
      dateOfBirth: dateOfBirth,
      ownerName: ownerName,
      ownerEmail: ownerEmail,
      ownerPhone: ownerPhone,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.pets).insert(_toRow(pet));
    final thresholds = AlarmThresholds.defaults(
      petId: pet.id,
      baseline: pet.baseline,
    );
    await _db.into(_db.alarmThresholdsTable).insert(_thresholdsToRow(thresholds));
    return pet;
  }

  Future<void> update(Pet pet) =>
      _db.update(_db.pets).replace(_toRow(pet));

  Future<void> delete(String id) =>
      (_db.delete(_db.pets)..where((t) => t.id.equals(id))).go();

  Pet _toModel(PetData r) => Pet(
        id: r.id,
        clinicId: r.clinicId,
        name: r.name,
        species: Species.values.byName(r.species),
        breed: r.breed,
        sex: PetSex.values.byName(r.sex),
        weightKg: r.weightKg,
        dateOfBirth: r.dateOfBirth,
        ownerName: r.ownerName,
        ownerEmail: r.ownerEmail,
        ownerPhone: r.ownerPhone,
        notes: r.notes,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  PetsCompanion _toRow(Pet pet) => PetsCompanion.insert(
        id: pet.id,
        clinicId: pet.clinicId,
        name: pet.name,
        species: pet.species.name,
        breed: Value(pet.breed),
        sex: pet.sex.name,
        weightKg: pet.weightKg,
        dateOfBirth: pet.dateOfBirth,
        ownerName: Value(pet.ownerName),
        ownerEmail: Value(pet.ownerEmail),
        ownerPhone: Value(pet.ownerPhone),
        notes: Value(pet.notes),
        createdAt: pet.createdAt,
        updatedAt: pet.updatedAt,
      );

  AlarmThresholdsTableCompanion _thresholdsToRow(AlarmThresholds t) =>
      AlarmThresholdsTableCompanion.insert(
        petId: t.petId,
        hrMin: t.hrMin,
        hrMax: t.hrMax,
        tempMinC: t.tempMinC,
        tempMaxC: t.tempMaxC,
        respMin: t.respMin,
        respMax: t.respMax,
        spo2Min: Value(t.spo2Min),
        alarmBeep: Value(t.alarmBeep),
        autoMonitor: Value(t.autoMonitor),
      );
}

class AlarmThresholdRepository {
  AlarmThresholdRepository(this._db);
  final AppDatabase _db;

  Future<AlarmThresholds?> forPet(String petId) async {
    final row = await (_db.select(_db.alarmThresholdsTable)
          ..where((t) => t.petId.equals(petId)))
        .getSingleOrNull();
    if (row == null) return null;
    return AlarmThresholds(
      petId: row.petId,
      spo2Min: row.spo2Min,
      hrMin: row.hrMin,
      hrMax: row.hrMax,
      tempMinC: row.tempMinC,
      tempMaxC: row.tempMaxC,
      respMin: row.respMin,
      respMax: row.respMax,
      alarmBeep: row.alarmBeep,
      autoMonitor: row.autoMonitor,
    );
  }

  Future<void> upsert(AlarmThresholds t) =>
      _db.into(_db.alarmThresholdsTable).insertOnConflictUpdate(
            AlarmThresholdsTableCompanion.insert(
              petId: t.petId,
              hrMin: t.hrMin,
              hrMax: t.hrMax,
              tempMinC: t.tempMinC,
              tempMaxC: t.tempMaxC,
              respMin: t.respMin,
              respMax: t.respMax,
              spo2Min: Value(t.spo2Min),
              alarmBeep: Value(t.alarmBeep),
              autoMonitor: Value(t.autoMonitor),
            ),
          );
}

class SessionRepository {
  SessionRepository(this._db);
  final AppDatabase _db;

  Future<MonitoringSession> startSession({
    required String petId,
    required String clinicId,
    required String startedBy,
    required String deviceId,
    required String deviceName,
  }) async {
    final session = MonitoringSession(
      id: const Uuid().v4(),
      petId: petId,
      clinicId: clinicId,
      startedAt: DateTime.now().toUtc(),
      endedAt: null,
      startedBy: startedBy,
      notes: '',
      deviceId: deviceId,
      deviceName: deviceName,
      summary: SessionSummary.empty,
    );
    await _db.into(_db.sessions).insert(SessionsCompanion.insert(
          id: session.id,
          petId: session.petId,
          clinicId: session.clinicId,
          startedAt: session.startedAt,
          startedBy: Value(session.startedBy),
          deviceId: Value(session.deviceId),
          deviceName: Value(session.deviceName),
          summaryJson: Value(jsonEncode(session.summary.toJson())),
        ));
    return session;
  }

  Future<void> endSession({
    required String sessionId,
    required SessionSummary summary,
    String notes = '',
  }) =>
      (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId))).write(
        SessionsCompanion(
          endedAt: Value(DateTime.now().toUtc()),
          notes: Value(notes),
          summaryJson: Value(jsonEncode(summary.toJson())),
        ),
      );

  Future<List<MonitoringSession>> forPet(String petId) async {
    final rows = await (_db.select(_db.sessions)
          ..where((t) => t.petId.equals(petId))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<MonitoringSession?> byId(String id) async {
    final row = await (_db.select(_db.sessions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<void> insertVitalReading(VitalReading r) =>
      _db.into(_db.vitalReadingsTable).insert(VitalReadingsTableCompanion.insert(
            sessionId: r.sessionId,
            timestamp: r.timestamp,
            kind: r.kind.name,
            value: r.value,
            secondaryValue: Value(r.secondaryValue),
            tertiaryValue: Value(r.tertiaryValue),
          ));

  Future<List<VitalReading>> readings(String sessionId, VitalKind kind) async {
    final rows = await (_db.select(_db.vitalReadingsTable)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.kind.equals(kind.name))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
    return rows
        .map((r) => VitalReading(
              sessionId: r.sessionId,
              timestamp: r.timestamp,
              kind: VitalKind.values.byName(r.kind),
              value: r.value,
              secondaryValue: r.secondaryValue,
              tertiaryValue: r.tertiaryValue,
            ))
        .toList();
  }

  MonitoringSession _toModel(SessionData r) => MonitoringSession(
        id: r.id,
        petId: r.petId,
        clinicId: r.clinicId,
        startedAt: r.startedAt,
        endedAt: r.endedAt,
        startedBy: r.startedBy,
        notes: r.notes,
        deviceId: r.deviceId,
        deviceName: r.deviceName,
        summary: _parseSummary(r.summaryJson),
      );

  SessionSummary _parseSummary(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    if (m.isEmpty) return SessionSummary.empty;
    return SessionSummary(
      minHr: (m['min_hr'] as num?)?.toDouble(),
      maxHr: (m['max_hr'] as num?)?.toDouble(),
      meanHr: (m['mean_hr'] as num?)?.toDouble(),
      minSpo2: (m['min_spo2'] as num?)?.toDouble(),
      maxSpo2: (m['max_spo2'] as num?)?.toDouble(),
      meanSpo2: (m['mean_spo2'] as num?)?.toDouble(),
      minTempC: (m['min_temp_c'] as num?)?.toDouble(),
      maxTempC: (m['max_temp_c'] as num?)?.toDouble(),
      meanTempC: (m['mean_temp_c'] as num?)?.toDouble(),
      respMean: (m['resp_mean'] as num?)?.toDouble(),
      nibpSystolic: (m['nibp_systolic'] as num?)?.toInt(),
      nibpDiastolic: (m['nibp_diastolic'] as num?)?.toInt(),
      nibpMean: (m['nibp_mean'] as num?)?.toInt(),
      beatCount: (m['beat_count'] as num?)?.toInt() ?? 0,
      rmssdMs: (m['rmssd_ms'] as num?)?.toDouble() ?? 0,
      sdnnMs: (m['sdnn_ms'] as num?)?.toDouble() ?? 0,
      signalQuality: (m['signal_quality'] as num?)?.toDouble() ?? 0,
      alarmTriggers: ((m['alarm_triggers'] as Map?) ?? const <String, int>{})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
    );
  }
}

class InsightRepository {
  InsightRepository(this._db);
  final AppDatabase _db;

  Future<void> save(SessionInsight insight) =>
      _db.into(_db.insights).insertOnConflictUpdate(InsightsCompanion.insert(
            id: insight.id,
            sessionId: insight.sessionId,
            petId: insight.petId,
            summary: insight.summary,
            findingsJson: Value(jsonEncode(insight.findings)),
            recommendationsJson:
                Value(jsonEncode(insight.recommendations)),
            urgency: Value(insight.urgency.name),
            thinking: Value(insight.thinking),
            modelId: insight.modelId,
            inputTokens: insight.inputTokens,
            outputTokens: insight.outputTokens,
            cacheReadTokens: insight.cacheReadTokens,
            generatedAt: insight.generatedAt,
          ));

  Future<List<SessionInsight>> forSession(String sessionId) async {
    final rows = await (_db.select(_db.insights)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<List<SessionInsight>> forPet(String petId, {int limit = 50}) async {
    final rows = await (_db.select(_db.insights)
          ..where((t) => t.petId.equals(petId))
          ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)])
          ..limit(limit))
        .get();
    return rows.map(_toModel).toList();
  }

  SessionInsight _toModel(InsightData r) => SessionInsight(
        id: r.id,
        sessionId: r.sessionId,
        petId: r.petId,
        summary: r.summary,
        findings: (jsonDecode(r.findingsJson) as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        recommendations: (jsonDecode(r.recommendationsJson) as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        urgency: InsightUrgency.values.byName(r.urgency),
        thinking: r.thinking,
        modelId: r.modelId,
        inputTokens: r.inputTokens,
        outputTokens: r.outputTokens,
        cacheReadTokens: r.cacheReadTokens,
        generatedAt: r.generatedAt,
      );
}
