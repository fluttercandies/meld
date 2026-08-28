import 'dart:io';

import 'package:meld_core/meld_core.dart';
import 'package:meld_font/meld_font.dart';
import 'package:test/test.dart';

void main() {
  test('rejects truncated and unsupported font data with diagnostics', () {
    expect(
      () => fontGlyphToSource(
          FontGlyphRef(fontBytes: <int>[0, 1, 2], codePoint: 0x41)),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-font')),
    );
  });

  test('reads a static TrueType glyph when a system fixture is available', () {
    final candidates = <String>[
      '/System/Library/Fonts/Geneva.ttf',
      '/System/Library/Fonts/ArialHB.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ];
    String? path;
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        path = candidate;
        break;
      }
    }
    if (path == null) return;
    final source = fontGlyphToSource(
        FontGlyphRef(fontBytes: File(path).readAsBytesSync(), codePoint: 0x41));
    final paths = iconToCubics(source);
    expect(paths, isNotEmpty);
    expect(paths.every((item) => item.closed), isTrue);
    expect(paths.expand((item) => item.points).every((value) => value.isFinite),
        isTrue);
  });
}
