import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:monet_ui/widgets/snapped_icons/icon_outline_analysis.dart';

export 'package:monet_ui/widgets/snapped_icons/icon_outline_analysis.dart'
    show IconOutline, IconOutlineAnalysis, OutlineVerb, kIconOutlineEm;

/// Outline of [icon] when an outline for its font family and code point
/// was registered with [registerIconOutlines].
IconOutline? iconOutline(IconData icon) {
  final family = icon.fontFamily;
  if (family == null ||
      icon.fontPackage != null ||
      (icon.fontFamilyFallback?.isNotEmpty ?? false)) {
    return null;
  }
  return _families[family]?.lookup(icon.codePoint);
}

/// Adds the outlines in [base64Data], in the format that
/// [kIconOutlineDataVersion] names. Icons of these families then draw as
/// paths: on the Material grid when the family is fitted, unfitted when not
/// (ADR 002, D9 and NG3).
///
/// A family in [base64Data] replaces an earlier registration of the same
/// family. Register before the first frame that draws an icon; outlines do
/// not change icons that were already laid out.
///
/// The package registers no outlines itself. Without a registration, icons
/// draw with their font.
void registerIconOutlines(String base64Data) {
  final data = _IconOutlineData(base64.decode(base64Data));
  for (final family in data.families) {
    _families[family.name] = family;
  }
}

/// Registered families by name.
final _families = <String, _Family>{};

/// Code points with an outline, by font family.
@visibleForTesting
Map<String, Iterable<int>> get debugIconOutlineCodePoints => {
  for (final MapEntry(:key, :value) in _families.entries)
    key: value.ranges.keys,
};

/// The stored outline of [codePoint] in [family], or null.
@visibleForTesting
IconOutline? debugIconOutline(String family, int codePoint) =>
    _families[family]?.lookup(codePoint);

/// Format version of the outline data that this code reads.
const kIconOutlineDataVersion = 2;

/// Decodes the format that [registerIconOutlines] reads. The Telosnex app's
/// `dev/maintenance_occasional/snapped_icons/outlines/generate.dart` writes
/// it.
///
/// Byte 0 is the version. Then a varint count of families. Per family: a
/// varint byte length and the UTF-8 family name, a varint units per em, one
/// byte that is 1 when the family is fitted to the grid, a varint glyph
/// count, per glyph a varint code point delta and a varint record length,
/// then the records in the same order.
///
/// A record is a varint verb count, one byte per verb, and every
/// coordinate as a zigzag varint delta from the previous one on the same
/// axis. A fitted family's record continues with one flag byte: bit 0 is
/// set when the record stores an analysis mirrored left to right. Then the
/// left-to-right analysis and, when flagged, the mirrored one (see
/// [writeIconOutlineAnalysis]).
final class _IconOutlineData {
  _IconOutlineData(Uint8List bytes) {
    final reader = OutlineDataReader(bytes);
    final version = bytes[reader.offset++];
    if (version != kIconOutlineDataVersion) {
      throw StateError('Unknown icon outline format $version');
    }
    for (var f = reader.varint(); f > 0; f--) {
      final nameLength = reader.varint();
      final name = utf8.decode(
        Uint8List.sublistView(bytes, reader.offset, reader.offset + nameLength),
      );
      reader.offset += nameLength;
      final em = reader.varint();
      final fits = bytes[reader.offset++] == 1;
      final count = reader.varint();
      final lengths = <int>[];
      final order = <int>[];
      var codePoint = 0;
      for (var i = 0; i < count; i++) {
        codePoint += reader.varint();
        order.add(codePoint);
        lengths.add(reader.varint());
      }
      final ranges = <int, int>{};
      var offset = reader.offset;
      for (var i = 0; i < order.length; i++) {
        ranges[order[i]] = offset;
        offset += lengths[i];
      }
      reader.offset = offset;
      families.add(_Family(name, bytes, em, fits, ranges));
    }
  }

  final families = <_Family>[];
}

/// One font family's outlines: its em size, whether its outlines are on
/// the Material grid, and code point to record offset in [bytes].
final class _Family {
  _Family(this.name, this.bytes, this.em, this.fits, this.ranges);

  final String name;
  final Uint8List bytes;
  final int em;
  final bool fits;
  final Map<int, int> ranges;

  /// Code point to decoded outline.
  final _decoded = <int, IconOutline>{};

  IconOutline? lookup(int codePoint) {
    final cached = _decoded[codePoint];
    if (cached != null) return cached;
    final offset = ranges[codePoint];
    if (offset == null) return null;
    return _decoded[codePoint] = _decode(offset);
  }

  IconOutline _decode(int offset) {
    final reader = OutlineDataReader(bytes, offset);
    final count = reader.varint();
    final verbs = Uint8List.sublistView(
      bytes,
      reader.offset,
      reader.offset + count,
    );
    reader.offset += count;
    var pointCount = 0;
    for (final verb in verbs) {
      pointCount += switch (verb) {
        OutlineVerb.move || OutlineVerb.line => 1,
        OutlineVerb.cubic => 3,
        _ => 0,
      };
    }
    final points = Int16List(pointCount * 2);
    var x = 0, y = 0;
    for (var i = 0; i < points.length; i += 2) {
      x += reader.zigzag();
      y += reader.zigzag();
      points[i] = x;
      points[i + 1] = y;
    }
    if (!fits) {
      return IconOutline(verbs, points, em: em, fits: false);
    }
    final flags = bytes[reader.offset++];
    final leftToRight = readIconOutlineAnalysis(reader);
    final rightToLeft = flags & 1 != 0 ? readIconOutlineAnalysis(reader) : null;
    return IconOutline(
      verbs,
      points,
      leftToRight: leftToRight,
      rightToLeft: rightToLeft,
    );
  }
}
