import 'dart:collection';
import 'dart:typed_data';

import 'model.dart';
import 'normalize.dart';
import 'plan.dart';
import 'sampling.dart';

final class MeldCacheStats {
  const MeldCacheStats({
    required this.entries,
    required this.hits,
    required this.misses,
    required this.sampleEntries,
    required this.sampleHits,
    required this.sampleMisses,
    this.bytes = 0,
    this.sampleBytes = 0,
    this.planBytes = 0,
  });
  final int entries;
  final int hits;
  final int misses;
  final int sampleEntries;
  final int sampleHits;
  final int sampleMisses;

  /// Approximate total bytes retained by both caches.
  final int bytes;

  /// Approximate bytes retained by the sampled-geometry cache.
  final int sampleBytes;

  /// Approximate bytes retained by the plan cache.
  final int planBytes;

  int get totalEntries => entries + sampleEntries;
}

/// Pure, reusable planner with bounded source and plan caches.
final class MeldEngine {
  MeldEngine({
    this.sampling = const SamplingConfig(),
    this.interpolation = MeldInterpolationStrategy.polar,
    this.maxCacheEntries = 128,
    this.maxCacheBytes = 32 * 1024 * 1024,
  }) {
    sampling.validate();
    if (maxCacheEntries <= 0) {
      throw MeldException(
          'invalid-cache-config', 'maxCacheEntries must be positive.');
    }
    if (maxCacheBytes <= 0 || maxCacheBytes > 1024 * 1024 * 1024) {
      throw MeldException(
        'invalid-cache-config',
        'maxCacheBytes must be between 1 and 1 GiB.',
      );
    }
  }

  final SamplingConfig sampling;
  final MeldInterpolationStrategy interpolation;

  /// Maximum number of entries retained in each LRU cache.
  final int maxCacheEntries;

  /// Approximate byte budget applied independently to the sample and plan
  /// caches. Oversized entries are not retained after they are computed.
  final int maxCacheBytes;
  final LinkedHashMap<String, List<SampledPath>> _sampleCache =
      LinkedHashMap<String, List<SampledPath>>();
  final LinkedHashMap<String, MeldPlan> _planCache =
      LinkedHashMap<String, MeldPlan>();
  int _hits = 0;
  int _misses = 0;
  int _sampleHits = 0;
  int _sampleMisses = 0;
  int _sampleCacheBytes = 0;
  int _planCacheBytes = 0;

  MeldCacheStats get cacheStats => MeldCacheStats(
        entries: _planCache.length,
        hits: _hits,
        misses: _misses,
        sampleEntries: _sampleCache.length,
        sampleHits: _sampleHits,
        sampleMisses: _sampleMisses,
        bytes: _sampleCacheBytes + _planCacheBytes,
        sampleBytes: _sampleCacheBytes,
        planBytes: _planCacheBytes,
      );

  String canonical(MeldSource source) => canonicalPathData(source);

  String _fingerprint(MeldSource source) {
    final buffer = StringBuffer();
    for (final path in iconToCubics(source)) {
      buffer
        ..write(path.closed ? '1:' : '0:')
        ..write(path.points.length)
        ..write(':');
      for (final value in path.points) {
        buffer
          ..write(value.toString())
          ..write(',');
      }
      buffer.write(';');
    }
    return buffer.toString();
  }

  List<SampledPath> sample(MeldSource source) {
    final key =
        '${_fingerprint(source)}|${sampling.pointCount}|${sampling.cornerThreshold}|${sampling.adaptive}|${sampling.maxPointCount}';
    final cached = _sampleCache[key];
    if (cached != null) {
      _sampleHits++;
      _sampleCache.remove(key);
      _sampleCache[key] = cached;
      return cached;
    }
    _sampleMisses++;
    final cubics = iconToCubics(source);
    final count = adaptiveSampleCount(cubics, sampling);
    final fixed = sampling.copyWith(
        pointCount: count, adaptive: false, maxPointCount: count);
    final sampled = List<SampledPath>.unmodifiable(
        resampleIcon(CubicSource(cubics), fixed));
    _sampleCache[key] = sampled;
    _sampleCacheBytes += _sampleBytes(sampled);
    _trimSampleCache();
    return sampled;
  }

  MeldPlan plan(MeldSource source, MeldSource target) {
    final sourceKey = _fingerprint(source);
    final targetKey = _fingerprint(target);
    final key =
        '$sourceKey\u0000$targetKey|${sampling.pointCount}|${sampling.cornerThreshold}|${sampling.adaptive}|${sampling.maxPointCount}';
    final cached = _planCache[key];
    if (cached != null) {
      _hits++;
      _planCache.remove(key);
      _planCache[key] = cached;
      final diagnostics = cached.diagnostics;
      return cached.copyWithDiagnostics(
        PlanDiagnostics(
          sourceSubpaths: diagnostics.sourceSubpaths,
          targetSubpaths: diagnostics.targetSubpaths,
          sampleCount: diagnostics.sampleCount,
          meanResidual: diagnostics.meanResidual,
          maxResidual: diagnostics.maxResidual,
          usedGlobalBlock: diagnostics.usedGlobalBlock,
          elapsedMicros: diagnostics.elapsedMicros,
          cacheHit: true,
          samplingError: diagnostics.samplingError,
        ),
      );
    }
    _misses++;
    final sourceCubics = iconToCubics(source);
    final targetCubics = iconToCubics(target);
    final count = adaptiveSampleCount(sourceCubics, sampling).clamp(
      sampling.pointCount,
      sampling.maxPointCount,
    );
    final targetCount = adaptiveSampleCount(targetCubics, sampling).clamp(
      sampling.pointCount,
      sampling.maxPointCount,
    );
    final fixedCount = count > targetCount ? count : targetCount;
    final fixed = sampling.copyWith(
        pointCount: fixedCount, adaptive: false, maxPointCount: fixedCount);
    final built = buildPlan(
      resampleIcon(CubicSource(sourceCubics), fixed),
      resampleIcon(CubicSource(targetCubics), fixed),
    );
    final samplingError = samplingErrorEstimate(sourceCubics, fixedCount);
    final targetSamplingError = samplingErrorEstimate(targetCubics, fixedCount);
    final diagnostics = built.diagnostics;
    final measured = built.copyWithDiagnostics(
      PlanDiagnostics(
        sourceSubpaths: diagnostics.sourceSubpaths,
        targetSubpaths: diagnostics.targetSubpaths,
        sampleCount: diagnostics.sampleCount,
        meanResidual: diagnostics.meanResidual,
        maxResidual: diagnostics.maxResidual,
        usedGlobalBlock: diagnostics.usedGlobalBlock,
        elapsedMicros: diagnostics.elapsedMicros,
        cacheHit: false,
        samplingError: samplingError > targetSamplingError
            ? samplingError
            : targetSamplingError,
      ),
    );
    _planCache[key] = measured;
    _planCacheBytes += _planBytes(measured);
    _trimPlanCache();
    return measured;
  }

  void prewarm(Iterable<(MeldSource, MeldSource)> pairs) {
    for (final pair in pairs) {
      plan(pair.$1, pair.$2);
    }
  }

  void clearCache() {
    _sampleCache.clear();
    _planCache.clear();
    _hits = 0;
    _misses = 0;
    _sampleHits = 0;
    _sampleMisses = 0;
    _sampleCacheBytes = 0;
    _planCacheBytes = 0;
  }

  void _trimSampleCache() {
    while (_sampleCache.length > maxCacheEntries ||
        _sampleCacheBytes > maxCacheBytes) {
      final key = _sampleCache.keys.first;
      final value = _sampleCache.remove(key)!;
      _sampleCacheBytes -= _sampleBytes(value);
    }
  }

  void _trimPlanCache() {
    while (_planCache.length > maxCacheEntries ||
        _planCacheBytes > maxCacheBytes) {
      final key = _planCache.keys.first;
      final value = _planCache.remove(key)!;
      _planCacheBytes -= _planBytes(value);
    }
  }

  int _sampleBytes(List<SampledPath> paths) => paths.fold<int>(
        0,
        (total, path) => total + path.points.length * 8,
      );

  int _planBytes(MeldPlan plan) => plan.items.fold<int>(
        0,
        (total, item) =>
            total +
            item.a.length * 8 +
            item.centeredA.length * 8 +
            item.transformedB.length * 8 +
            item.orientedB.length * 8,
      );
}

final class MeldFrame {
  MeldFrame(
      {required Iterable<Float64List> paths,
      required this.progress,
      required this.velocity})
      : paths = _freezeFramePaths(paths) {
    if (!progress.isFinite || !velocity.isFinite) {
      throw MeldException(
        'invalid-frame',
        'Frame progress and velocity must be finite.',
      );
    }
  }

  final List<Float64List> paths;
  final double progress;
  final double velocity;
}

List<Float64List> _freezeFramePaths(Iterable<Float64List> input) {
  final output = <Float64List>[];
  for (final path in input) {
    if (output.length >= 512) {
      throw MeldException(
        'frame-limit',
        'A morph frame may contain at most 512 paths.',
      );
    }
    final copy = Float64List.fromList(path);
    if (copy.length.isOdd ||
        copy.any(
            (value) => !value.isFinite || value.abs() > kMeldMaxCoordinate)) {
      throw MeldException(
        'invalid-frame',
        'Frame paths must contain finite coordinates within the '
            'supported range.',
      );
    }
    output.add(copy.asUnmodifiableView());
  }
  return List<Float64List>.unmodifiable(output);
}
