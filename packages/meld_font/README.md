# meld_font

[![pub package](https://img.shields.io/pub/v/meld_font.svg)](https://pub.dev/packages/meld_font)
[![CI](https://github.com/fluttercandies/meld/actions/workflows/ci.yml/badge.svg)](https://github.com/fluttercandies/meld/actions/workflows/ci.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-6D5EF7.svg)](https://github.com/fluttercandies/meld/blob/main/LICENSE)

Optional pure Dart adapter that turns caller-owned static TrueType glyph outlines into Meld geometry. It resolves Unicode cmap entries, expands simple and composite `glyf` contours, and converts quadratic segments to cubic paths without bundling a font.

## Install

```yaml
dependencies:
  meld_font: ^1.0.0
```

```dart
import 'dart:typed_data';
import 'package:meld_core/meld_core.dart';
import 'package:meld_font/meld_font.dart';

MeldSource loadGlyph(Uint8List fontBytes) {
  return fontGlyphToSource(
    FontGlyphRef(
      fontBytes: fontBytes,
      codePoint: 0x2302,
      fontFamily: 'Your licensed font',
    ),
  );
}
```

The adapter rejects unsupported CFF, color, and variable outlines with a diagnostic `MeldException`. Supply a static TTF/OTF file your application is licensed to distribute, then pass the returned `MeldSource` to `MeldIcon` or `MeldEngine`.

## Links

- [Font input guidance](https://github.com/fluttercandies/meld#inputs)
- [API documentation](https://pub.dev/documentation/meld_font/latest/)
