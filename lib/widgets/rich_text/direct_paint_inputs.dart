import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:monet_ui/widgets/rich_text/emoji_paint_spans.dart';
import 'package:monet_ui/widgets/rich_text/paragrapher.dart';

/// Native ParagraphBuilder encodes TextStyle.color and Shadow.color as ARGB32
/// (dart:ui text.dart/_encodeTextStyle and painting.dart/_encodeShadows).
/// Sub-byte palette changes therefore do not change that paragraph's pixels.
///
/// Do NOT round the caller's colors: custom foreground/background Paint and
/// our separate spread stroke Paint use float colors. The latter is repainted
/// independently with the current, unrounded shadows even when this returns
/// true. Web and styled spans conservatively keep the existing rebuild path.
bool sameNativeDirectParagraphPaint(ParagraphInput a, ParagraphInput b) {
  if (kIsWeb || a.paintColor.toARGB32() != b.paintColor.toARGB32()) {
    return false;
  }
  if (!nativeParagraphShadowsEqual(a.style.shadows, b.style.shadows)) {
    return false;
  }
  return sameDirectSpreadBase(a, b);
}

/// Spread strokes install their own foreground Paint and clear built-in
/// shadows. Their source paragraph does not depend on the label's fill color
/// or on non-spread shadows. Every other input must still agree exactly.
/// The strategy separately keys actual stroke colors/shapes and font changes.
bool sameDirectSpreadBase(ParagraphInput a, ParagraphInput b) {
  if (a.style.foreground != null ||
      b.style.foreground != null ||
      a.style.background != null ||
      b.style.background != null ||
      !isUnstyledTextSpan(a.textSpan) ||
      !isUnstyledTextSpan(b.textSpan)) {
    return false;
  }
  return a.textSpan == b.textSpan &&
      a.text == b.text &&
      a.direction == b.direction &&
      a.maxLines == b.maxLines &&
      a.align == b.align &&
      a.textScaler == b.textScaler &&
      a.strutStyle == b.strutStyle &&
      listEquals(a.placeholderSizes, b.placeholderSizes) &&
      listEquals(
        a.inlinePlaceholderDimensions,
        b.inlinePlaceholderDimensions,
      ) &&
      a.maxWidth == b.maxWidth &&
      a.softWrap == b.softWrap &&
      (a.style == b.style ||
          _withoutFillAndShadows(a.style) == _withoutFillAndShadows(b.style));
}

TextStyle _withoutFillAndShadows(TextStyle style) =>
    style.copyWith(color: const Color(0xff000000), shadows: const []);

/// Built-in native shadows only; our float-colored spread strokes are separate.
bool nativeParagraphShadowsEqual(List<Shadow>? a, List<Shadow>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].color.toARGB32() != b[i].color.toARGB32() ||
        a[i].offset != b[i].offset ||
        a[i].blurRadius != b[i].blurRadius) {
      return false;
    }
    // BoxShadow.spreadRadius/blurStyle are not encoded in a native paragraph.
    // The direct strategy's independent stroke picture handles spread changes.
  }
  return true;
}
