import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart';
import 'parser.dart';

const double kappa = 0.5522847498307936;
const double _tau = math.pi * 2;

List<CubicPath> iconToCubics(MeldSource source) {
  final paths = switch (source) {
    PathDataSource(:final d) => _pathDataToCubics(d),
    SvgMarkupSource(:final markup) => _markupToCubics(markup),
    GeometrySource(:final nodes, :final viewBox) =>
      _fitPaths(_geometryToCubics(nodes), viewBox),
    CubicSource(:final paths) => paths
        .map((path) => CubicPath(path.points, closed: path.closed))
        .toList(growable: false),
  };
  return List<CubicPath>.unmodifiable(paths);
}

List<CubicPath> _pathDataToCubics(String data) {
  return List<CubicPath>.unmodifiable(parsePath(data)
      .map(_lowerSubpath)
      .whereType<CubicPath>()
      .toList(growable: false));
}

CubicPath? _lowerSubpath(RawSubpath raw) {
  final builder = _CubicBuilder(raw.x0, raw.y0);
  for (final segment in raw.segments) {
    switch (segment) {
      case RawLine(:final x, :final y):
        builder.line(x, y);
      case RawCubic(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x,
          :final y
        ):
        builder.cubic(x1, y1, x2, y2, x, y);
      case RawQuadratic(:final x1, :final y1, :final x, :final y):
        builder.quadratic(x1, y1, x, y);
      case RawArc(
          :final rx,
          :final ry,
          :final rotation,
          :final large,
          :final sweep,
          :final x,
          :final y
        ):
        builder.arc(rx, ry, rotation, large, sweep, x, y);
    }
  }
  return builder.finish(raw.closed);
}

List<CubicPath> _geometryToCubics(List<GeometryNode> nodes) {
  if (nodes.length > 512) {
    throw _invalid(
        'geometry-limit', 'An icon may contain at most 512 geometry nodes.');
  }
  final output = <CubicPath>[];
  var segmentCount = 0;
  for (final node in nodes) {
    final a = node.attributes;
    switch (node.tag) {
      case 'path':
        final d = a['d'];
        if (d is! String)
          throw _invalid(
              'path-missing-d', 'A path node needs a string d attribute.');
        final paths = _pathDataToCubics(d);
        output.addAll(paths);
        segmentCount +=
            paths.fold<int>(0, (sum, path) => sum + path.segmentCount);
      case 'line':
        final b = _CubicBuilder(_number(a, 'x1'), _number(a, 'y1'));
        b.line(_number(a, 'x2'), _number(a, 'y2'));
        final path = b.finish(false);
        if (path != null) {
          output.add(path);
          segmentCount += path.segmentCount;
        }
      case 'circle':
        final path = _ellipsePath(_number(a, 'cx'), _number(a, 'cy'),
            _number(a, 'r'), _number(a, 'r'));
        if (path != null) {
          output.add(path);
          segmentCount += path.segmentCount;
        }
      case 'ellipse':
        final path = _ellipsePath(_number(a, 'cx'), _number(a, 'cy'),
            _number(a, 'rx'), _number(a, 'ry'));
        if (path != null) {
          output.add(path);
          segmentCount += path.segmentCount;
        }
      case 'rect':
        final path = _rectPath(a);
        if (path != null) {
          output.add(path);
          segmentCount += path.segmentCount;
        }
      case 'polyline':
        final path = _polyPath(_points(a['points']), false);
        if (path != null) {
          output.add(path);
          segmentCount += path.segmentCount;
        }
      case 'polygon':
        final path = _polyPath(_points(a['points']), true);
        if (path != null) {
          output.add(path);
          segmentCount += path.segmentCount;
        }
      default:
        throw _invalid('unsupported-element',
            'Unsupported geometry element <${node.tag}>.');
    }
  }
  if (segmentCount > kMeldMaxCubicSegments) {
    throw _invalid('geometry-limit',
        'Geometry may contain at most $kMeldMaxCubicSegments cubic segments.');
  }
  if (output.isEmpty)
    throw _invalid('empty-icon', 'The icon contains no drawable geometry.');
  return List<CubicPath>.unmodifiable(output);
}

List<CubicPath> _markupToCubics(String markup, {bool applyViewBox = true}) {
  if (markup.length > 1 << 20) {
    throw _invalid('svg-limit', 'SVG markup exceeds the 1 MiB safety limit.');
  }
  if (!markup.trimLeft().startsWith('<')) {
    throw _invalid('invalid-svg-markup',
        'SvgMarkupSource expects SVG markup, not raw path data.');
  }
  final body = markup
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(
          RegExp(r'<(script|style)\b[^>]*>[\s\S]*?<\/\1>',
              caseSensitive: false),
          '')
      .replaceAll(
        RegExp(r'<(defs|mask|clippath|symbol)\b[^>]*>[\s\S]*?<\/\1>',
            caseSensitive: false),
        '',
      );
  final root = RegExp(r'<svg\b([^>]*)>', caseSensitive: false).firstMatch(body);
  MeldViewBox? viewBox;
  if (root != null) {
    final rootAttrs = _parseAttributes(root.group(1)!);
    final rawViewBox = rootAttrs['viewBox'];
    if (rawViewBox != null) viewBox = MeldViewBox.parse(rawViewBox);
  }
  final nodes = <GeometryNode>[];
  final tags = RegExp(r'<([a-zA-Z][\w:-]*)([^>]*)\/?>');
  for (final match in tags.allMatches(body)) {
    final tag = match.group(1)!.toLowerCase();
    if (const {
      'svg',
      'g',
      'title',
      'desc',
      'defs',
      'mask',
      'clippath',
      'symbol'
    }.contains(tag)) continue;
    if (!const {
      'path',
      'line',
      'circle',
      'ellipse',
      'rect',
      'polyline',
      'polygon'
    }.contains(tag)) {
      throw _invalid('unsupported-element', 'Unsupported SVG element <$tag>.');
    }
    final attrs = _parseAttributes(match.group(2)!);
    if (attrs.containsKey('transform')) {
      throw _invalid('unsupported-transform',
          'SVG transforms must be baked into path coordinates.');
    }
    nodes.add(GeometryNode(tag, attrs));
  }
  if (nodes.isEmpty)
    throw _invalid('empty-icon', 'The SVG contains no morphable geometry.');
  final paths = _geometryToCubics(nodes);
  return applyViewBox ? _fitPaths(paths, viewBox) : paths;
}

Map<String, Object?> _parseAttributes(String raw) {
  final attrs = <String, Object?>{};
  final expression = RegExp(r'''([\w:-]+)\s*=\s*(["'])(.*?)\2''');
  for (final match in expression.allMatches(raw)) {
    attrs[match.group(1)!] = match.group(3)!;
  }
  return attrs;
}

double _number(Map<String, Object?> attrs, String key, [double fallback = 0]) {
  final value = attrs[key];
  if (value == null) return fallback;
  final result =
      value is num ? value.toDouble() : double.tryParse(value.toString());
  if (result == null || !result.isFinite || result.abs() > kMeldMaxCoordinate) {
    throw _invalid(
      'invalid-number',
      'Attribute $key must be finite and no greater than '
          '$kMeldMaxCoordinate in absolute value.',
    );
  }
  return result;
}

List<double> _points(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return const <double>[];
  final values = text.split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
  if (values.any((value) =>
      value == null || !value.isFinite || value.abs() > kMeldMaxCoordinate)) {
    throw _invalid(
      'invalid-points',
      'Polyline points must be finite and no greater than '
          '$kMeldMaxCoordinate in absolute value.',
    );
  }
  return values.cast<double>();
}

CubicPath? _polyPath(List<double> values, bool closed) {
  if (values.length < 4 || values.length.isOdd) return null;
  final builder = _CubicBuilder(values[0], values[1]);
  for (var i = 2; i < values.length; i += 2) {
    builder.line(values[i], values[i + 1]);
  }
  return builder.finish(closed);
}

CubicPath? _ellipsePath(double cx, double cy, double rx, double ry) {
  if (rx < 0 || ry < 0) {
    throw _invalid('invalid-radius', 'Ellipse radii must be non-negative.');
  }
  if (rx.abs() < 1e-12 || ry.abs() < 1e-12) return null;
  final builder = _CubicBuilder(cx + rx, cy);
  final kx = kappa * rx;
  final ky = kappa * ry;
  builder.cubic(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
  builder.cubic(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
  builder.cubic(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
  builder.cubic(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
  return builder.finish(true);
}

CubicPath? _rectPath(Map<String, Object?> attrs) {
  final x = _number(attrs, 'x');
  final y = _number(attrs, 'y');
  final width = _number(attrs, 'width');
  final height = _number(attrs, 'height');
  if (width <= 0 || height <= 0) return null;
  var rx = attrs.containsKey('rx') ? _number(attrs, 'rx') : double.nan;
  var ry = attrs.containsKey('ry') ? _number(attrs, 'ry') : double.nan;
  if (rx.isNaN) rx = ry.isNaN ? 0 : ry;
  if (ry.isNaN) ry = rx;
  if (rx < 0 || ry < 0) {
    throw _invalid('invalid-radius', 'Rectangle radii must be non-negative.');
  }
  rx = rx.clamp(0, width / 2);
  ry = ry.clamp(0, height / 2);
  if (rx < 1e-12 || ry < 1e-12) {
    return _polyPath(
        <double>[x, y, x + width, y, x + width, y + height, x, y + height],
        true);
  }
  final right = x + width;
  final bottom = y + height;
  final builder = _CubicBuilder(x + rx, y);
  builder.line(right - rx, y);
  builder.arc(rx, ry, 0, false, true, right, y + ry);
  builder.line(right, bottom - ry);
  builder.arc(rx, ry, 0, false, true, right - rx, bottom);
  builder.line(x + rx, bottom);
  builder.arc(rx, ry, 0, false, true, x, bottom - ry);
  builder.line(x, y + ry);
  builder.arc(rx, ry, 0, false, true, x + rx, y);
  return builder.finish(true);
}

MeldException _invalid(String code, String message) =>
    MeldException(code, message);

final class _CubicBuilder {
  _CubicBuilder(this.x, this.y) : _points = <double>[x, y];

  double x;
  double y;
  final List<double> _points;

  void cubic(double x1, double y1, double x2, double y2, double nx, double ny) {
    _points.addAll(<double>[x1, y1, x2, y2, nx, ny]);
    x = nx;
    y = ny;
  }

  void line(double nx, double ny) {
    if ((nx - x).abs() < 1e-12 && (ny - y).abs() < 1e-12) return;
    cubic(x + (nx - x) / 3, y + (ny - y) / 3, x + 2 * (nx - x) / 3,
        y + 2 * (ny - y) / 3, nx, ny);
  }

  void quadratic(double x1, double y1, double nx, double ny) {
    cubic(
      x + 2 * (x1 - x) / 3,
      y + 2 * (y1 - y) / 3,
      nx + 2 * (x1 - nx) / 3,
      ny + 2 * (y1 - ny) / 3,
      nx,
      ny,
    );
  }

  void arc(double rx0, double ry0, double rotation, bool large, bool sweep,
      double nx, double ny) {
    final x0 = x;
    final y0 = y;
    if ((nx - x0).abs() < 1e-12 && (ny - y0).abs() < 1e-12) return;
    var rx = rx0.abs();
    var ry = ry0.abs();
    if (rx < 1e-12 || ry < 1e-12) {
      line(nx, ny);
      return;
    }
    final phi = rotation * math.pi / 180;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx = (x0 - nx) / 2;
    final dy = (y0 - ny) / 2;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;
    final lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry);
    if (lambda > 1) {
      final scale = math.sqrt(lambda);
      rx *= scale;
      ry *= scale;
    }
    final rx2 = rx * rx;
    final ry2 = ry * ry;
    final x1p2 = x1p * x1p;
    final y1p2 = y1p * y1p;
    var rad = (rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2) / (rx2 * y1p2 + ry2 * x1p2);
    if (rad < 0) rad = 0;
    final coef = (large == sweep ? -1 : 1) * math.sqrt(rad);
    final cxp = coef * rx * y1p / ry;
    final cyp = -coef * ry * x1p / rx;
    final centerX = cosPhi * cxp - sinPhi * cyp + (x0 + nx) / 2;
    final centerY = sinPhi * cxp + cosPhi * cyp + (y0 + ny) / 2;
    final startAngle = math.atan2((y1p - cyp) / ry, (x1p - cxp) / rx);
    var delta = math.atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - startAngle;
    if (!sweep && delta > 0) delta -= _tau;
    if (sweep && delta < 0) delta += _tau;
    final count = math.max(1, (delta.abs() / (math.pi / 2)).ceil());
    final step = delta / count;
    final alpha = 4 / 3 * math.tan(step / 4);
    double ex(double angle) =>
        centerX + rx * math.cos(angle) * cosPhi - ry * math.sin(angle) * sinPhi;
    double ey(double angle) =>
        centerY + rx * math.cos(angle) * sinPhi + ry * math.sin(angle) * cosPhi;
    double tx(double angle) =>
        -rx * math.sin(angle) * cosPhi - ry * math.cos(angle) * sinPhi;
    double ty(double angle) =>
        -rx * math.sin(angle) * sinPhi + ry * math.cos(angle) * cosPhi;
    var a0 = startAngle;
    var px = x0;
    var py = y0;
    for (var i = 1; i <= count; i++) {
      final a1 = startAngle + step * i;
      final px1 = i == count ? nx : ex(a1);
      final py1 = i == count ? ny : ey(a1);
      cubic(px + alpha * tx(a0), py + alpha * ty(a0), px1 - alpha * tx(a1),
          py1 - alpha * ty(a1), px1, py1);
      a0 = a1;
      px = px1;
      py = py1;
    }
  }

  CubicPath? finish(bool closed) {
    if (closed) line(_points[0], _points[1]);
    if (_points.length < 8) return null;
    return CubicPath(Float64List.fromList(_points), closed: closed);
  }
}

MeldSource fitViewBox(MeldSource source, MeldViewBox viewBox,
    {double grid = 24}) {
  if (!(grid > 0) || !grid.isFinite || grid > kMeldMaxCoordinate) {
    throw _invalid(
      'invalid-grid',
      'Grid size must be finite, positive and no greater than '
          '$kMeldMaxCoordinate.',
    );
  }
  final rawPaths = switch (source) {
    GeometrySource(:final nodes) => _geometryToCubics(nodes),
    SvgMarkupSource(:final markup) =>
      _markupToCubics(markup, applyViewBox: false),
    _ => iconToCubics(source),
  };
  final paths = _fitPaths(rawPaths, viewBox, grid: grid);
  return CubicSource(paths, paintStyle: source.paintStyle);
}

List<CubicPath> _fitPaths(List<CubicPath> paths, MeldViewBox? viewBox,
    {double grid = 24}) {
  if (viewBox == null) return paths;
  viewBox.validate();
  if (!(grid > 0) || !grid.isFinite || grid > kMeldMaxCoordinate) {
    throw _invalid(
      'invalid-grid',
      'Grid size must be finite, positive and no greater than '
          '$kMeldMaxCoordinate.',
    );
  }
  final scale = math.min(grid / viewBox.width, grid / viewBox.height);
  final tx = (grid - viewBox.width * scale) / 2 - viewBox.minX * scale;
  final ty = (grid - viewBox.height * scale) / 2 - viewBox.minY * scale;
  return List<CubicPath>.unmodifiable(paths
      .map(
        (path) => CubicPath(
          Float64List.fromList(
            [
              for (var i = 0; i < path.points.length; i += 2) ...<double>[
                path.points[i] * scale + tx,
                path.points[i + 1] * scale + ty,
              ],
            ],
          ),
          closed: path.closed,
        ),
      )
      .toList(growable: false));
}

String canonicalPathData(MeldSource source) {
  final paths = iconToCubics(source);
  if (paths.isEmpty)
    throw _invalid('empty-icon', 'The icon contains no drawable geometry.');
  final out = StringBuffer();
  for (final path in paths) {
    out.write('M${_format(path.points[0])} ${_format(path.points[1])}');
    for (var i = 2; i < path.points.length; i += 6) {
      out.write(
        'C${_format(path.points[i])} ${_format(path.points[i + 1])} '
        '${_format(path.points[i + 2])} ${_format(path.points[i + 3])} '
        '${_format(path.points[i + 4])} ${_format(path.points[i + 5])}',
      );
    }
    if (path.closed) out.write('Z');
  }
  return out.toString();
}

String _format(double value) => (value * 10000).round() / 10000 == 0
    ? '0'
    : ((value * 10000).round() / 10000).toString();
