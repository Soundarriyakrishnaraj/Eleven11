import 'package:material_ui/material_ui.dart';

import 'eink_palette.dart';

/// Available paper backgrounds for notes
class NotePaperStyle {
  const NotePaperStyle({
    required this.name,
    required this.background,
    required this.surface,
    required this.lineColor,
  });

  final String name;
  final Color background;
  final Color surface;
  final Color lineColor;
}

class NotePaperStyles {
  const NotePaperStyles._();

  static const NotePaperStyle paperWhite = NotePaperStyle(
    name: 'Paper White',
    background: EInkPalette.paperWhite,
    surface: Color(0xFFFFFFFF),
    lineColor: Color(0xFFE2DDD2),
  );

  static const NotePaperStyle warmIvory = NotePaperStyle(
    name: 'Warm Ivory',
    background: EInkPalette.ivory,
    surface: Color(0xFFFAF6EE),
    lineColor: Color(0xFFE0D7C6),
  );

  static const NotePaperStyle antiqueCream = NotePaperStyle(
    name: 'Antique Cream',
    background: EInkPalette.cream,
    surface: Color(0xFFF3EDE2),
    lineColor: Color(0xFFD6CBBB),
  );

  static const NotePaperStyle softSage = NotePaperStyle(
    name: 'Soft Sage',
    background: Color(0xFFF0F4EF),
    surface: Color(0xFFF7FAF6),
    lineColor: Color(0xFFD3E0D1),
  );

  static const NotePaperStyle coolMist = NotePaperStyle(
    name: 'Cool Mist',
    background: Color(0xFFEEF3F7),
    surface: Color(0xFFF6FAFC),
    lineColor: Color(0xFFD1DDE7),
  );

  static const List<NotePaperStyle> all = [
    paperWhite,
    warmIvory,
    antiqueCream,
    softSage,
    coolMist,
  ];
}

/// ThemeExtension for E-Ink specific UI properties (Notes highlighter colors,
/// paper backgrounds, ruled lines, e-paper borders).
@immutable
class Eleven11EInkExtension extends ThemeExtension<Eleven11EInkExtension> {
  const Eleven11EInkExtension({
    required this.isEInkMode,
    required this.paperBackground,
    required this.cardBackground,
    required this.inkColor,
    required this.mutedInkColor,
    required this.subtleBorder,
    required this.highlightYellow,
    required this.highlightGreen,
    required this.highlightOrange,
    required this.highlightPink,
    required this.highlightBlue,
    required this.ruledLineColor,
    required this.showRuledLines,
  });

  final bool isEInkMode;
  final Color paperBackground;
  final Color cardBackground;
  final Color inkColor;
  final Color mutedInkColor;
  final Color subtleBorder;

  // Highlighter colors
  final Color highlightYellow;
  final Color highlightGreen;
  final Color highlightOrange;
  final Color highlightPink;
  final Color highlightBlue;

  // Ruled paper
  final Color ruledLineColor;
  final bool showRuledLines;

  factory Eleven11EInkExtension.standard({
    bool isEInk = false,
    Color? paper,
    Color? ink,
    bool showRuled = false,
  }) {
    final p = paper ?? EInkPalette.paperWhite;
    final i = ink ?? EInkPalette.charcoal;

    return Eleven11EInkExtension(
      isEInkMode: isEInk,
      paperBackground: p,
      cardBackground: isEInk ? Color.alphaBlend(Colors.white.withValues(alpha: 0.6), p) : const Color(0xFF222222),
      inkColor: i,
      mutedInkColor: isEInk ? EInkPalette.slateGrey : const Color(0xFFB8B1A8),
      subtleBorder: isEInk ? Color.alphaBlend(EInkPalette.silverGrey, p) : const Color(0xFF3A3835),
      highlightYellow: const Color(0x66E8D79B), // Pale Yellow 40%
      highlightGreen: const Color(0x6697C1A9),  // Mint 40%
      highlightOrange: const Color(0x66E8AA7B), // Pale Orange 40%
      highlightPink: const Color(0x66DEABB7),   // Pale Pink 40%
      highlightBlue: const Color(0x669FB6CD),   // Powder Blue 40%
      ruledLineColor: const Color(0x40868E96),
      showRuledLines: showRuled,
    );
  }

  @override
  Eleven11EInkExtension copyWith({
    bool? isEInkMode,
    Color? paperBackground,
    Color? cardBackground,
    Color? inkColor,
    Color? mutedInkColor,
    Color? subtleBorder,
    Color? highlightYellow,
    Color? highlightGreen,
    Color? highlightOrange,
    Color? highlightPink,
    Color? highlightBlue,
    Color? ruledLineColor,
    bool? showRuledLines,
  }) {
    return Eleven11EInkExtension(
      isEInkMode: isEInkMode ?? this.isEInkMode,
      paperBackground: paperBackground ?? this.paperBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      inkColor: inkColor ?? this.inkColor,
      mutedInkColor: mutedInkColor ?? this.mutedInkColor,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      highlightYellow: highlightYellow ?? this.highlightYellow,
      highlightGreen: highlightGreen ?? this.highlightGreen,
      highlightOrange: highlightOrange ?? this.highlightOrange,
      highlightPink: highlightPink ?? this.highlightPink,
      highlightBlue: highlightBlue ?? this.highlightBlue,
      ruledLineColor: ruledLineColor ?? this.ruledLineColor,
      showRuledLines: showRuledLines ?? this.showRuledLines,
    );
  }

  @override
  Eleven11EInkExtension lerp(
    covariant ThemeExtension<Eleven11EInkExtension>? other,
    double t,
  ) {
    if (other is! Eleven11EInkExtension) return this;

    return Eleven11EInkExtension(
      isEInkMode: t < 0.5 ? isEInkMode : other.isEInkMode,
      paperBackground: Color.lerp(paperBackground, other.paperBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      inkColor: Color.lerp(inkColor, other.inkColor, t)!,
      mutedInkColor: Color.lerp(mutedInkColor, other.mutedInkColor, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      highlightYellow: Color.lerp(highlightYellow, other.highlightYellow, t)!,
      highlightGreen: Color.lerp(highlightGreen, other.highlightGreen, t)!,
      highlightOrange: Color.lerp(highlightOrange, other.highlightOrange, t)!,
      highlightPink: Color.lerp(highlightPink, other.highlightPink, t)!,
      highlightBlue: Color.lerp(highlightBlue, other.highlightBlue, t)!,
      ruledLineColor: Color.lerp(ruledLineColor, other.ruledLineColor, t)!,
      showRuledLines: t < 0.5 ? showRuledLines : other.showRuledLines,
    );
  }
}
