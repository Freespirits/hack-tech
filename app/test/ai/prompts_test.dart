import 'package:flutter_test/flutter_test.dart';
import 'package:petvitals/ai/prompts.dart';
import 'package:petvitals/data/models/insight.dart';
import 'package:petvitals/data/models/pet.dart';
import 'package:petvitals/data/models/session.dart';
import 'package:petvitals/signal/species_baselines.dart';

void main() {
  Pet samplePet() => Pet(
        id: 'pet-1',
        clinicId: 'clinic-1',
        name: 'Bella',
        species: Species.dog,
        breed: 'Beagle',
        sex: PetSex.spayed,
        weightKg: 12.5,
        dateOfBirth: DateTime(2022, 1, 1),
        ownerName: 'Sam',
        ownerEmail: 's@example.com',
        ownerPhone: '+10000',
        notes: 'recovering from surgery',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  MonitoringSession sampleSession({String id = 'sess-1'}) => MonitoringSession(
        id: id,
        petId: 'pet-1',
        clinicId: 'clinic-1',
        startedAt: DateTime(2026, 4, 27, 10),
        endedAt: DateTime(2026, 4, 27, 10, 5),
        startedBy: 'vet@example.com',
        notes: '',
        deviceId: 'AA:BB',
        deviceName: 'AM4100',
        summary: const SessionSummary(
          minHr: 90,
          maxHr: 140,
          meanHr: 115,
          minSpo2: 95,
          maxSpo2: 99,
          meanSpo2: 97,
          minTempC: 38.5,
          maxTempC: 39.0,
          meanTempC: 38.7,
          respMean: 22,
          nibpSystolic: 130,
          nibpDiastolic: 80,
          nibpMean: 100,
          beatCount: 240,
          rmssdMs: 65,
          sdnnMs: 80,
          signalQuality: 0.82,
          alarmTriggers: <String, int>{},
        ),
      );

  test('toJson includes all required top-level keys', () {
    final pet = samplePet();
    final req = InsightRequest(
      pet: pet,
      session: sampleSession(),
      recentSessions: const [],
      locale: 'en',
    );
    final json = req.toJson();
    expect(json.keys, containsAll(<String>[
      'pet', 'baseline', 'session', 'recent_sessions', 'locale',
    ]));
    expect((json['baseline']! as Map)['species'], 'dog');
  });

  test('recent sessions deduplicate the current session and skip ongoing', () {
    final ongoing = MonitoringSession(
      id: 'sess-ongoing',
      petId: 'pet-1',
      clinicId: 'clinic-1',
      startedAt: DateTime(2026, 4, 28),
      endedAt: null,
      startedBy: '',
      notes: '',
      deviceId: '',
      deviceName: '',
      summary: SessionSummary.empty,
    );
    final req = InsightRequest(
      pet: samplePet(),
      session: sampleSession(),
      recentSessions: <MonitoringSession>[
        sampleSession(),
        ongoing,
        sampleSession(id: 'sess-2'),
      ],
      locale: 'en',
    );
    final json = req.toJson();
    final recent = json['recent_sessions']! as List;
    expect(recent.length, 1);
    expect((recent.first as Map)['id'], 'sess-2');
  });

  test('InsightResponse parses minimal payload with defaults', () {
    final r = InsightResponse.fromJson(<String, Object?>{
      'summary': 'Looks normal.',
      'findings': <String>['HR within range'],
      'recommendations': <String>['Recheck in 30 days'],
      'urgency': 'routine',
      'model': 'claude-opus-4-7',
      'usage': {'input_tokens': 100, 'output_tokens': 50, 'cache_read_input_tokens': 80},
    });
    expect(r.summary, 'Looks normal.');
    expect(r.urgency, InsightUrgency.routine);
    expect(r.cacheReadTokens, 80);
    expect(r.modelId, 'claude-opus-4-7');
  });

  test('InsightResponse falls back to defaults on missing fields', () {
    final r = InsightResponse.fromJson(<String, Object?>{});
    expect(r.summary, '');
    expect(r.urgency, InsightUrgency.routine);
    expect(r.findings, isEmpty);
    expect(r.recommendations, isEmpty);
  });
}
