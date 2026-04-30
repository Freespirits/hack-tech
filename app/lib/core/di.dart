/// Riverpod providers — wire BLE, DB, repositories and the AI client
/// together. Any UI screen pulls what it needs from these providers
/// rather than importing concrete classes directly, so tests can
/// override them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/insight_client.dart';
import '../ble/ble_service.dart';
import '../data/local/database.dart';
import '../data/local/repositories.dart';
import '../data/remote/supabase_client.dart';
import '../data/remote/sync.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final petRepositoryProvider = Provider<PetRepository>(
  (ref) => PetRepository(ref.watch(databaseProvider)),
);

final alarmThresholdRepositoryProvider = Provider<AlarmThresholdRepository>(
  (ref) => AlarmThresholdRepository(ref.watch(databaseProvider)),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(databaseProvider)),
);

final insightRepositoryProvider = Provider<InsightRepository>(
  (ref) => InsightRepository(ref.watch(databaseProvider)),
);

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(svc.dispose);
  return svc;
});

final supabaseProvider = Provider<SupabaseGateway>(
  (ref) => throw UnimplementedError(
    'supabaseProvider must be overridden after Supabase.initialize().',
  ),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(databaseProvider),
    ref.watch(supabaseProvider),
  ),
);

final insightClientProvider = Provider<InsightClient>(
  (ref) => InsightClient(),
);

/// The clinic the user is currently acting on behalf of. Selected
/// after sign-in if the user is a member of multiple clinics; pinned
/// to the only one otherwise.
final activeClinicIdProvider = StateProvider<String?>((_) => null);
