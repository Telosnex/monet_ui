import 'package:flutter/widgets.dart';

import 'package:monet_ui/widgets/rich_text/emoji_detection.dart';

/// Paint-only, complementary versions of the SAME paragraph. Neither removes
/// text or introduces placeholders, so shaping, BiDi and line breaks retain
/// the original inputs. Split at graphemes, not UTF-16 code units: ZWJ, flags,
/// variation selectors and modifiers must stay together.
class EmojiPaintSpans {
  EmojiPaintSpans(String text) {
    final textRuns = <InlineSpan>[];
    final emojiRuns = <InlineSpan>[];
    final buffer = StringBuffer();
    bool? previousEmoji;
    var supported = true;
    void flush() {
      if (buffer.isEmpty) return;
      final run = buffer.toString();
      buffer.clear();
      textRuns.add(
        TextSpan(text: run, style: previousEmoji! ? _kHidden : null),
      );
      emojiRuns.add(
        TextSpan(text: run, style: previousEmoji ? null : _kHidden),
      );
    }

    for (final cluster in text.characters) {
      final emoji = _isEmojiPresentation(cluster);
      // Presentation selectors do not force Flutter to choose a colour font.
      // E.g. Arial can supply a monochrome © even for ©️. Do not freeze that
      // glyph white in the native pass. Keep the entire ambiguous paragraph
      // direct instead of trying to infer font fallback from Unicode alone.
      if (cluster.contains('\uFE0E') ||
          (emoji && !_emojiPresentation.hasMatch(cluster)) ||
          (!emoji && textHasColorEmoji(cluster))) {
        supported = false;
      }
      if (previousEmoji != emoji) flush();
      previousEmoji = emoji;
      buffer.write(cluster);
    }
    flush();
    this.supported = supported;
    ordinary = TextSpan(children: textRuns);
    emoji = TextSpan(children: emojiRuns);
  }

  late final bool supported;
  late final TextSpan ordinary;
  late final TextSpan emoji;
}

const _kHidden = TextStyle(color: Color(0x00000000));
// The Dart VM/browser regexp engine supports Unicode properties; the analyzer's
// regexp validator currently does not (covered by the grapheme tests).
// ignore: valid_regexps
final _emojiPresentation = RegExp(r'\p{Emoji_Presentation}', unicode: true);

bool _isEmojiPresentation(String cluster) {
  if (cluster.contains('\uFE0E')) return false; // explicit text presentation
  return cluster.contains('\uFE0F') || // explicit emoji presentation
      cluster.contains('\u20E3') || // keycap, with or without VS16
      _emojiPresentation.hasMatch(cluster);
}

/// This prototype does not flatten styled/interactive rich text. The original
/// span remains authoritative for selection/semantics; only private painters
/// receive the split spans.
bool isUnstyledTextSpan(InlineSpan span) =>
    span is TextSpan &&
    span.style == null &&
    (span.children?.every(isUnstyledTextSpan) ?? true);

// Bounded by both entry count and the renderer's 2,000-character eligibility
// limit. Do not rescan graphemes on every palette notification.
final _spansCache = <String, EmojiPaintSpans>{};
EmojiPaintSpans emojiPaintSpansFor(String text) {
  final cached = _spansCache[text];
  if (cached != null) return cached;
  final spans = EmojiPaintSpans(text);
  if (_spansCache.length >= 128) _spansCache.remove(_spansCache.keys.first);
  _spansCache[text] = spans;
  return spans;
}
