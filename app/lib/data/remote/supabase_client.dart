/// Thin wrapper around the Supabase client.
///
/// We split this from the rest of the app so tests can inject a fake
/// implementation and so the BLE/signal/UI layers never reach for
/// `Supabase.instance` directly.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';

class SupabaseGateway {
  SupabaseGateway._(this._client);
  final SupabaseClient _client;

  static Future<SupabaseGateway> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      debug: false,
    );
    return SupabaseGateway._(Supabase.instance.client);
  }

  /// For testing: pass a pre-built client (e.g. against a local
  /// `supabase start` instance).
  SupabaseGateway.withClient(this._client);

  SupabaseClient get raw => _client;

  bool get isAuthenticated => _client.auth.currentUser != null;
  String? get userId => _client.auth.currentUser?.id;
  String? get userEmail => _client.auth.currentUser?.email;

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) =>
      _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );

  Future<void> signOut() => _client.auth.signOut();

  Future<List<String>> myClinics() async {
    final rows = await _client
        .from('clinic_members')
        .select('clinic_id')
        .eq('user_id', _client.auth.currentUser!.id);
    return (rows as List).map((r) => r['clinic_id'] as String).toList();
  }
}
