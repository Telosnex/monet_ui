// The families and font files of the resolved google_fonts package.
//
// The one reader of the package (docs/design/ADR_fonts_in_monet_ui.md in
// telosnex, D3): tool/generate_fonts.dart and the telosnex fonts pipeline
// use it. For tools: it imports dart:io, so monet_ui.dart does not export
// it.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// One font file of a family.
class FontVariant {
  const FontVariant(this.weight, this.italic, this.hash, this.length);
  final int weight;
  final bool italic;
  final String hash;
  final int length;
  String get pickerName => '$weight${italic ? 'i' : ''}';

  /// The URL google_fonts downloads the file from (GoogleFontsFile.url).
  String get url => 'https://fonts.gstatic.com/s/a/$hash.ttf';
}

/// The resolved google_fonts package and its families.
class FontSource {
  const FontSource(this.directory, this.version, this.hash, this.families);
  final Directory directory;
  final String version;
  final String hash;
  final Map<String, List<FontVariant>> families;
}

/// The families and files in the source of google_fonts_lite.dart.
///
/// Throws if a family has missing, duplicate, or malformed variants.
Map<String, List<FontVariant>> parseLiteDescriptors(String source) {
  final families = RegExp(
    r"^    '([^']+)': \{",
    multiLine: true,
  ).allMatches(source).toList();
  final variants = RegExp(
    r"GoogleFontsVariant\(\s*fontWeight: FontWeight\.w(\d+),\s*"
    r"fontStyle: FontStyle\.(normal|italic),\s*\): (?:const )?"
    r"GoogleFontsFile\(\s*'([0-9a-f]{64})',\s*(\d+),",
  );
  final result = <String, List<FontVariant>>{};
  for (var i = 0; i < families.length; i++) {
    final family = families[i].group(1)!;
    final block = source.substring(
      families[i].end,
      i + 1 == families.length ? source.length : families[i + 1].start,
    );
    final entries = variants
        .allMatches(block)
        .map(
          (match) => FontVariant(
            int.parse(match.group(1)!),
            match.group(2) == 'italic',
            match.group(3)!,
            int.parse(match.group(4)!),
          ),
        )
        .toList();
    if (entries.isEmpty ||
        entries.length !=
            RegExp(r'GoogleFontsVariant\(').allMatches(block).length ||
        result.containsKey(family) ||
        entries.map((entry) => entry.pickerName).toSet().length !=
            entries.length) {
      throw FormatException(
        'Missing, duplicate, or malformed variants: $family',
      );
    }
    result[family] = entries;
  }
  if (result.isEmpty) throw const FormatException('No Lite descriptors found');
  return result;
}

/// The google_fonts package that [packageConfig] resolves.
FontSource readFontSource(File packageConfig) {
  final config = jsonDecode(packageConfig.readAsStringSync()) as Map;
  final entry = (config['packages'] as List).cast<Map>().singleWhere(
    (entry) => entry['name'] == 'google_fonts',
  );
  final directory = Directory.fromUri(
    packageConfig.absolute.uri.resolve(entry['rootUri'] as String),
  );
  final pubspec = File('${directory.path}/pubspec.yaml').readAsStringSync();
  final version = RegExp(
    r'^version: (\S+)',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!;
  final source = File('${directory.path}/lib/src/google_fonts_lite.dart')
      .readAsStringSync();
  return FontSource(
    directory,
    version,
    sha256.convert(utf8.encode(source)).toString(),
    parseLiteDescriptors(source),
  );
}
