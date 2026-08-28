# meld_font

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
