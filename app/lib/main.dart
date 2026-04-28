import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di.dart';
import 'data/remote/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabase = await SupabaseGateway.initialize();
  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(supabase),
      ],
      child: const PetVitalsApp(),
    ),
  );
}
