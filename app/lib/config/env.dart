/// Environment configuration. Values come from `--dart-define`s passed
/// at build time, e.g.:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
library;

class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// When true, raw BLE traffic is dumped to a rotating file in the
  /// app's documents directory. Off by default — the dump file can
  /// grow at ~1 MB / hour during active monitoring.
  static const bool bleDebugLogging = bool.fromEnvironment(
    'BLE_DEBUG_LOGGING',
    defaultValue: false,
  );

  /// Default locale for AI insight generation. Override per-clinic.
  static const String defaultInsightLocale = String.fromEnvironment(
    'INSIGHT_LOCALE',
    defaultValue: 'en',
  );
}
