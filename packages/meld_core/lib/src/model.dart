import 'dart:typed_data';

/// A structured failure from the parser, normalizer or planner.
class MeldException extends FormatException {
  MeldException(
    this.code,
    String message, {
    this.offset,
    this.source,
    this.suggestion,
  }) : super(message, source, offset);

  final String code;
  @override
  final int? offset;
  @override
  final String? source;
  final String? suggestion;

  @override
  String toString() {
    final location = offset == null ? '' : ' at offset $offset';
    final hint = suggestion == null ? '' : ' Suggestion: $suggestion';
    return 'MeldException[$code]$location: $message$hint';
  }
}

/// Describes the visual intent carried by a source when a widget uses its
/// `original` paint mode.
enum MeldSourcePaintStyle {
  /// The source is normally rendered as a contour stroke.
  outline,

  /// The source is normally rendered as a filled compound contour.
  fill,

  /// The source is rendered with both a fill and a contour stroke.
  both,
}

sealed class MeldSource {
  const MeldSource();

  /// The source's own rendering intent used by `MeldPaintStyle.original`.
  MeldSourcePaintStyle get paintStyle;
}

/// Raw SVG `d` data. The parser accepts all SVG path commands supported by
/// Meld and preserves the original text for canonical endpoint rendering.
/// Because `d` does not contain paint attributes, [paintStyle] is explicit
/// and defaults to an outline source.
final class PathDataSource extends MeldSource {
  const PathDataSource(
    this.d, {
    this.paintStyle = MeldSourcePaintStyle.outline,
  }) : super();

  final String d;
  @override
  final MeldSourcePaintStyle paintStyle;
}

/// SVG markup source.
///
/// When [paintStyle] is omitted, the source style is inferred from the
/// drawable elements' inline `fill`, `stroke` and `style` attributes. The
/// inference follows SVG's monochrome defaults (filled unless a stroke-only
/// declaration is present) and returns [MeldSourcePaintStyle.both] when both
/// operations are present. Pass [paintStyle] when the visual style is supplied
/// by external CSS that is not embedded in [markup].
final class SvgMarkupSource extends MeldSource {
  const SvgMarkupSource(this.markup, {MeldSourcePaintStyle? paintStyle})
      : _paintStyle = paintStyle,
        super();

  final String markup;
  @override
  MeldSourcePaintStyle get paintStyle =>
      _paintStyle ?? _inferSvgPaintStyle(markup);

  final MeldSourcePaintStyle? _paintStyle;
}

/// Structured SVG geometry. Attributes are immutable and intentionally mirror
/// the small, portable subset used by icon packages. [paintStyle] is explicit
/// because the node model does not carry a CSS cascade.
final class GeometrySource extends MeldSource {
  GeometrySource(
    Iterable<GeometryNode> nodes, {
    this.viewBox,
    this.paintStyle = MeldSourcePaintStyle.outline,
  }) : nodes = List<GeometryNode>.unmodifiable(nodes);

  final List<GeometryNode> nodes;
  final MeldViewBox? viewBox;
  @override
  final MeldSourcePaintStyle paintStyle;
}

/// A normalized cubic source, useful for font adapters and precomputed assets.
/// Set [paintStyle] to [MeldSourcePaintStyle.fill] for compound contours such
/// as font glyphs; the default keeps generic geometry as an outline source.
final class CubicSource extends MeldSource {
  CubicSource(
    Iterable<CubicPath> paths, {
    this.paintStyle = MeldSourcePaintStyle.outline,
  })  : paths = List<CubicPath>.unmodifiable(paths),
        super();

  final List<CubicPath> paths;
  @override
  final MeldSourcePaintStyle paintStyle;
}

MeldSourcePaintStyle _inferSvgPaintStyle(String markup) {
  final body = markup.replaceAll(
    RegExp(r'<(defs|mask|clippath|symbol)\b[^>]*>[\s\S]*?<\/\1>',
        caseSensitive: false),
    '',
  );
  const drawableTags = <String>{
    'path',
    'line',
    'circle',
    'ellipse',
    'rect',
    'polyline',
    'polygon',
  };
  final tags = RegExp(r'<([a-zA-Z][\w:-]*)([^>]*)\/?\s*>');
  final root = RegExp(r'<svg\b([^>]*)>', caseSensitive: false).firstMatch(body);
  final inherited = root == null
      ? const <String, String>{}
      : _parseInlineSvgPaint(root.group(1)!);
  var hasFill = false;
  var hasStroke = false;
  for (final match in tags.allMatches(body)) {
    final tag = match.group(1)!.toLowerCase();
    if (!drawableTags.contains(tag)) continue;
    final attributes = _parseInlineSvgPaint(match.group(2)!);
    final fill = attributes['fill'] ?? inherited['fill'] ?? 'black';
    final stroke = attributes['stroke'] ?? inherited['stroke'] ?? 'none';
    final opacity = attributes['opacity'] ?? inherited['opacity'];
    final fillOpacity = attributes['fill-opacity'] ?? inherited['fill-opacity'];
    final strokeOpacity =
        attributes['stroke-opacity'] ?? inherited['stroke-opacity'];
    final strokeWidth = attributes['stroke-width'] ?? inherited['stroke-width'];
    if (_isVisibleSvgPaint(fill, opacity, fillOpacity)) hasFill = true;
    if (_isVisibleSvgPaint(stroke, opacity, strokeOpacity, strokeWidth)) {
      hasStroke = true;
    }
  }
  if (hasStroke && hasFill) return MeldSourcePaintStyle.both;
  if (hasStroke) return MeldSourcePaintStyle.outline;
  return MeldSourcePaintStyle.fill;
}

Map<String, String> _parseInlineSvgPaint(String raw) {
  final attributes = <String, String>{};
  final style = <String, String>{};
  final expression = RegExp(r'''([\w:-]+)\s*=\s*(["'])(.*?)\2''');
  for (final match in expression.allMatches(raw)) {
    final key = match.group(1)!.toLowerCase();
    final value = match.group(3)!.trim();
    if (key == 'style') {
      for (final declaration in value.split(';')) {
        final separator = declaration.indexOf(':');
        if (separator <= 0) continue;
        style[declaration.substring(0, separator).trim().toLowerCase()] =
            declaration.substring(separator + 1).trim();
      }
    } else if (const <String>{
      'fill',
      'stroke',
      'opacity',
      'fill-opacity',
      'stroke-opacity',
      'stroke-width',
    }.contains(key)) {
      attributes[key] = value;
    }
  }
  attributes.addAll(style);
  return attributes;
}

bool _isVisibleSvgPaint(
  String value,
  String? opacity,
  String? channelOpacity, [
  String? width,
]) {
  final normalized = value.trim().toLowerCase();
  return normalized.isNotEmpty &&
      normalized != 'none' &&
      normalized != 'transparent' &&
      normalized != '0' &&
      normalized != '0%' &&
      !_isZeroSvgNumber(opacity) &&
      !_isZeroSvgNumber(channelOpacity) &&
      !_isZeroSvgNumber(width);
}

bool _isZeroSvgNumber(String? value) {
  if (value == null) return false;
  final normalized = value.trim().toLowerCase();
  if (normalized.endsWith('%')) {
    return double.tryParse(
          normalized.substring(0, normalized.length - 1),
        ) ==
        0;
  }
  return double.tryParse(normalized) == 0;
}

typedef MeldIconSource = MeldSource;

final class GeometryNode {
  GeometryNode(String tag, Map<String, Object?> attributes)
      : tag = tag.toLowerCase(),
        attributes = Map<String, Object?>.unmodifiable(attributes);

  final String tag;
  final Map<String, Object?> attributes;
}

final class MeldViewBox {
  factory MeldViewBox.parse(Object value) {
    late final List<double> values;
    try {
      values = switch (value) {
        final num n => <double>[0, 0, n.toDouble(), n.toDouble()],
        final String s => s
            .trim()
            .split(RegExp(r'[\s,]+'))
            .map(double.parse)
            .toList(growable: false),
        final List<num> list =>
          list.map((e) => e.toDouble()).toList(growable: false),
        _ => const <double>[],
      };
    } on FormatException {
      throw MeldException(
          'invalid-view-box', 'viewBox contains a non-numeric value.');
    }
    if (values.length != 4 ||
        !values.every((value) => value.isFinite) ||
        values[2] <= 0 ||
        values[3] <= 0) {
      throw MeldException(
        'invalid-view-box',
        'viewBox must contain four finite values with positive width and height',
        suggestion: 'Use "0 0 24 24" or [0, 0, 24, 24].',
      );
    }
    return MeldViewBox(values[0], values[1], values[2], values[3]);
  }
  const MeldViewBox(this.minX, this.minY, this.width, this.height);

  final double minX;
  final double minY;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is MeldViewBox &&
      other.minX == minX &&
      other.minY == minY &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(minX, minY, width, height);
}

/// Cubic path points are packed as x/y pairs: p0, c1, c2, p1, ...
final class CubicPath {
  CubicPath(Float64List points, {required this.closed})
      : points = Float64List.fromList(points);

  final Float64List points;
  final bool closed;

  int get segmentCount => (points.length ~/ 2 - 1) ~/ 3;
}

final class SampledPath {
  SampledPath(Float64List points, {required this.closed})
      : points = Float64List.fromList(points);

  final Float64List points;
  final bool closed;

  int get pointCount => points.length ~/ 2;
}

final class SamplingConfig {
  const SamplingConfig({
    this.pointCount = 64,
    this.cornerThreshold = 0.39269908169872414,
    this.adaptive = true,
    this.maxPointCount = 128,
  })  : assert(pointCount >= 8),
        assert(maxPointCount >= pointCount),
        assert(cornerThreshold >= 0);

  final int pointCount;
  final double cornerThreshold;
  final bool adaptive;
  final int maxPointCount;

  SamplingConfig copyWith({
    int? pointCount,
    double? cornerThreshold,
    bool? adaptive,
    int? maxPointCount,
  }) {
    return SamplingConfig(
      pointCount: pointCount ?? this.pointCount,
      cornerThreshold: cornerThreshold ?? this.cornerThreshold,
      adaptive: adaptive ?? this.adaptive,
      maxPointCount: maxPointCount ?? this.maxPointCount,
    );
  }
}

enum MeldInterpolationStrategy { polar, linear, tangentAware }

enum MeldMotionMode { never, user, always }

final class SpringConfig {
  const SpringConfig({
    this.stiffness = 420,
    this.damping = 30,
    this.mass = 1,
    this.maxStep = 0.1,
  })  : assert(stiffness > 0),
        assert(damping >= 0),
        assert(mass > 0),
        assert(maxStep > 0);

  final double stiffness;
  final double damping;
  final double mass;
  final double maxStep;

  SpringConfig copyWith({
    double? stiffness,
    double? damping,
    double? mass,
    double? maxStep,
  }) {
    return SpringConfig(
      stiffness: stiffness ?? this.stiffness,
      damping: damping ?? this.damping,
      mass: mass ?? this.mass,
      maxStep: maxStep ?? this.maxStep,
    );
  }
}

enum SpringPreset { smooth, snappy, bouncy }

SpringConfig springPreset(SpringPreset preset) {
  return switch (preset) {
    SpringPreset.smooth => const SpringConfig(stiffness: 170, damping: 26),
    SpringPreset.snappy => const SpringConfig(stiffness: 420, damping: 30),
    SpringPreset.bouncy => const SpringConfig(stiffness: 300, damping: 14),
  };
}

final class PlanDiagnostics {
  const PlanDiagnostics({
    required this.sourceSubpaths,
    required this.targetSubpaths,
    required this.sampleCount,
    required this.meanResidual,
    required this.maxResidual,
    required this.usedGlobalBlock,
    required this.elapsedMicros,
    required this.cacheHit,
    this.samplingError = 0,
  });

  final int sourceSubpaths;
  final int targetSubpaths;
  final int sampleCount;
  final double meanResidual;
  final double maxResidual;
  final bool usedGlobalBlock;
  final int elapsedMicros;
  final bool cacheHit;
  final double samplingError;

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceSubpaths': sourceSubpaths,
        'targetSubpaths': targetSubpaths,
        'sampleCount': sampleCount,
        'meanResidual': meanResidual,
        'maxResidual': maxResidual,
        'usedGlobalBlock': usedGlobalBlock,
        'elapsedMicros': elapsedMicros,
        'cacheHit': cacheHit,
        'samplingError': samplingError,
      };

  static PlanDiagnostics fromJson(Map<String, Object?> json) {
    int integer(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num && value.isFinite) return value.toInt();
      throw MeldException(
          'invalid-plan', 'Diagnostic field "$key" must be an integer.');
    }

    double decimal(String key) {
      final value = json[key];
      if (value is num && value.isFinite) return value.toDouble();
      throw MeldException(
          'invalid-plan', 'Diagnostic field "$key" must be finite.');
    }

    bool boolean(String key) {
      final value = json[key];
      if (value is bool) return value;
      throw MeldException(
          'invalid-plan', 'Diagnostic field "$key" must be boolean.');
    }

    return PlanDiagnostics(
      sourceSubpaths: integer('sourceSubpaths'),
      targetSubpaths: integer('targetSubpaths'),
      sampleCount: integer('sampleCount'),
      meanResidual: decimal('meanResidual'),
      maxResidual: decimal('maxResidual'),
      usedGlobalBlock: boolean('usedGlobalBlock'),
      elapsedMicros: integer('elapsedMicros'),
      cacheHit: boolean('cacheHit'),
      samplingError:
          json['samplingError'] == null ? 0 : decimal('samplingError'),
    );
  }
}

final class MorphSnapshot {
  MorphSnapshot({
    required Iterable<SampledPath> paths,
    required this.progress,
    required this.target,
    required this.flying,
    this.velocity = 0,
    this.diagnostics,
  }) : paths = List<SampledPath>.unmodifiable(paths);

  final List<SampledPath> paths;
  final double progress;
  final MeldSource? target;
  final bool flying;
  final double velocity;
  final PlanDiagnostics? diagnostics;
}
