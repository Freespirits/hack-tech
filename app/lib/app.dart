import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/theme.dart';
import 'core/di.dart';
import 'ui/screens/live_session_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/pet_form_screen.dart';
import 'ui/screens/pet_list_screen.dart';
import 'ui/screens/session_detail_screen.dart';

class PetVitalsApp extends ConsumerWidget {
  const PetVitalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.watch(supabaseProvider);
    final router = GoRouter(
      initialLocation: supabase.isAuthenticated ? '/pets' : '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/pets',
          builder: (_, __) => const PetListScreen(),
        ),
        GoRoute(
          path: '/pets/new',
          builder: (_, __) => const PetFormScreen(),
        ),
        GoRoute(
          path: '/pets/:petId/session',
          builder: (_, state) => LiveSessionScreen(
            petId: state.pathParameters['petId']!,
          ),
        ),
        GoRoute(
          path: '/sessions/:sessionId',
          builder: (_, state) => SessionDetailScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'PetVitals',
      theme: PetVitalsTheme.light(),
      darkTheme: PetVitalsTheme.dark(),
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('de'),
        Locale('es'),
        Locale('fr'),
        Locale('pt'),
        Locale('zh'),
      ],
    );
  }
}
