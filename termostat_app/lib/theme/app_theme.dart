import 'package:flutter/material.dart';

/// Shared quiet palette: neutral surfaces, readable type, one blue-grey accent.
/// Uses bundled platform fonts only; no network fonts or new dependency.
class AppTheme {
  static ThemeData get light => build(Brightness.light);
  static ThemeData get dark => build(Brightness.dark);

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? const Color(0xFF151A1D) : const Color(0xFFF5F7F8);
    final surface = dark ? const Color(0xFF1E252A) : Colors.white;
    final border = dark ? const Color(0xFF3F4B54) : const Color(0xFFDDE3E7);
    final primary = dark ? const Color(0xFFA2CDE0) : const Color(0xFF2B6076);
    final colors = ColorScheme.fromSeed(
            seedColor: const Color(0xFF2B6076), brightness: brightness)
        .copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF0C3546) : Colors.white,
      surface: surface,
      onSurface: dark ? const Color(0xFFEDF2F4) : const Color(0xFF252E34),
      onSurfaceVariant:
          dark ? const Color(0xFFBCC8CE) : const Color(0xFF59666E),
      surfaceContainerLowest: canvas,
      surfaceContainerLow:
          dark ? const Color(0xFF252E34) : const Color(0xFFF0F4F6),
      surfaceContainer:
          dark ? const Color(0xFF29333A) : const Color(0xFFEAF0F3),
      surfaceContainerHigh:
          dark ? const Color(0xFF303C44) : const Color(0xFFE4ECEF),
      outline: dark ? const Color(0xFF8698A3) : const Color(0xFF7B8993),
      outlineVariant: border,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall
            ?.copyWith(fontSize: 26, fontWeight: FontWeight.w600),
        titleLarge: base.textTheme.titleLarge
            ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: base.textTheme.titleMedium
            ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge:
            base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
        bodyMedium:
            base.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
        bodySmall:
            base.textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.4),
        labelLarge: base.textTheme.labelLarge
            ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: 24,
        titleTextStyle: TextStyle(
            fontSize: 26, fontWeight: FontWeight.w600, color: colors.onSurface),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(side: BorderSide(color: border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: shape,
        side: BorderSide(color: colors.outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      )),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        minimumSize: const Size(44, 48),
        elevation: 0,
        shape: shape,
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 1.5)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: shape),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 24),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: shape,
          backgroundColor: colors.inverseSurface,
          contentTextStyle:
              TextStyle(color: colors.onInverseSurface, fontSize: 14)),
    );
  }
}
