import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meld_core/meld_core.dart';

/// A pure-Dart reference to one glyph in caller-owned font bytes.
final class FontGlyphRef {
  FontGlyphRef({
    required List<int> fontBytes,
    required this.codePoint,
    this.fontFamily,
    this.maxComponents = 64,
    this.maxPoints = 10000,
  }) : fontBytes = Uint8List.fromList(fontBytes);

  final Uint8List fontBytes;
  final int codePoint;
  final String? fontFamily;
  final int maxComponents;
  final int maxPoints;
}

/// Converts a static TrueType glyph into a core source. CFF, color and
/// variable outlines are rejected explicitly until their geometry semantics
/// can be represented without losing fidelity.
MeldSource fontGlyphToSource(FontGlyphRef ref, {double grid = 24}) {
  final font = _TrueTypeFont(ref);
  final glyphId = font.glyphIdForCodePoint(ref.codePoint);
  if (glyphId == 0 && !font.hasGlyphZero) {
    throw MeldException('glyph-not-found',
        'No glyph for U+${ref.codePoint.toRadixString(16).toUpperCase()}.');
  }
  final paths = font.glyphPaths(glyphId);
  if (paths.isEmpty)
    throw MeldException(
        'empty-glyph', 'The requested glyph has no outline geometry.');
  final bounds = _bounds(paths);
  final width = bounds.maxX - bounds.minX;
  final height = bounds.maxY - bounds.minY;
  if (!(width > 0) || !(height > 0))
    throw MeldException(
        'empty-glyph', 'The requested glyph has a zero-sized outline.');
  final scale = math.min(grid / width, grid / height);
  final tx = (grid - width * scale) / 2 - bounds.minX * scale;
  final ty = (grid - height * scale) / 2 + bounds.maxY * scale;
  final normalized = paths.map((path) {
    final points = Float64List(path.points.length);
    for (var i = 0; i < points.length; i += 2) {
      points[i] = path.points[i] * scale + tx;
      points[i + 1] = -path.points[i + 1] * scale + ty;
    }
    return CubicPath(points, closed: true);
  });
  return CubicSource(
    normalized,
    paintStyle: MeldSourcePaintStyle.fill,
  );
}

({double minX, double minY, double maxX, double maxY}) _bounds(
    List<CubicPath> paths) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final path in paths) {
    for (var i = 0; i < path.points.length; i += 2) {
      minX = math.min(minX, path.points[i]);
      minY = math.min(minY, path.points[i + 1]);
      maxX = math.max(maxX, path.points[i]);
      maxY = math.max(maxY, path.points[i + 1]);
    }
  }
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

final class _TrueTypeFont {
  _TrueTypeFont(this.ref) : bytes = ref.fontBytes {
    _readDirectory();
    unitsPerEm = _u16At(head.offset + 18);
    indexToLocFormat = _i16At(head.offset + 50);
    glyphCount = _u16At(maxp.offset + 4);
    if (unitsPerEm <= 0 || glyphCount <= 0) {
      throw MeldException(
          'invalid-font', 'Font has invalid unitsPerEm or glyph count.');
    }
    if (indexToLocFormat != 0 && indexToLocFormat != 1) {
      throw MeldException(
          'unsupported-font', 'Unsupported glyph location format.');
    }
    locaOffsets = _readLoca();
    cmapSubtable = _selectCmap();
  }

  final FontGlyphRef ref;
  final Uint8List bytes;
  final Map<String, _Table> tables = <String, _Table>{};
  late final _Table head;
  late final _Table maxp;
  late final _Table loca;
  late final _Table glyf;
  late final int unitsPerEm;
  late final int indexToLocFormat;
  late final int glyphCount;
  late final List<int> locaOffsets;
  late final _CmapSubtable cmapSubtable;
  bool hasGlyphZero = true;

  int glyphIdForCodePoint(int codePoint) {
    if (codePoint < 0 || codePoint > 0x10FFFF)
      throw MeldException(
          'invalid-code-point', 'Code point is outside Unicode range.');
    return cmapSubtable.lookup(codePoint);
  }

  List<CubicPath> glyphPaths(int glyphId, [int depth = 0]) {
    if (glyphId < 0 || glyphId >= glyphCount)
      throw MeldException('glyph-not-found', 'Glyph id is outside the font.');
    if (depth > 16)
      throw MeldException('font-recursion-limit',
          'Composite glyph nesting exceeds the safety limit.');
    final start = locaOffsets[glyphId];
    final end = locaOffsets[glyphId + 1];
    if (end <= start) return const <CubicPath>[];
    final offset = glyf.offset + start;
    final contours = _i16At(offset);
    if (contours >= 0) return _simpleGlyph(offset, contours);
    return _compositeGlyph(offset, depth);
  }

  List<CubicPath> _simpleGlyph(int offset, int contourCount) {
    if (contourCount > ref.maxComponents * 4)
      throw MeldException('font-limit', 'Too many glyph contours.');
    var cursor = offset + 10;
    final ends = <int>[
      for (var i = 0; i < contourCount; i++) _u16At(cursor + i * 2)
    ];
    cursor += contourCount * 2;
    final pointCount = (ends.isEmpty ? -1 : ends.last) + 1;
    if (pointCount <= 0) return const <CubicPath>[];
    if (pointCount > ref.maxPoints)
      throw MeldException('font-limit', 'Glyph contains too many points.');
    final instructions = _u16At(cursor);
    cursor += 2 + instructions;
    final flags = <int>[];
    while (flags.length < pointCount) {
      final flag = _u8At(cursor++);
      flags.add(flag);
      if ((flag & 8) != 0) {
        final repeat = _u8At(cursor++);
        if (flags.length + repeat > pointCount)
          throw MeldException(
              'invalid-font', 'Glyph flag repeat exceeds point count.');
        for (var i = 0; i < repeat; i++) {
          flags.add(flag);
        }
      }
    }
    final xs = List<int>.filled(pointCount, 0);
    final ys = List<int>.filled(pointCount, 0);
    var x = 0;
    for (var i = 0; i < pointCount; i++) {
      final flag = flags[i];
      if ((flag & 2) != 0) {
        final delta = _u8At(cursor++);
        x += (flag & 16) != 0 ? delta : -delta;
      } else if ((flag & 16) == 0) {
        x += _i16At(cursor);
        cursor += 2;
      }
      xs[i] = x;
    }
    var y = 0;
    for (var i = 0; i < pointCount; i++) {
      final flag = flags[i];
      if ((flag & 4) != 0) {
        final delta = _u8At(cursor++);
        y += (flag & 32) != 0 ? delta : -delta;
      } else if ((flag & 32) == 0) {
        y += _i16At(cursor);
        cursor += 2;
      }
      ys[i] = y;
    }
    final paths = <CubicPath>[];
    var start = 0;
    for (final end in ends) {
      paths.add(_contour(xs.sublist(start, end + 1), ys.sublist(start, end + 1),
          flags.sublist(start, end + 1)));
      start = end + 1;
    }
    return paths;
  }

  List<CubicPath> _compositeGlyph(int offset, int depth) {
    var cursor = offset + 10;
    final paths = <CubicPath>[];
    var componentCount = 0;
    var more = true;
    while (more) {
      if (++componentCount > ref.maxComponents)
        throw MeldException(
            'font-limit', 'Composite glyph has too many components.');
      final flags = _u16At(cursor);
      final glyphId = _u16At(cursor + 2);
      cursor += 4;
      final argsAreWords = (flags & 1) != 0;
      final arg1 = argsAreWords ? _i16At(cursor) : _i8At(cursor);
      cursor += argsAreWords ? 2 : 1;
      final arg2 = argsAreWords ? _i16At(cursor) : _i8At(cursor);
      cursor += argsAreWords ? 2 : 1;
      if ((flags & 2) == 0) {
        throw MeldException('unsupported-font',
            'Composite point attachment is not supported; use XY offsets.');
      }
      var a = 1.0;
      var b = 0.0;
      var c = 0.0;
      var d = 1.0;
      if ((flags & 8) != 0) {
        a = d = _f2dot14(_i16At(cursor));
        cursor += 2;
      } else if ((flags & 64) != 0) {
        a = _f2dot14(_i16At(cursor));
        d = _f2dot14(_i16At(cursor + 2));
        cursor += 4;
      } else if ((flags & 128) != 0) {
        a = _f2dot14(_i16At(cursor));
        b = _f2dot14(_i16At(cursor + 2));
        c = _f2dot14(_i16At(cursor + 4));
        d = _f2dot14(_i16At(cursor + 6));
        cursor += 8;
      }
      for (final path in glyphPaths(glyphId, depth + 1)) {
        final transformed = Float64List(path.points.length);
        for (var i = 0; i < transformed.length; i += 2) {
          final x = path.points[i];
          final y = path.points[i + 1];
          transformed[i] = a * x + c * y + arg1;
          transformed[i + 1] = b * x + d * y + arg2;
        }
        paths.add(CubicPath(transformed, closed: path.closed));
      }
      more = (flags & 32) != 0;
    }
    return paths;
  }

  CubicPath _contour(List<int> xs, List<int> ys, List<int> flags) {
    if (xs.isEmpty || ys.isEmpty)
      throw MeldException('invalid-font', 'Empty contour.');
    final points = <(double, double, bool)>[
      for (var i = 0; i < xs.length; i++)
        (xs[i].toDouble(), ys[i].toDouble(), (flags[i] & 1) != 0),
    ];
    final expanded = <(double, double, bool)>[];
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      expanded.add(current);
      if (!current.$3 && !next.$3) {
        expanded.add(
            ((current.$1 + next.$1) / 2, (current.$2 + next.$2) / 2, true));
      }
    }
    final firstOn = expanded.indexWhere((point) => point.$3);
    if (firstOn < 0)
      throw MeldException(
          'invalid-font', 'Glyph contour has no on-curve point.');
    final ordered = <(double, double, bool)>[
      for (var i = 0; i < expanded.length; i++)
        expanded[(firstOn + i) % expanded.length],
    ];
    final startPoint = ordered.first;
    final builder = _QuadraticBuilder(startPoint.$1, startPoint.$2);
    var cursor = 1;
    while (cursor < ordered.length) {
      final point = ordered[cursor];
      if (point.$3) {
        builder.line(point.$1, point.$2);
        cursor++;
      } else {
        final endpoint = ordered[(cursor + 1) % ordered.length];
        builder.quadratic(point.$1, point.$2, endpoint.$1, endpoint.$2);
        cursor += 2;
      }
    }
    if ((builder.x - startPoint.$1).abs() > 1e-9 ||
        (builder.y - startPoint.$2).abs() > 1e-9) {
      builder.line(startPoint.$1, startPoint.$2);
    }
    return builder.finish();
  }

  void _readDirectory() {
    if (bytes.length < 12)
      throw MeldException('invalid-font', 'Font header is truncated.');
    final count = _u16At(4);
    if (12 + count * 16 > bytes.length)
      throw MeldException('invalid-font', 'Font table directory is truncated.');
    for (var i = 0; i < count; i++) {
      final offset = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final length = _u32At(offset + 12);
      final tableOffset = _u32At(offset + 8);
      if (tableOffset + length > bytes.length)
        throw MeldException('invalid-font', 'Font table $tag is truncated.');
      tables[tag] = _Table(tableOffset, length);
    }
    head = _required('head');
    maxp = _required('maxp');
    loca = _required('loca');
    glyf = _required('glyf');
    _required('cmap');
  }

  _Table _required(String tag) =>
      tables[tag] ??
      (throw MeldException(
          'unsupported-font', 'Font is missing required table $tag.'));

  List<int> _readLoca() {
    final expected = glyphCount + 1;
    final values = <int>[];
    if (indexToLocFormat == 0) {
      if (loca.length < expected * 2)
        throw MeldException('invalid-font', 'loca table is truncated.');
      for (var i = 0; i < expected; i++) {
        values.add(_u16At(loca.offset + i * 2) * 2);
      }
    } else {
      if (loca.length < expected * 4)
        throw MeldException('invalid-font', 'loca table is truncated.');
      for (var i = 0; i < expected; i++) {
        values.add(_u32At(loca.offset + i * 4));
      }
    }
    return values;
  }

  _CmapSubtable _selectCmap() {
    final cmap = _required('cmap');
    final count = _u16At(cmap.offset + 2);
    _CmapSubtable? best;
    for (var i = 0; i < count; i++) {
      final record = cmap.offset + 4 + i * 8;
      final platform = _u16At(record);
      final encoding = _u16At(record + 2);
      final offset = cmap.offset + _u32At(record + 4);
      final format = _u16At(offset);
      if (format == 12) {
        best = _CmapFormat12(bytes, offset);
        break;
      }
      if (format == 4 && (platform == 3 || platform == 0))
        best ??= _CmapFormat4(bytes, offset);
      if (encoding == 10 && format == 12) best = _CmapFormat12(bytes, offset);
    }
    return best ??
        (throw MeldException(
            'unsupported-font', 'Font has no Unicode cmap subtable.'));
  }

  int _u8At(int offset) => _read(offset, 1).first;
  int _i8At(int offset) =>
      _u8At(offset) > 127 ? _u8At(offset) - 256 : _u8At(offset);
  int _u16At(int offset) => _u16(bytes, offset);
  int _i16At(int offset) => _i16(bytes, offset);
  int _u32At(int offset) => _u32(bytes, offset);
  List<int> _read(int offset, int length) {
    if (offset < 0 || offset + length > bytes.length)
      throw MeldException('invalid-font', 'Font read exceeded file bounds.');
    return bytes.sublist(offset, offset + length);
  }
}

final class _Table {
  const _Table(this.offset, this.length);
  final int offset;
  final int length;
}

sealed class _CmapSubtable {
  const _CmapSubtable();
  int lookup(int codePoint);
}

final class _CmapFormat4 extends _CmapSubtable {
  _CmapFormat4(this.bytes, this.offset)
      : segmentCount = _u16(bytes, offset + 6) ~/ 2;
  final Uint8List bytes;
  final int offset;
  final int segmentCount;

  @override
  int lookup(int codePoint) {
    if (codePoint > 0xFFFF) return 0;
    final endBase = offset + 14;
    final startBase = endBase + segmentCount * 2 + 2;
    final deltaBase = startBase + segmentCount * 2;
    final rangeBase = deltaBase + segmentCount * 2;
    for (var i = 0; i < segmentCount; i++) {
      final end = _u16(bytes, endBase + i * 2);
      if (codePoint > end) continue;
      final start = _u16(bytes, startBase + i * 2);
      if (codePoint < start) return 0;
      final delta = _i16(bytes, deltaBase + i * 2);
      final range = _u16(bytes, rangeBase + i * 2);
      if (range == 0) return (codePoint + delta) & 0xFFFF;
      final glyphOffset = rangeBase + i * 2 + range + (codePoint - start) * 2;
      if (glyphOffset + 2 > bytes.length) return 0;
      final glyph = _u16(bytes, glyphOffset);
      return glyph == 0 ? 0 : (glyph + delta) & 0xFFFF;
    }
    return 0;
  }
}

final class _CmapFormat12 extends _CmapSubtable {
  _CmapFormat12(this.bytes, this.offset) : groups = _u32(bytes, offset + 12);
  final Uint8List bytes;
  final int offset;
  final int groups;

  @override
  int lookup(int codePoint) {
    var low = 0;
    var high = groups - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final start = _u32(bytes, offset + 16 + mid * 12);
      final end = _u32(bytes, offset + 20 + mid * 12);
      if (codePoint < start) {
        high = mid - 1;
      } else if (codePoint > end) {
        low = mid + 1;
      } else {
        return _u32(bytes, offset + 24 + mid * 12) + codePoint - start;
      }
    }
    return 0;
  }
}

final class _QuadraticBuilder {
  _QuadraticBuilder(this.x, this.y) : points = <double>[x, y];
  double x;
  double y;
  final List<double> points;

  void line(double nx, double ny) {
    cubic(x + (nx - x) / 3, y + (ny - y) / 3, x + 2 * (nx - x) / 3,
        y + 2 * (ny - y) / 3, nx, ny);
  }

  void quadratic(double cx, double cy, double nx, double ny) {
    cubic(x + 2 * (cx - x) / 3, y + 2 * (cy - y) / 3, nx + 2 * (cx - nx) / 3,
        ny + 2 * (cy - ny) / 3, nx, ny);
  }

  void cubic(double x1, double y1, double x2, double y2, double nx, double ny) {
    points.addAll(<double>[x1, y1, x2, y2, nx, ny]);
    x = nx;
    y = ny;
  }

  CubicPath finish() {
    if ((points[0] - x).abs() > 1e-9 || (points[1] - y).abs() > 1e-9)
      line(points[0], points[1]);
    return CubicPath(Float64List.fromList(points), closed: true);
  }
}

int _u16(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];
int _i16(Uint8List bytes, int offset) {
  final value = _u16(bytes, offset);
  return value > 32767 ? value - 65536 : value;
}

int _u32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

double _f2dot14(int value) => value / 16384;
