/// Detects characters likely to be rendered as colour emoji by the platform.
///
/// Covers every code point with the Unicode `Emoji` property except ASCII
/// digits, `#` and `*`, which only become emoji with a keycap (also covered).
/// That includes text-default symbols such as ↔ and ©, which platform font
/// fallback can draw in colour. ZWJ sequences, skin-tone modifiers and
/// regional indicators are covered by their base code points.
///
/// ## Why not a `RegExp`?
///
/// This predicate sits on the hot path: it is consulted by `_canTintWith`
/// every time a colour-only style change is observed (i.e. once per frame
/// during a hover/colour animation). The previous implementation compiled a
/// nine-alternation Unicode `RegExp` and ran `hasMatch`, which forces the
/// regex engine to walk the full string code-point-by-code-point with a fair
/// amount of per-char overhead.
///
/// The replacement is a hand-rolled UTF-16 scan with two cheap escape hatches:
///
///  1. **ASCII fast-out per code unit.** Any code unit below `0xA9` (ASCII
///     and most Latin-1) is skipped with a single integer compare. Other
///     text below U+2000 or above U+3299 (Latin, Cyrillic, CJK, …) costs one
///     or two more compares. Pure-ASCII strings — the common case for UI
///     chrome — never touch the range checks.
///  2. **Surrogate-aware astral decode.** Only when a high surrogate is seen
///     do we decode the astral code point and test the supplemental ranges.
///
/// On top of that, results are memoised in a small bounded map keyed by the
/// text, because the same string is re-checked frame after frame during an
/// animation. A cache hit is a single hash lookup with no LRU bookkeeping; a
/// miss is the linear scan below. Together these make the steady-state cost
/// effectively nothing.
///
const int _kColorEmojiCacheCapacity = 512;
final Map<String, bool> _colorEmojiCache = <String, bool>{};

bool textHasColorEmoji(String text) {
  if (text.isEmpty) return false;
  final cached = _colorEmojiCache[text];
  if (cached != null) return cached;
  final result = scanForColorEmoji(text);
  if (_colorEmojiCache.length == _kColorEmojiCacheCapacity) {
    _colorEmojiCache.remove(_colorEmojiCache.keys.first);
  }
  _colorEmojiCache[text] = result;
  return result;
}

/// Linear UTF-16 scan for code points that can render as colour emoji. See
/// [textHasColorEmoji] for the rationale.
bool scanForColorEmoji(String text) {
  final len = text.length;
  int i = 0;
  while (i < len) {
    final c = text.codeUnitAt(i);
    if (c < 0xA9) {
      // Below every emoji code point: ASCII and most Latin-1. The hot path.
      i++;
      continue;
    }
    if (c >= 0xD800 && c <= 0xDBFF) {
      // High surrogate: decode the astral code point and test supplemental
      // emoji blocks.
      if (i + 1 < len) {
        final lo = text.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          final cp = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
          if (_isAstralColorEmoji(cp)) return true;
          i += 2;
          continue;
        }
      }
    } else if (_isBmpColorEmoji(c)) {
      return true;
    }
    i++;
  }
  return false;
}

/// BMP code points with the Unicode `Emoji` property, plus the keycap and
/// emoji presentation selector. Many default to text presentation (↔, ©,
/// ™), but platform fallback can still draw them from a colour font: macOS
/// draws ↔ from Apple Color Emoji. A false positive only costs the cached
/// tint path; a miss paints a solid block on hover.
bool _isBmpColorEmoji(int c) {
  if (c < 0x2000) return c == 0xA9 || c == 0xAE;
  if (c >= 0x2600 && c <= 0x27BF) return true; // Misc Symbols + Dingbats
  if (c > 0x3299) return c == 0xFE0F;
  for (var r = 0; r < _kBmpEmojiRanges.length; r += 2) {
    if (c < _kBmpEmojiRanges[r]) return false;
    if (c <= _kBmpEmojiRanges[r + 1]) return true;
  }
  return false;
}

/// Sorted inclusive pairs between U+2000 and U+3299, outside 2600-27BF.
const _kBmpEmojiRanges = [
  0x203C, 0x203C, // ‼
  0x2049, 0x2049, // ⁉
  0x20E3, 0x20E3, // combining keycap
  0x2122, 0x2122, // ™
  0x2139, 0x2139, // ℹ
  0x2194, 0x2199, // ↔ ↕ ↖ ↗ ↘ ↙
  0x21A9, 0x21AA, // ↩ ↪
  0x231A, 0x231B, // ⌚ ⌛
  0x2328, 0x2328, // ⌨
  0x23CF, 0x23CF, // ⏏
  0x23E9, 0x23F3, // ⏩ … ⏳
  0x23F8, 0x23FA, // ⏸ ⏹ ⏺
  0x24C2, 0x24C2, // Ⓜ
  0x25AA, 0x25AB, // ▪ ▫
  0x25B6, 0x25B6, // ▶
  0x25C0, 0x25C0, // ◀
  0x25FB, 0x25FE, // ◻ ◼ ◽ ◾
  0x2934, 0x2935, // ⤴ ⤵
  0x2B05, 0x2B07, // ⬅ ⬆ ⬇
  0x2B1B, 0x2B1C, // ⬛ ⬜
  0x2B50, 0x2B50, // ⭐
  0x2B55, 0x2B55, // ⭕
  0x3030, 0x3030, // 〰
  0x303D, 0x303D, // 〽
  0x3297, 0x3297, // ㊗
  0x3299, 0x3299, // ㊙
];

bool _isAstralColorEmoji(int cp) {
  return cp == 0x1F004 || // 🀄
      cp == 0x1F0CF || // 🃏
      (cp >= 0x1F170 && cp <= 0x1F251) || // 🅰, flags, 🆎, 🈁, 🉐
      (cp >= 0x1F300 && cp <= 0x1F5FF) || // Misc Symbols & Pictographs
      (cp >= 0x1F600 && cp <= 0x1F64F) || // Emoticons
      (cp >= 0x1F680 && cp <= 0x1F6FF) || // Transport & Map
      (cp >= 0x1F7E0 && cp <= 0x1F7F0) || // 🟠 … 🟰
      (cp >= 0x1F900 && cp <= 0x1F9FF) || // Supplemental Symbols
      (cp >= 0x1FA00 && cp <= 0x1FAFF); // Symbols Extended-A/B
}
