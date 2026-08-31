import 'package:flutter/material.dart';

/// Central theme definition implementing the Material 3 "astral" aesthetic:
/// a deep, calm primary, generous rounded corners, soft surfaces and a
/// consistent dark/light palette derived from a single seed color.
///
/// The theme is seed-color based so the whole scheme (primary/secondary/
/// tertiary, surfaces, states) is generated consistently and adapts to both
/// light and dark modes. Choose a vibrant seed in settings to restyle the
/// entire app.
class AppTheme {
  AppTheme._();

  /// Default seed color — an indigo/violet, matching the astral gradient feel.
  static const Color defaultSeed = Color(0xFF6750A4);

  /// Build the full [ThemeData] for a given mode and seed color.
  static ThemeData build({
    required Brightness brightness,
    required Color seedColor,
    bool useMaterial3 = true,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: useMaterial3,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamilyFallback: const ['MiSans', 'Roboto', 'sans-serif'],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  /// Light theme.
  static ThemeData light({Color seedColor = defaultSeed}) =>
      build(brightness: Brightness.light, seedColor: seedColor);

  /// Dark theme.
  static ThemeData dark({Color seedColor = defaultSeed}) =>
      build(brightness: Brightness.dark, seedColor: seedColor);
}
