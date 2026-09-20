import 'package:flutter/material.dart';

/// Graphite's two hand-assigned renderings (ADR-0009).
final class ScheduleTheme {
  static ThemeData light = _theme(_light);
  static ThemeData dark = _theme(_dark);

  static ThemeData _theme(ColorScheme colors) => ThemeData(
    colorScheme: colors,
    useMaterial3: true,
    dividerColor: colors.outline,
    extensions: [
      colors.brightness == Brightness.dark
          ? ScheduleGridColors.dark
          : ScheduleGridColors.light,
    ],
  );

  static const _light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xff315d58),
    onPrimary: Colors.white,
    primaryContainer: Color(0xffd3eae3),
    onPrimaryContainer: Color(0xff173c36),
    secondary: Color(0xff365b79),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xffddeaf3),
    onSecondaryContainer: Color(0xff213f55),
    tertiary: Color(0xff68517a),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xffeacfc4),
    onTertiaryContainer: Color(0xff3d2421),
    error: Color(0xffa83639),
    onError: Colors.white,
    errorContainer: Color(0xfff9dad7),
    onErrorContainer: Color(0xff502022),
    surface: Color(0xfff5f6f4),
    onSurface: Color(0xff20272b),
    surfaceDim: Color(0xffd9dede),
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xfff0f2f1),
    surfaceContainer: Color(0xffe9edec),
    surfaceContainerHigh: Color(0xffdee4e3),
    surfaceContainerHighest: Color(0xffd3dcdc),
    onSurfaceVariant: Color(0xff43535b),
    outline: Color(0xff53646c),
    outlineVariant: Color(0xffb9c5c7),
    inverseSurface: Color(0xff273137),
    onInverseSurface: Color(0xfff4f6f7),
    inversePrimary: Color(0xffa5e3d3),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xff37d6b4),
    onPrimary: Color(0xff06251e),
    primaryContainer: Color(0xff12483d),
    onPrimaryContainer: Color(0xffc8fff2),
    secondary: Color(0xff72b7ff),
    onSecondary: Color(0xff08243e),
    secondaryContainer: Color(0xff173c5d),
    onSecondaryContainer: Color(0xffdaebff),
    tertiary: Color(0xffc69bff),
    onTertiary: Color(0xff27123d),
    tertiaryContainer: Color(0xff664444),
    onTertiaryContainer: Color(0xfff4f6f7),
    error: Color(0xffffb0a8),
    onError: Color(0xff331012),
    errorContainer: Color(0xff5a2428),
    onErrorContainer: Color(0xffffe2de),
    surface: Color(0xff151a1f),
    onSurface: Color(0xfff4f6f7),
    surfaceDim: Color(0xff090b0d),
    surfaceBright: Color(0xff303a43),
    surfaceContainerLowest: Color(0xff0d1013),
    surfaceContainerLow: Color(0xff12171b),
    surfaceContainer: Color(0xff1c2329),
    surfaceContainerHigh: Color(0xff222a31),
    surfaceContainerHighest: Color(0xff29333b),
    onSurfaceVariant: Color(0xffc2cbd1),
    outline: Color(0xff8d9ba4),
    outlineVariant: Color(0xff3e4851),
    inverseSurface: Color(0xffe3e8eb),
    onInverseSurface: Color(0xff172027),
    inversePrimary: Color(0xff315d58),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );
}

@immutable
final class ScheduleGridColors extends ThemeExtension<ScheduleGridColors> {
  const ScheduleGridColors({
    required this.covered,
    required this.onCovered,
    required this.shortOne,
    required this.onShortOne,
    required this.shortSeveral,
    required this.onShortSeveral,
    required this.rosterRule,
    required this.rosterText,
    required this.todayOutline,
  });

  final Color covered;
  final Color onCovered;
  final Color shortOne;
  final Color onShortOne;
  final Color shortSeveral;
  final Color onShortSeveral;
  final Color rosterRule;
  final Color rosterText;
  final Color todayOutline;

  static const light = ScheduleGridColors(
    covered: Color(0xffd8e4e8),
    onCovered: Color(0xff17282e),
    shortOne: Color(0xfff0d8b1),
    onShortOne: Color(0xff342714),
    shortSeveral: Color(0xffe9bdba),
    onShortSeveral: Color(0xff3d1e20),
    rosterRule: Color(0xff405a62),
    rosterText: Color(0xff273b42),
    todayOutline: Color(0xff315d58),
  );

  static const dark = ScheduleGridColors(
    covered: Color(0xff34444a),
    onCovered: Color(0xfff4f6f7),
    shortOne: Color(0xff6a5134),
    onShortOne: Color(0xfff4f6f7),
    shortSeveral: Color(0xff873e43),
    onShortSeveral: Color(0xfff4f6f7),
    rosterRule: Color(0xffa7bbc3),
    rosterText: Color(0xffd7e3e7),
    todayOutline: Color(0xff37d6b4),
  );

  static ScheduleGridColors of(BuildContext context) =>
      Theme.of(context).extension<ScheduleGridColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  ScheduleGridColors copyWith({
    Color? covered,
    Color? onCovered,
    Color? shortOne,
    Color? onShortOne,
    Color? shortSeveral,
    Color? onShortSeveral,
    Color? rosterRule,
    Color? rosterText,
    Color? todayOutline,
  }) => ScheduleGridColors(
    covered: covered ?? this.covered,
    onCovered: onCovered ?? this.onCovered,
    shortOne: shortOne ?? this.shortOne,
    onShortOne: onShortOne ?? this.onShortOne,
    shortSeveral: shortSeveral ?? this.shortSeveral,
    onShortSeveral: onShortSeveral ?? this.onShortSeveral,
    rosterRule: rosterRule ?? this.rosterRule,
    rosterText: rosterText ?? this.rosterText,
    todayOutline: todayOutline ?? this.todayOutline,
  );

  @override
  ScheduleGridColors lerp(ThemeExtension<ScheduleGridColors>? other, double t) {
    if (other is! ScheduleGridColors) return this;
    return ScheduleGridColors(
      covered: Color.lerp(covered, other.covered, t)!,
      onCovered: Color.lerp(onCovered, other.onCovered, t)!,
      shortOne: Color.lerp(shortOne, other.shortOne, t)!,
      onShortOne: Color.lerp(onShortOne, other.onShortOne, t)!,
      shortSeveral: Color.lerp(shortSeveral, other.shortSeveral, t)!,
      onShortSeveral: Color.lerp(onShortSeveral, other.onShortSeveral, t)!,
      rosterRule: Color.lerp(rosterRule, other.rosterRule, t)!,
      rosterText: Color.lerp(rosterText, other.rosterText, t)!,
      todayOutline: Color.lerp(todayOutline, other.todayOutline, t)!,
    );
  }
}
