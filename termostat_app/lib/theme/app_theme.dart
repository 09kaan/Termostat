import 'package:flutter/material.dart';

/// Style tokens only; never carry thermostat or device state.
class AppAppearance extends ThemeExtension<AppAppearance> {
  const AppAppearance({required this.warm});
  final bool warm;
  static bool isWarm(BuildContext context) =>
      Theme.of(context).extension<AppAppearance>()?.warm ?? false;
  @override
  AppAppearance copyWith({bool? warm}) =>
      AppAppearance(warm: warm ?? this.warm);
  @override
  AppAppearance lerp(covariant AppAppearance? other, double t) =>
      other == null || t < .5 ? this : other;
}

class AppTheme {
  static ThemeData get light => original(Brightness.light);
  static ThemeData get dark => original(Brightness.dark);
  static ThemeData forAppearance(String appearance, Brightness brightness) =>
      appearance == 'warm_minimal' ? warm(brightness) : original(brightness);

  /// Exact original blue Material theme, without the removed navigation bar.
  static ThemeData original(Brightness brightness) {
    if (brightness == Brightness.light) {
      return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue, brightness: brightness),
          extensions: const [AppAppearance(warm: false)]);
    }
    return ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: brightness,
            surface: const Color(0xFF1E1E1E),
            onSurface: Colors.white,
            surfaceContainerLowest: const Color(0xFF121212),
            primary: Colors.lightBlueAccent[400],
            onPrimary: Colors.white,
            secondary: Colors.cyanAccent[200],
            onSecondary: Colors.white,
            error: Colors.redAccent,
            onError: Colors.white,
            outline: Colors.grey[700]),
        textTheme: const TextTheme()
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
        extensions: const [AppAppearance(warm: false)]);
  }

  static ThemeData warm(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? const Color(0xFF211E1B) : const Color(0xFFF7F4ED);
    final surface = dark ? const Color(0xFF2D2722) : Colors.white;
    final border = dark ? const Color(0xFF51483F) : const Color(0xFFE5DED3);
    final primary = dark ? const Color(0xFFE8B39B) : const Color(0xFFA54D35);
    final colors = ColorScheme.fromSeed(
            seedColor: const Color(0xFFA54D35), brightness: brightness)
        .copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF482516) : Colors.white,
      secondaryContainer:
          dark ? const Color(0xFF50382D) : const Color(0xFFEFE5D7),
      onSecondaryContainer:
          dark ? const Color(0xFFF2D5C3) : const Color(0xFF6C4D3D),
      surface: surface,
      onSurface: dark ? const Color(0xFFF5F0E8) : const Color(0xFF292A27),
      onSurfaceVariant:
          dark ? const Color(0xFFD0BFB1) : const Color(0xFF76665B),
      surfaceContainerLowest: canvas,
      surfaceContainerLow:
          dark ? const Color(0xFF292A27) : const Color(0xFFF1EBE1),
      surfaceContainer:
          dark ? const Color(0xFF352D26) : const Color(0xFFEBE3D5),
      surfaceContainerHigh:
          dark ? const Color(0xFF40342A) : const Color(0xFFE4D9C8),
      outline: dark ? const Color(0xFFB39B87) : const Color(0xFF967D69),
      outlineVariant: border,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return base.copyWith(
      extensions: const [AppAppearance(warm: true)],
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
