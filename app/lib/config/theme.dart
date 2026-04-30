import 'package:flutter/material.dart';

class PetVitalsTheme {
  PetVitalsTheme._();

  static const Color brandTeal = Color(0xFF0EA5A4);
  static const Color brandNavy = Color(0xFF0F172A);
  static const Color alarmRed = Color(0xFFDC2626);
  static const Color alarmAmber = Color(0xFFF59E0B);
  static const Color signalGreen = Color(0xFF16A34A);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandTeal,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        cardTheme: const CardTheme(margin: EdgeInsets.zero, elevation: 0),
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandTeal,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: brandNavy,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      );
}
