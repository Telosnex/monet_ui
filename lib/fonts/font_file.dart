import 'dart:typed_data';

/// Facts read from the bytes of a TrueType or OpenType font file.
///
/// The one reader of font files in monet_ui and the apps that use it
/// (docs/design/ADR_fonts_in_monet_ui.md in telosnex, D2). Reads only; the
/// font transform is in font_line_metrics_patch.dart.

/// A table record: its position in the table directory, and the offset and
/// length of the table.
typedef FontTableRecord = ({int record, int offset, int length});

/// The tables of [bytes] by tag, or null if [bytes] is not a TrueType or
/// OpenType file, or its table directory is cut off.
Map<String, FontTableRecord>? fontTableRecords(ByteData bytes) {
  if (bytes.lengthInBytes < 12) return null;
  final version = bytes.getUint32(0);
  // 1.0 (TrueType), 'OTTO' (CFF), 'true' (Apple TrueType).
  if (version != 0x00010000 && version != 0x4F54544F && version != 0x74727565) {
    return null;
  }
  final records = <String, FontTableRecord>{};
  final numTables = bytes.getUint16(4);
  for (var i = 0; i < numTables; i++) {
    final record = 12 + 16 * i;
    if (record + 16 > bytes.lengthInBytes) return null;
    final tag = String.fromCharCodes([
      for (var b = 0; b < 4; b++) bytes.getUint8(record + b),
    ]);
    records[tag] = (
      record: record,
      offset: bytes.getUint32(record + 8),
      length: bytes.getUint32(record + 12),
    );
  }
  return records;
}

/// The tables whose glyphs have their own colours.
const kColorFontTables = {'COLR', 'CPAL', 'SVG ', 'CBDT', 'CBLC', 'sbix'};

/// The colour tables of [bytes], sorted. Empty for a font without them, or a
/// file that is not a font.
List<String> colorTables(ByteData bytes) =>
    (fontTableRecords(bytes)?.keys.where(kColorFontTables.contains).toList() ??
          <String>[])
      ..sort();

/// The outline format of a font file.
enum FontOutlines { trueType, cff, cff2, none }

/// The outline format of [bytes]: glyf, CFF, or CFF2.
FontOutlines fontOutlines(ByteData bytes) {
  final records = fontTableRecords(bytes);
  if (records == null) return FontOutlines.none;
  if (records.containsKey('glyf')) return FontOutlines.trueType;
  if (records.containsKey('CFF2')) return FontOutlines.cff2;
  if (records.containsKey('CFF ')) return FontOutlines.cff;
  return FontOutlines.none;
}

/// head.unitsPerEm of [bytes], or null if it has no head table.
int? unitsPerEm(ByteData bytes) {
  final head = fontTableRecords(bytes)?['head'];
  if (head == null || head.length < 54) return null;
  return bytes.getUint16(head.offset + 18);
}

/// Code points that the Unicode cmap subtables map to a glyph other than 0
/// (.notdef).
///
/// Reads formats 4 and 12, on platform 0, and platform 3 encodings 1 and 10.
/// A font with only other formats gives an empty set.
Set<int> cmapCodePoints(ByteData bytes) {
  final cmap = fontTableRecords(bytes)?['cmap'];
  if (cmap == null) return {};
  final d = bytes;
  final base = cmap.offset;
  final out = <int>{};
  final n = d.getUint16(base + 2);
  for (var i = 0; i < n; i++) {
    final platform = d.getUint16(base + 4 + 8 * i);
    final encoding = d.getUint16(base + 6 + 8 * i);
    final unicode =
        platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
    if (!unicode) continue;
    final t = base + d.getUint32(base + 8 + 8 * i);
    final format = d.getUint16(t);
    if (format == 4) {
      final segX2 = d.getUint16(t + 6);
      final ends = t + 14, starts = ends + segX2 + 2;
      final deltas = starts + segX2, offsets = deltas + segX2;
      for (var s = 0; s < segX2 ~/ 2; s++) {
        final end = d.getUint16(ends + 2 * s);
        final start = d.getUint16(starts + 2 * s);
        final delta = d.getInt16(deltas + 2 * s);
        final ro = d.getUint16(offsets + 2 * s);
        for (var c = start; c <= end && c != 0xffff; c++) {
          int g;
          if (ro == 0) {
            g = (c + delta) & 0xffff;
          } else {
            g = d.getUint16(offsets + 2 * s + ro + 2 * (c - start));
            if (g != 0) g = (g + delta) & 0xffff;
          }
          if (g != 0) out.add(c);
        }
      }
    } else if (format == 12) {
      final groups = d.getUint32(t + 12);
      for (var k = 0; k < groups; k++) {
        final g = t + 16 + 12 * k;
        final start = d.getUint32(g), end = d.getUint32(g + 4);
        final first = d.getUint32(g + 8);
        for (var c = start; c <= end; c++) {
          if (first + (c - start) != 0) out.add(c);
        }
      }
    }
  }
  return out;
}

/// A-Z and a-z.
final kLatinLetterCodePoints = [
  for (var c = 0x41; c <= 0x5A; c++) c,
  for (var c = 0x61; c <= 0x7A; c++) c,
];

/// Whether [codePoints] has A-Z and a-z: the font draws English letters.
///
/// The catalog's `latin` subset does not decide this: many families without
/// it draw English (the Playwrite families, the math fonts). The generator's
/// Python rasterizer uses the same rule.
bool hasLatinLetters(Set<int> codePoints) =>
    kLatinLetterCodePoints.every(codePoints.contains);
