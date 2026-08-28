library;

import 'package:flutter/widgets.dart';
import 'package:meld_font/meld_font.dart';
import 'package:meld_flutter/meld_flutter.dart';

export 'package:meld_core/meld_core.dart';
export 'package:meld_flutter/meld_flutter.dart';
export 'package:meld_font/meld_font.dart';

/// The stable namespace for convenience conversions exposed by Meld.
///
/// Geometry source types remain available as immutable classes such as
/// [PathDataSource] and [SvgMarkupSource]. Use this namespace for adapters
/// that turn framework-specific inputs into a [MeldSource].
abstract final class Meld {
  /// Converts a caller-owned font glyph reference into a [MeldSource].
  static MeldSource sourceFromFontGlyph(FontGlyphRef glyph,
      {double grid = 24}) {
    return fontGlyphToSource(glyph, grid: grid);
  }

  /// Converts [IconData] using caller-provided font bytes into a [MeldSource].
  static MeldSource sourceFromIconData(
    IconData icon, {
    required List<int> fontBytes,
    double grid = 24,
  }) {
    return iconDataToSource(icon, fontBytes: fontBytes, grid: grid);
  }
}
