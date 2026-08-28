import 'dart:typed_data';

/// Hard limits applied at public geometry boundaries.
///
/// The limits keep malformed or untrusted input from allocating unbounded
/// buffers while leaving ample room for production icon assets.
const int kMeldMaxCubicSegments = 16384;
const int kMeldMaxSamplePoints = 4096;

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
  }) : nodes = _freezeGeometryNodes(nodes);

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
  })  : paths = _freezeCubicPaths(paths),
        super();

  final List<CubicPath> paths;
  @override
  final MeldSourcePaintStyle paintStyle;
}

MeldSourcePaintStyle _inferSvgPaintStyle(String markup) {
  if (markup.length > 1 << 20) {
    throw MeldException(
        'svg-limit', 'SVG markup exceeds the 1 MiB safety limit.');
  }
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
  final tags = RegExp(r'<(/?)([a-zA-Z][\w:-]*)([^>]*)>');
  final inheritedStack = <Map<String, String>>[const <String, String>{}];
  var hasFill = false;
  var hasStroke = false;
  for (final match in tags.allMatches(body)) {
    final closing = match.group(1)!.isNotEmpty;
    final tag = match.group(2)!.toLowerCase();
    if (closing) {
      if (inheritedStack.length > 1) inheritedStack.removeLast();
      continue;
    }
    final effective = <String, String>{
      ...inheritedStack.last,
      ..._parseInlineSvgPaint(match.group(3)!),
    };
    if (!drawableTags.contains(tag)) {
      if (!match.group(3)!.trimRight().endsWith('/')) {
        inheritedStack.add(effective);
      }
      continue;
    }
    final fill = effective['fill'] ?? 'black';
    final stroke = effective['stroke'] ?? 'none';
    final opacity = effective['opacity'];
    final fillOpacity = effective['fill-opacity'];
    final strokeOpacity = effective['stroke-opacity'];
    final strokeWidth = effective['stroke-width'];
    if (_isVisibleSvgPaint(fill, opacity, fillOpacity)) hasFill = true;
    if (_isVisibleSvgPaint(stroke, opacity, strokeOpacity, strokeWidth)) {
      hasStroke = true;
    }
    if (hasFill && hasStroke) return MeldSourcePaintStyle.both;
    if (!match.group(3)!.trimRight().endsWith('/')) {
      inheritedStack.add(effective);
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
      : tag = _validateGeometryTag(tag),
        attributes = _freezeAttributes(attributes);

  final String tag;
  final Map<String, Object?> attributes;
}

Map<String, Object?> _freezeAttributes(Map<String, Object?> input) {
  return Map<String, Object?>.unmodifiable({
    for (final entry in input.entries) entry.key: _freezeAttribute(entry.value),
  });
}

Object? _freezeAttribute(Object? value) {
  if (value is Map<String, Object?>) return _freezeAttributes(value);
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeAttribute));
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeAttribute));
  }
  return value;
}

String _validateGeometryTag(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    throw MeldException('invalid-geometry', 'Geometry tag must not be empty.');
  }
  return normalized;
}

List<GeometryNode> _freezeGeometryNodes(Iterable<GeometryNode> input) {
  final output = <GeometryNode>[];
  for (final node in input) {
    if (output.length >= 512) {
      throw MeldException(
          'geometry-limit', 'An icon may contain at most 512 geometry nodes.');
    }
    output.add(node);
  }
  return List<GeometryNode>.unmodifiable(output);
}

List<CubicPath> _freezeCubicPaths(Iterable<CubicPath> input) {
  final output = <CubicPath>[];
  var segments = 0;
  for (final path in input) {
    if (output.length >= 512) {
      throw MeldException(
          'geometry-limit', 'An icon may contain at most 512 cubic paths.');
    }
    segments += path.segmentCount;
    if (segments > kMeldMaxCubicSegments) {
      throw MeldException(
        'geometry-limit',
        'An icon may contain at most $kMeldMaxCubicSegments cubic segments.',
      );
    }
    output.add(path);
  }
  return List<CubicPath>.unmodifiable(output);
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
    if (values.length != 4) {
      throw MeldException(
        'invalid-view-box',
        'viewBox must contain four finite values with positive width and height',
        suggestion: 'Use "0 0 24 24" or [0, 0, 24, 24].',
      );
    }
    final result = MeldViewBox(values[0], values[1], values[2], values[3]);
    result.validate();
    return result;
  }
  const MeldViewBox(this.minX, this.minY, this.width, this.height);

  final double minX;
  final double minY;
  final double width;
  final double height;

  /// Validates a viewBox created through the const constructor.
  void validate() {
    if (![minX, minY, width, height].every((value) => value.isFinite) ||
        width <= 0 ||
        height <= 0) {
      throw MeldException(
        'invalid-view-box',
        'viewBox must contain finite values and positive width and height.',
        suggestion: 'Use a finite viewBox such as "0 0 24 24".',
      );
    }
  }

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
      : points = _freezeCubicPoints(points) {
    if (segmentCount < 1) {
      throw MeldException('invalid-cubic-path',
          'A cubic path must contain at least one segment.');
    }
  }

  final Float64List points;
  final bool closed;

  int get segmentCount => (points.length ~/ 2 - 1) ~/ 3;
}

final class SampledPath {
  SampledPath(Float64List points, {required this.closed})
      : points = _freezeSampledPoints(points);

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

  void validate() {
    if (pointCount < 8 || pointCount > kMeldMaxSamplePoints) {
      throw MeldException(
        'invalid-sampling-config',
        'pointCount must be between 8 and $kMeldMaxSamplePoints.',
      );
    }
    if (maxPointCount < pointCount || maxPointCount > kMeldMaxSamplePoints) {
      throw MeldException(
        'invalid-sampling-config',
        'maxPointCount must be between pointCount and '
            '$kMeldMaxSamplePoints.',
      );
    }
    if (!cornerThreshold.isFinite || cornerThreshold < 0) {
      throw MeldException('invalid-sampling-config',
          'cornerThreshold must be finite and non-negative.');
    }
  }

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

  void validate() {
    if (!stiffness.isFinite ||
        stiffness <= 0 ||
        !damping.isFinite ||
        damping < 0 ||
        !mass.isFinite ||
        mass <= 0 ||
        !maxStep.isFinite ||
        maxStep <= 0 ||
        maxStep > 1) {
      throw MeldException(
        'invalid-spring-config',
        'Spring stiffness, damping, mass and maxStep must be finite; '
            'stiffness/mass/maxStep must be positive and maxStep must not exceed 1.',
      );
    }
  }

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

Float64List _freezeCubicPoints(Float64List input) {
  if (input.length < 8 || (input.length - 2) % 6 != 0) {
    throw MeldException(
      'invalid-cubic-path',
      'Cubic path points must contain p0 followed by cubic segments.',
    );
  }
  final segments = (input.length - 2) ~/ 6;
  if (segments > kMeldMaxCubicSegments) {
    throw MeldException(
      'geometry-limit',
      'A cubic path may contain at most $kMeldMaxCubicSegments segments.',
    );
  }
  for (final value in input) {
    if (!value.isFinite) {
      throw MeldException(
        'invalid-coordinate',
        'Cubic path coordinates must be finite.',
      );
    }
  }
  return Float64List.fromList(input).asUnmodifiableView();
}

Float64List _freezeSampledPoints(Float64List input) {
  final count = input.length ~/ 2;
  if (input.length.isOdd || count < 8) {
    throw MeldException('invalid-sampled-path',
        'A sampled path must contain at least 8 points.');
  }
  if (count > kMeldMaxSamplePoints) {
    throw MeldException(
      'sample-count-too-large',
      'A sampled path may contain at most $kMeldMaxSamplePoints points.',
    );
  }
  for (final value in input) {
    if (!value.isFinite) {
      throw MeldException(
        'invalid-coordinate',
        'Sampled path coordinates must be finite.',
      );
    }
  }
  return Float64List.fromList(input).asUnmodifiableView();
}
