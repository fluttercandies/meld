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

sealed class MeldSource {
  const MeldSource();
}

/// Raw SVG `d` data. The parser accepts all SVG path commands supported by
/// Meld and preserves the original text for canonical endpoint rendering.
final class PathDataSource extends MeldSource {
  const PathDataSource(this.d);

  final String d;
}

/// SVG markup source. The markup parser accepts stroke-centered geometry only.
final class SvgMarkupSource extends MeldSource {
  const SvgMarkupSource(this.markup);

  final String markup;
}

/// Structured SVG geometry. Attributes are immutable and intentionally mirror
/// the small, portable subset used by icon packages.
final class GeometrySource extends MeldSource {
  GeometrySource(Iterable<GeometryNode> nodes, {this.viewBox})
      : nodes = List<GeometryNode>.unmodifiable(nodes);

  final List<GeometryNode> nodes;
  final MeldViewBox? viewBox;
}

/// A normalized cubic source, useful for font adapters and precomputed assets.
final class CubicSource extends MeldSource {
  CubicSource(Iterable<CubicPath> paths)
      : paths = List<CubicPath>.unmodifiable(paths);

  final List<CubicPath> paths;
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
