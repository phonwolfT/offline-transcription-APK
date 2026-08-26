import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: const Color(0xFF6366F1), // Indigo 500
      scaffoldBackgroundColor: const Color(0xFFF3F4F6), // Gray 100
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6366F1),
        secondary: Color(0xFF8B5CF6), // Violet 500
        surface: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF818CF8), // Indigo 400
      scaffoldBackgroundColor: const Color(0xFF111827), // Gray 900
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF818CF8),
        secondary: Color(0xFFA78BFA), // Violet 400
        surface: Color(0xFF1F2937), // Gray 800
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1F2937),
        elevation: 0,
      ),
      useMaterial3: true,
    );
  }
}
