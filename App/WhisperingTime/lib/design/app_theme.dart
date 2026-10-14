import 'package:flutter/material.dart';

/// 统一的视觉尺寸；页面只决定布局，颜色与组件状态由主题负责。
abstract final class ImprintSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double section = 32;
  static const double page = 48;
}

@immutable
class ImprintTokens extends ThemeExtension<ImprintTokens> {
  const ImprintTokens({
    required this.quietSurface,
    required this.brandSurface,
    this.panelRadius = 18,
  });

  final Color quietSurface;
  final Color brandSurface;
  final double panelRadius;

  @override
  ImprintTokens copyWith({
    Color? quietSurface,
    Color? brandSurface,
    double? panelRadius,
  }) => ImprintTokens(
    quietSurface: quietSurface ?? this.quietSurface,
    brandSurface: brandSurface ?? this.brandSurface,
    panelRadius: panelRadius ?? this.panelRadius,
  );

  @override
  ImprintTokens lerp(covariant ImprintTokens? other, double t) {
    if (other == null) return this;
    return ImprintTokens(
      quietSurface: Color.lerp(quietSurface, other.quietSurface, t)!,
      brandSurface: Color.lerp(brandSurface, other.brandSurface, t)!,
      panelRadius: panelRadius + (other.panelRadius - panelRadius) * t,
    );
  }
}

abstract final class AppTheme {
  static ThemeData light({bool highContrast = false}) =>
      _build(Brightness.light, highContrast: highContrast);

  static ThemeData dark({bool highContrast = false}) =>
      _build(Brightness.dark, highContrast: highContrast);

  static ThemeData _build(Brightness brightness, {required bool highContrast}) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? const Color(0xFF1B1917) : const Color(0xFFF8F5F0);
    final surface = dark ? const Color(0xFF25221F) : const Color(0xFFFFFDFA);
    final quiet = dark ? const Color(0xFF302B26) : const Color(0xFFF0EAE2);
    final ink = dark ? const Color(0xFFF4EEE7) : const Color(0xFF29231E);
    final secondaryInk = dark
        ? const Color(0xFFCCBEB1)
        : const Color(0xFF6D6055);
    final primary = dark
        ? const Color(0xFFFFB38C)
        : highContrast
        ? const Color(0xFF753017)
        : const Color(0xFF963F24);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF963F24),
          brightness: brightness,
          contrastLevel: highContrast ? 1 : 0,
        ).copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF4B210F) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF4E2B1F)
              : const Color(0xFFFFE7D8),
          onPrimaryContainer: dark
              ? const Color(0xFFFFD9C6)
              : const Color(0xFF6B2D17),
          secondary: dark ? const Color(0xFFB5C8B5) : const Color(0xFF506753),
          onSecondary: dark ? const Color(0xFF233625) : Colors.white,
          secondaryContainer: dark
              ? const Color(0xFF303E32)
              : const Color(0xFFE2EBDE),
          onSecondaryContainer: dark
              ? const Color(0xFFDCE8D7)
              : const Color(0xFF354B37),
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: highContrast ? ink : secondaryInk,
          surfaceContainerLowest: dark ? canvas : Colors.white,
          surfaceContainerLow: surface,
          surfaceContainer: quiet,
          surfaceContainerHigh: dark
              ? const Color(0xFF3B342E)
              : const Color(0xFFEAE1D7),
          surfaceContainerHighest: dark
              ? const Color(0xFF443B33)
              : const Color(0xFFE2D7CB),
          outline: dark ? const Color(0xFF9D8D7E) : const Color(0xFF8D7C6D),
          outlineVariant: highContrast
              ? dark
                    ? const Color(0xFF9D8D7E)
                    : const Color(0xFF8D7C6D)
              : dark
              ? const Color(0xFF52473E)
              : const Color(0xFFDFD5CA),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final text = base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          displaySmall: TextStyle(
            fontSize: 40,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: -1,
          ),
          headlineLarge: TextStyle(
            fontSize: 32,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 26,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          titleMedium: TextStyle(
            fontSize: 17,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: ink),
          bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: ink),
          bodySmall: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: highContrast ? ink : secondaryInk,
          ),
          labelLarge: TextStyle(
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        )
        .apply(
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
          fontFamilyFallback: const [
            'PingFang SC',
            'Microsoft YaHei',
            'Noto Sans CJK SC',
            'sans-serif',
          ],
        );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
    );
    return base.copyWith(
      textTheme: text,
      extensions: [
        ImprintTokens(
          quietSurface: quiet,
          brandSurface: scheme.primaryContainer,
        ),
      ],
      appBarTheme: AppBarThemeData(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: button.copyWith(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.12)
                : scheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : scheme.onPrimary;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? scheme.primary
                  : scheme.outline,
              width: states.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: button),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStatePropertyAll(scheme.onSurfaceVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        errorMaxLines: 3,
        helperMaxLines: 3,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        textColor: ink,
        selectedColor: primary,
        selectedTileColor: scheme.primaryContainer,
        shape: shape,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        dividerColor: Colors.transparent,
        indicatorColor: primary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: quiet,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: shape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        backgroundColor: scheme.inverseSurface,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
