import 'package:material_ui/material_ui.dart';

/// Represents a single curated E-Ink color with light and dark tint variants.
class EInkColorItem {
  const EInkColorItem({
    required this.name,
    required this.color,
    required this.lightTint,
    required this.darkTint,
    required this.category,
  });

  final String name;
  final Color color;
  final Color lightTint;
  final Color darkTint;
  final String category;
}

/// Comprehensive E-Ink Color Palette designed to simulate the look and feel of
/// modern color electronic paper (e-paper / E-Ink Kaleido/Gallery).
enum EInkPresetPalette {
  classicKaleido,
  coolNewspaper,
  nightEInk,
}

class EInkPaletteConfig {
  const EInkPaletteConfig({
    required this.name,
    required this.description,
    required this.background,
    required this.card,
    required this.border,
    required this.text1,
    required this.text2,
    required this.accent1,
    required this.accent2,
    required this.success,
    required this.warning,
  });

  final String name;
  final String description;
  final Color background;
  final Color card;
  final Color border;
  final Color text1;
  final Color text2;
  final Color accent1;
  final Color accent2;
  final Color success;
  final Color warning;
}

class EInkPalette {
  const EInkPalette._();

  // ---------------------------------------------------------------------------
  // 3 Exact E-Ink Color Palettes
  // ---------------------------------------------------------------------------
  // 1. Classic Kaleido:
  // BG #F2F0EB, Card #E6E3DC, Border #C8C4BA, Text1 #1C1C1A, Text2 #5E5D58,
  // Accent1 #B5543E, Accent2 #476880, Success #567560, Warning #C49635
  static const EInkPaletteConfig classicKaleido = EInkPaletteConfig(
    name: 'Classic Kaleido',
    description: 'Warm, natural paper tone inspired by color e-readers',
    background: Color(0xFFF2F0EB),
    card: Color(0xFFE6E3DC),
    border: Color(0xFFC8C4BA),
    text1: Color(0xFF1C1C1A),
    text2: Color(0xFF5E5D58),
    accent1: Color(0xFFB5543E),
    accent2: Color(0xFF476880),
    success: Color(0xFF567560),
    warning: Color(0xFFC49635),
  );

  // 2. Cool Newspaper:
  // BG #ECEEED, Card #DFE2E0, Border #BFC4C1, Text1 #141716, Text2 #525855,
  // Accent1 #2E5A88, Accent2 #A84438, Success #3D6E58, Warning #B8862D
  static const EInkPaletteConfig coolNewspaper = EInkPaletteConfig(
    name: 'Cool Newspaper',
    description: 'Crisp editorial aesthetic with cool grey newsprint tones',
    background: Color(0xFFECEEED),
    card: Color(0xFFDFE2E0),
    border: Color(0xFFBFC4C1),
    text1: Color(0xFF141716),
    text2: Color(0xFF525855),
    accent1: Color(0xFF2E5A88),
    accent2: Color(0xFFA84438),
    success: Color(0xFF3D6E58),
    warning: Color(0xFFB8862D),
  );

  // 3. Night E-Ink:
  // BG #1E1E1C, Card #292926, Border #3D3D38, Text1 #E6E3DC, Text2 #9E9B93,
  // Accent1 #D47A63, Accent2 #7A9EB8, Success #7BA187, Warning #D9B257
  static const EInkPaletteConfig nightEInk = EInkPaletteConfig(
    name: 'Night E-Ink',
    description: 'Inverted low-light dark e-paper for comfortable evening focus',
    background: Color(0xFF1E1E1C),
    card: Color(0xFF292926),
    border: Color(0xFF3D3D38),
    text1: Color(0xFFE6E3DC),
    text2: Color(0xFF9E9B93),
    accent1: Color(0xFFD47A63),
    accent2: Color(0xFF7A9EB8),
    success: Color(0xFF7BA187),
    warning: Color(0xFFD9B257),
  );

  static EInkPaletteConfig getConfig(EInkPresetPalette preset) {
    switch (preset) {
      case EInkPresetPalette.classicKaleido:
        return classicKaleido;
      case EInkPresetPalette.coolNewspaper:
        return coolNewspaper;
      case EInkPresetPalette.nightEInk:
        return nightEInk;
    }
  }

  // ---------------------------------------------------------------------------
  // 1. NEUTRAL PAPER & INK COLORS
  // ---------------------------------------------------------------------------
  static const Color paperWhite = Color(0xFFF9F7F2);
  static const Color ivory = Color(0xFFF4EFE6);
  static const Color warmWhite = Color(0xFFF6F3EC);
  static const Color cream = Color(0xFFECE5D8);
  static const Color antiqueWhite = Color(0xFFE8E0D2);
  static const Color lightGrey = Color(0xFFDCD7CD);
  static const Color silverGrey = Color(0xFFC7C1B6);
  static const Color slateGrey = Color(0xFF868E96);
  static const Color charcoal = Color(0xFF2C2F33);
  static const Color inkBlack = Color(0xFF1A1C1E);

  // ---------------------------------------------------------------------------
  // 2. RED COLORS
  // ---------------------------------------------------------------------------
  static const Color softRose = Color(0xFFD98880);
  static const Color dustyRose = Color(0xFFC47470);
  static const Color mutedRed = Color(0xFFB35954);
  static const Color terracotta = Color(0xFFB85D43);
  static const Color brickRed = Color(0xFF9E4738);
  static const Color softCoral = Color(0xFFD27D68);

  // ---------------------------------------------------------------------------
  // 3. ORANGE COLORS
  // ---------------------------------------------------------------------------
  static const Color paleOrange = Color(0xFFE8AA7B);
  static const Color softPeach = Color(0xFFE5B292);
  static const Color mutedOrange = Color(0xFFCF8552);
  static const Color apricot = Color(0xFFD69460);
  static const Color burntOrange = Color(0xFFB0673B);
  static const Color warmAmber = Color(0xFFBF7B38);

  // ---------------------------------------------------------------------------
  // 4. YELLOW COLORS
  // ---------------------------------------------------------------------------
  static const Color paleYellow = Color(0xFFE8D79B);
  static const Color butterYellow = Color(0xFFDFCC84);
  static const Color softGold = Color(0xFFCDB669);
  static const Color mutedMustard = Color(0xFFBFA554);
  static const Color sand = Color(0xFFCFBE8F);
  static const Color ochre = Color(0xFFA68D42);

  // ---------------------------------------------------------------------------
  // 5. GREEN COLORS
  // ---------------------------------------------------------------------------
  static const Color mint = Color(0xFF97C1A9);
  static const Color sageGreen = Color(0xFF8BA888);
  static const Color seafoam = Color(0xFF88B39E);
  static const Color paleGreen = Color(0xFFA5C49F);
  static const Color olive = Color(0xFF7E8F68);
  static const Color mossGreen = Color(0xFF6B7F5E);
  static const Color forestGreen = Color(0xFF4F684E);

  // ---------------------------------------------------------------------------
  // 6. CYAN & TEAL COLORS
  // ---------------------------------------------------------------------------
  static const Color paleCyan = Color(0xFF94C4C2);
  static const Color softAqua = Color(0xFF7EBAB8);
  static const Color dustyTeal = Color(0xFF629B99);
  static const Color mutedTurquoise = Color(0xFF558E8D);
  static const Color seaGreen = Color(0xFF5C8A84);
  static const Color deepTeal = Color(0xFF3E6966);

  // ---------------------------------------------------------------------------
  // 7. BLUE COLORS
  // ---------------------------------------------------------------------------
  static const Color powderBlue = Color(0xFF9FB6CD);
  static const Color skyBlue = Color(0xFF86A5C4);
  static const Color mutedBlue = Color(0xFF6E8EAF);
  static const Color dustyBlue = Color(0xFF5B7A9A);
  static const Color steelBlue = Color(0xFF516F8C);
  static const Color slateBlue = Color(0xFF485E75);
  static const Color deepBlue = Color(0xFF334A60);

  // ---------------------------------------------------------------------------
  // 8. PURPLE COLORS
  // ---------------------------------------------------------------------------
  static const Color lavender = Color(0xFFB8A9C9);
  static const Color lilac = Color(0xFFA796BA);
  static const Color dustyPurple = Color(0xFF8F7B9E);
  static const Color mutedViolet = Color(0xFF7B668B);
  static const Color softPlum = Color(0xFF6D527A);
  static const Color deepPurple = Color(0xFF523D5F);

  // ---------------------------------------------------------------------------
  // 9. PINK COLORS
  // ---------------------------------------------------------------------------
  static const Color palePink = Color(0xFFDEABB7);
  static const Color blushPink = Color(0xFFD497A4);
  static const Color dustyPink = Color(0xFFC0808F);
  static const Color mutedMagenta = Color(0xFFA86374);
  static const Color mauve = Color(0xFF9B6976);

  // ---------------------------------------------------------------------------
  // 10. BROWN & EARTH COLORS
  // ---------------------------------------------------------------------------
  static const Color sandstone = Color(0xFFC8B49B);
  static const Color beige = Color(0xFFBEA98F);
  static const Color taupe = Color(0xFFA6937C);
  static const Color caramel = Color(0xFFA07B57);
  static const Color chestnut = Color(0xFF845F3E);
  static const Color cocoa = Color(0xFF6B4E38);
  static const Color earthBrown = Color(0xFF533F31);

  // ---------------------------------------------------------------------------
  // ALL CURATED ITEMS WITH TINTS
  // ---------------------------------------------------------------------------
  static const List<EInkColorItem> allColors = [
    // Neutral
    EInkColorItem(
      name: 'Paper White',
      color: paperWhite,
      lightTint: Color(0xFFFCFBF9),
      darkTint: Color(0xFFEBE6DC),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Ivory',
      color: ivory,
      lightTint: Color(0xFFF9F6F0),
      darkTint: Color(0xFFE4DDD0),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Warm White',
      color: warmWhite,
      lightTint: Color(0xFFFAF8F3),
      darkTint: Color(0xFFE8E3D7),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Cream',
      color: cream,
      lightTint: Color(0xFFF3EFE7),
      darkTint: Color(0xFFDDD3C2),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Antique White',
      color: antiqueWhite,
      lightTint: Color(0xFFEFE9DC),
      darkTint: Color(0xFFD5CCBC),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Light Grey',
      color: lightGrey,
      lightTint: Color(0xFFE7E3DA),
      darkTint: Color(0xFFC8C2B6),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Silver Grey',
      color: silverGrey,
      lightTint: Color(0xFFD6D1C7),
      darkTint: Color(0xFFB0AAA0),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Slate Grey',
      color: slateGrey,
      lightTint: Color(0xFFA6ACB3),
      darkTint: Color(0xFF687077),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Charcoal',
      color: charcoal,
      lightTint: Color(0xFF4E5257),
      darkTint: Color(0xFF1E2023),
      category: 'Neutral',
    ),
    EInkColorItem(
      name: 'Ink Black',
      color: inkBlack,
      lightTint: Color(0xFF383B3F),
      darkTint: Color(0xFF0F1012),
      category: 'Neutral',
    ),

    // Red
    EInkColorItem(
      name: 'Soft Rose',
      color: softRose,
      lightTint: Color(0xFFE5A7A0),
      darkTint: Color(0xFFC06B62),
      category: 'Red',
    ),
    EInkColorItem(
      name: 'Dusty Rose',
      color: dustyRose,
      lightTint: Color(0xFFD39390),
      darkTint: Color(0xFFA85955),
      category: 'Red',
    ),
    EInkColorItem(
      name: 'Muted Red',
      color: mutedRed,
      lightTint: Color(0xFFC67A76),
      darkTint: Color(0xFF92423E),
      category: 'Red',
    ),
    EInkColorItem(
      name: 'Terracotta',
      color: terracotta,
      lightTint: Color(0xFFCC7F69),
      darkTint: Color(0xFF964630),
      category: 'Red',
    ),
    EInkColorItem(
      name: 'Brick Red',
      color: brickRed,
      lightTint: Color(0xFFB86657),
      darkTint: Color(0xFF7C3326),
      category: 'Red',
    ),
    EInkColorItem(
      name: 'Soft Coral',
      color: softCoral,
      lightTint: Color(0xFFDE9987),
      darkTint: Color(0xFFB5604C),
      category: 'Red',
    ),

    // Orange
    EInkColorItem(
      name: 'Pale Orange',
      color: paleOrange,
      lightTint: Color(0xFFEFBF99),
      darkTint: Color(0xFFCC8D5E),
      category: 'Orange',
    ),
    EInkColorItem(
      name: 'Soft Peach',
      color: softPeach,
      lightTint: Color(0xFFEFC6AD),
      darkTint: Color(0xFFC79574),
      category: 'Orange',
    ),
    EInkColorItem(
      name: 'Muted Orange',
      color: mutedOrange,
      lightTint: Color(0xFFDCA177),
      darkTint: Color(0xFFAC6837),
      category: 'Orange',
    ),
    EInkColorItem(
      name: 'Apricot',
      color: apricot,
      lightTint: Color(0xFFE2AD84),
      darkTint: Color(0xFFB37443),
      category: 'Orange',
    ),
    EInkColorItem(
      name: 'Burnt Orange',
      color: burntOrange,
      lightTint: Color(0xFFC58257),
      darkTint: Color(0xFF8F4D24),
      category: 'Orange',
    ),
    EInkColorItem(
      name: 'Warm Amber',
      color: warmAmber,
      lightTint: Color(0xFFD19556),
      darkTint: Color(0xFF9C6024),
      category: 'Orange',
    ),

    // Yellow
    EInkColorItem(
      name: 'Pale Yellow',
      color: paleYellow,
      lightTint: Color(0xFFEFE2B3),
      darkTint: Color(0xFFC9B77C),
      category: 'Yellow',
    ),
    EInkColorItem(
      name: 'Butter Yellow',
      color: butterYellow,
      lightTint: Color(0xFFE9DAA1),
      darkTint: Color(0xFFBEAB65),
      category: 'Yellow',
    ),
    EInkColorItem(
      name: 'Soft Gold',
      color: softGold,
      lightTint: Color(0xFFDAC88A),
      darkTint: Color(0xFFAA944C),
      category: 'Yellow',
    ),
    EInkColorItem(
      name: 'Muted Mustard',
      color: mutedMustard,
      lightTint: Color(0xFFD0BA75),
      darkTint: Color(0xFF9E8437),
      category: 'Yellow',
    ),
    EInkColorItem(
      name: 'Sand',
      color: sand,
      lightTint: Color(0xFFDCCEA6),
      darkTint: Color(0xFFAF9E71),
      category: 'Yellow',
    ),
    EInkColorItem(
      name: 'Ochre',
      color: ochre,
      lightTint: Color(0xFFBBA45F),
      darkTint: Color(0xFF846D2B),
      category: 'Yellow',
    ),

    // Green
    EInkColorItem(
      name: 'Mint',
      color: mint,
      lightTint: Color(0xFFB2D3C0),
      darkTint: Color(0xFF76A289),
      category: 'Green',
    ),
    EInkColorItem(
      name: 'Sage Green',
      color: sageGreen,
      lightTint: Color(0xFFA5BFA2),
      darkTint: Color(0xFF6B8A68),
      category: 'Green',
    ),
    EInkColorItem(
      name: 'Seafoam',
      color: seafoam,
      lightTint: Color(0xFFA4C7B5),
      darkTint: Color(0xFF68947F),
      category: 'Green',
    ),
    EInkColorItem(
      name: 'Pale Green',
      color: paleGreen,
      lightTint: Color(0xFFBCD5B7),
      darkTint: Color(0xFF84A67D),
      category: 'Green',
    ),
    EInkColorItem(
      name: 'Olive',
      color: olive,
      lightTint: Color(0xFF9AA986),
      darkTint: Color(0xFF5F6F4B),
      category: 'Green',
    ),
    EInkColorItem(
      name: 'Moss Green',
      color: mossGreen,
      lightTint: Color(0xFF889A7B),
      darkTint: Color(0xFF4F6043),
      category: 'Green',
    ),
    EInkColorItem(
      name: 'Forest Green',
      color: forestGreen,
      lightTint: Color(0xFF6E866D),
      darkTint: Color(0xFF354B35),
      category: 'Green',
    ),

    // Cyan & Teal
    EInkColorItem(
      name: 'Pale Cyan',
      color: paleCyan,
      lightTint: Color(0xFFAED3D1),
      darkTint: Color(0xFF73A5A3),
      category: 'Cyan & Teal',
    ),
    EInkColorItem(
      name: 'Soft Aqua',
      color: softAqua,
      lightTint: Color(0xFF9ECBCA),
      darkTint: Color(0xFF5D9B99),
      category: 'Cyan & Teal',
    ),
    EInkColorItem(
      name: 'Dusty Teal',
      color: dustyTeal,
      lightTint: Color(0xFF84B2B0),
      darkTint: Color(0xFF457D7B),
      category: 'Cyan & Teal',
    ),
    EInkColorItem(
      name: 'Muted Turquoise',
      color: mutedTurquoise,
      lightTint: Color(0xFF78A7A6),
      darkTint: Color(0xFF3B7170),
      category: 'Cyan & Teal',
    ),
    EInkColorItem(
      name: 'Sea Green',
      color: seaGreen,
      lightTint: Color(0xFF7DA29D),
      darkTint: Color(0xFF416D68),
      category: 'Cyan & Teal',
    ),
    EInkColorItem(
      name: 'Deep Teal',
      color: deepTeal,
      lightTint: Color(0xFF5E8582),
      darkTint: Color(0xFF264C4A),
      category: 'Cyan & Teal',
    ),

    // Blue
    EInkColorItem(
      name: 'Powder Blue',
      color: powderBlue,
      lightTint: Color(0xFFB7C8DB),
      darkTint: Color(0xFF7F98B2),
      category: 'Blue',
    ),
    EInkColorItem(
      name: 'Sky Blue',
      color: skyBlue,
      lightTint: Color(0xFFA3BBD5),
      darkTint: Color(0xFF6486A8),
      category: 'Blue',
    ),
    EInkColorItem(
      name: 'Muted Blue',
      color: mutedBlue,
      lightTint: Color(0xFF8FA8C3),
      darkTint: Color(0xFF4E7092),
      category: 'Blue',
    ),
    EInkColorItem(
      name: 'Dusty Blue',
      color: dustyBlue,
      lightTint: Color(0xFF7B95B1),
      darkTint: Color(0xFF405D7C),
      category: 'Blue',
    ),
    EInkColorItem(
      name: 'Steel Blue',
      color: steelBlue,
      lightTint: Color(0xFF728DA7),
      darkTint: Color(0xFF37526E),
      category: 'Blue',
    ),
    EInkColorItem(
      name: 'Slate Blue',
      color: slateBlue,
      lightTint: Color(0xFF677E95),
      darkTint: Color(0xFF2F4357),
      category: 'Blue',
    ),
    EInkColorItem(
      name: 'Deep Blue',
      color: deepBlue,
      lightTint: Color(0xFF516980),
      darkTint: Color(0xFF1B2F43),
      category: 'Blue',
    ),

    // Purple
    EInkColorItem(
      name: 'Lavender',
      color: lavender,
      lightTint: Color(0xFFCCC0DA),
      darkTint: Color(0xFF9B8BAF),
      category: 'Purple',
    ),
    EInkColorItem(
      name: 'Lilac',
      color: lilac,
      lightTint: Color(0xFFBEB0CE),
      darkTint: Color(0xFF87749C),
      category: 'Purple',
    ),
    EInkColorItem(
      name: 'Dusty Purple',
      color: dustyPurple,
      lightTint: Color(0xFFA896B6),
      darkTint: Color(0xFF705B80),
      category: 'Purple',
    ),
    EInkColorItem(
      name: 'Muted Violet',
      color: mutedViolet,
      lightTint: Color(0xFF9783A5),
      darkTint: Color(0xFF5C476E),
      category: 'Purple',
    ),
    EInkColorItem(
      name: 'Soft Plum',
      color: softPlum,
      lightTint: Color(0xFF8B7098),
      darkTint: Color(0xFF4E345C),
      category: 'Purple',
    ),
    EInkColorItem(
      name: 'Deep Purple',
      color: deepPurple,
      lightTint: Color(0xFF6E567D),
      darkTint: Color(0xFF372444),
      category: 'Purple',
    ),

    // Pink
    EInkColorItem(
      name: 'Pale Pink',
      color: palePink,
      lightTint: Color(0xFFE8C2CB),
      darkTint: Color(0xFFC68B97),
      category: 'Pink',
    ),
    EInkColorItem(
      name: 'Blush Pink',
      color: blushPink,
      lightTint: Color(0xFFDFB0BA),
      darkTint: Color(0xFFB57583),
      category: 'Pink',
    ),
    EInkColorItem(
      name: 'Dusty Pink',
      color: dustyPink,
      lightTint: Color(0xFFCF9AA7),
      darkTint: Color(0xFF9E5C6B),
      category: 'Pink',
    ),
    EInkColorItem(
      name: 'Muted Magenta',
      color: mutedMagenta,
      lightTint: Color(0xFFBC808F),
      darkTint: Color(0xFF854353),
      category: 'Pink',
    ),
    EInkColorItem(
      name: 'Mauve',
      color: mauve,
      lightTint: Color(0xFFB08591),
      darkTint: Color(0xFF794956),
      category: 'Pink',
    ),

    // Brown & Earth
    EInkColorItem(
      name: 'Sandstone',
      color: sandstone,
      lightTint: Color(0xFFD7C7B3),
      darkTint: Color(0xFFA99379),
      category: 'Brown & Earth',
    ),
    EInkColorItem(
      name: 'Beige',
      color: beige,
      lightTint: Color(0xFFCEBEA8),
      darkTint: Color(0xFF9E886D),
      category: 'Brown & Earth',
    ),
    EInkColorItem(
      name: 'Taupe',
      color: taupe,
      lightTint: Color(0xFFB9A993),
      darkTint: Color(0xFF86725B),
      category: 'Brown & Earth',
    ),
    EInkColorItem(
      name: 'Caramel',
      color: caramel,
      lightTint: Color(0xFFB69472),
      darkTint: Color(0xFF805C38),
      category: 'Brown & Earth',
    ),
    EInkColorItem(
      name: 'Chestnut',
      color: chestnut,
      lightTint: Color(0xFF9E7B5B),
      darkTint: Color(0xFF644122),
      category: 'Brown & Earth',
    ),
    EInkColorItem(
      name: 'Cocoa',
      color: cocoa,
      lightTint: Color(0xFF856851),
      darkTint: Color(0xFF4E331F),
      category: 'Brown & Earth',
    ),
    EInkColorItem(
      name: 'Earth Brown',
      color: earthBrown,
      lightTint: Color(0xFF705948),
      darkTint: Color(0xFF38271B),
      category: 'Brown & Earth',
    ),
  ];

  static const List<String> categories = [
    'Neutral',
    'Red',
    'Orange',
    'Yellow',
    'Green',
    'Cyan & Teal',
    'Blue',
    'Purple',
    'Pink',
    'Brown & Earth',
  ];
}

/// Curated E-Ink Presets
class EInkPreset {
  const EInkPreset({
    required this.name,
    required this.description,
    required this.accentColor,
    required this.paperColor,
  });

  final String name;
  final String description;
  final Color accentColor;
  final Color paperColor;
}

class EInkPresets {
  const EInkPresets._();

  static const EInkPreset classicEInk = EInkPreset(
    name: 'Classic E-Ink',
    description: 'Minimalist monochromatic newspaper paper & dark charcoal',
    accentColor: EInkPalette.charcoal,
    paperColor: EInkPalette.paperWhite,
  );

  static const EInkPreset warmPaper = EInkPreset(
    name: 'Warm Paper',
    description: 'Gentle bookish cream background with warm amber notes',
    accentColor: EInkPalette.warmAmber,
    paperColor: EInkPalette.ivory,
  );

  static const EInkPreset softPastel = EInkPreset(
    name: 'Soft Pastel',
    description: 'Soothing sage and dusty rose e-paper hues',
    accentColor: EInkPalette.sageGreen,
    paperColor: EInkPalette.warmWhite,
  );

  static const EInkPreset naturalEarth = EInkPreset(
    name: 'Natural Earth',
    description: 'Warm sandstone, ochre and organic earthy tones',
    accentColor: EInkPalette.caramel,
    paperColor: EInkPalette.cream,
  );

  static const EInkPreset coolEInk = EInkPreset(
    name: 'Cool E-Ink',
    description: 'Calm dusty blue and crisp silver slate paper',
    accentColor: EInkPalette.steelBlue,
    paperColor: EInkPalette.lightGrey,
  );

  static const EInkPreset fullColorEInk = EInkPreset(
    name: 'Full Color E-Ink',
    description: 'Vibrant modern Kaleido palette with soft terracotta & teal',
    accentColor: EInkPalette.terracotta,
    paperColor: EInkPalette.antiqueWhite,
  );

  static const List<EInkPreset> all = [
    classicEInk,
    warmPaper,
    softPastel,
    naturalEarth,
    coolEInk,
    fullColorEInk,
  ];
}
