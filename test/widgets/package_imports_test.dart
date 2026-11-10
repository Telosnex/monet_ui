// Reads the package's files with dart:io.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

// ADR 003 (Telosnex app, lib/features/monet_ui/docs/), invariant I1: the
// package does not import the Telosnex app.

final _directive = RegExp(r'^(?:import|export|part)\s[^;]*;', multiLine: true);
final _uri = RegExp(r"""['"]([^'"]+)['"]""");

List<String> _uris(File file) => [
  for (final directive in _directive.allMatches(file.readAsStringSync()))
    for (final match in _uri.allMatches(directive[0]!)) match[1]!,
];

/// `lib/` paths that [path] reaches through package and relative imports.
Set<String> _reachable(String path) {
  final seen = <String>{};
  final stack = [path];
  while (stack.isNotEmpty) {
    final from = stack.removeLast();
    if (!seen.add(from)) continue;
    for (final uri in _uris(File(from))) {
      final String target;
      if (uri.startsWith('package:monet_ui/')) {
        target = 'lib/${uri.substring('package:monet_ui/'.length)}';
      } else if (!uri.contains(':')) {
        target = Uri.parse(from).resolve(uri).path;
      } else {
        continue;
      }
      stack.add(target);
    }
  }
  return seen..remove(path);
}

void main() {
  test('no file imports the Telosnex app', () {
    final found = [
      for (final entry in Directory('lib').listSync(recursive: true))
        if (entry is File && entry.path.endsWith('.dart'))
          for (final uri in _uris(entry))
            if (uri.startsWith('package:telosnex/')) '${entry.path}: $uri',
    ];
    expect(found, isEmpty);
  });

  test('icon size math does not import controls', () {
    // Moved from the app's data_composition_dependency_boundary_test.
    expect(
      _reachable('lib/widgets/tool_icon_size.dart'),
      isNot(contains('lib/widgets/bordered.dart')),
    );
  });
}
