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
  });
  final int entries;
  final int hits;
  final int misses;
  final int sampleEntries;
  final int sampleHits;
  final int sampleMisses;

  int get totalEntries => entries + sampleEntries;
}

/// Pure, reusable planner with bounded source and plan caches.
final class MeldEngine {
  MeldEngine({
    this.sampling = const SamplingConfig(),
    this.interpolation = MeldInterpolationStrategy.polar,
    this.maxCacheEntries = 128,
  }) {
    sampling.validate();
    if (maxCacheEntries <= 0) {
      throw MeldException(
          'invalid-cache-config', 'maxCacheEntries must be positive.');
    }
  }

  final SamplingConfig sampling;
  final MeldInterpolationStrategy interpolation;
  final int maxCacheEntries;
  final LinkedHashMap<String, List<SampledPath>> _sampleCache =
      LinkedHashMap<String, List<SampledPath>>();
  final LinkedHashMap<String, MeldPlan> _planCache =
      LinkedHashMap<String, MeldPlan>();
  int _hits = 0;
  int _misses = 0;
  int _sampleHits = 0;
  int _sampleMisses = 0;

  MeldCacheStats get cacheStats => MeldCacheStats(
        entries: _planCache.length,
        hits: _hits,
        misses: _misses,
        sampleEntries: _sampleCache.length,
        sampleHits: _sampleHits,
        sampleMisses: _sampleMisses,
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
    final cached = _sampleCache.remove(key);
    if (cached != null) {
      _sampleHits++;
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
    _trim(_sampleCache);
    return sampled;
  }

  MeldPlan plan(MeldSource source, MeldSource target) {
    final sourceKey = _fingerprint(source);
    final targetKey = _fingerprint(target);
    final key =
        '$sourceKey\u0000$targetKey|${sampling.pointCount}|${sampling.cornerThreshold}|${sampling.adaptive}|${sampling.maxPointCount}';
    final cached = _planCache.remove(key);
    if (cached != null) {
      _hits++;
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
    _trim(_planCache);
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
  }

  void _trim<K, V>(LinkedHashMap<K, V> cache) {
    while (cache.length > maxCacheEntries) {
      cache.remove(cache.keys.first);
    }
  }
}

final class MeldFrame {
  MeldFrame(
      {required Iterable<Float64List> paths,
      required this.progress,
      required this.velocity})
      : paths = List<Float64List>.unmodifiable(paths
            .map((path) => Float64List.fromList(path).asUnmodifiableView()));

  final List<Float64List> paths;
  final double progress;
  final double velocity;
}
