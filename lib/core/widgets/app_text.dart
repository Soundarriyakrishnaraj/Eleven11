import 'package:material_ui/material_ui.dart';
import '../providers/theme_provider.dart';

/// Extension on String to conditionally transform text to uppercase when custom TTF mode is active.
/// Does NOT alter raw strings or database records.
extension EinkUppercaseString on String {
  String toEInkDisplay([bool? forceUppercase]) {
    final shouldUpper = forceUppercase ?? ThemeNotifier.instance.isUppercaseMode;
    return shouldUpper ? toUpperCase() : this;
  }
}

/// A text widget that renders user-facing text in UPPERCASE when Custom TTF mode is enabled.
/// Keeps underlying source string completely untouched.
class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.forceUppercase,
  });

  final String text;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  final bool? forceUppercase;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeNotifier.instance,
      builder: (context, _) {
        final displayText = text.toEInkDisplay(forceUppercase);
        return Text(
          displayText,
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      },
    );
  }
}
