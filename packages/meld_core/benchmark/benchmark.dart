import 'dart:convert';
import 'dart:io';

import 'package:meld_core/meld_core.dart';

void main(List<String> args) {
  final check = args.contains('--check');
  final json = args.contains('--json');
  const source = PathDataSource('M3 6H21M3 12H21M3 18H21');
  const target = PathDataSource('M5 5L19 19M19 5L5 19');
  final engine = MeldEngine();
  const iterations = 1000;
  final coldSamples = <int>[];
  for (var i = 0; i < 100; i++) {
    engine.clearCache();
    final coldSource = PathDataSource('M3 ${6 + i / 100}H21M3 12H21M3 18H21');
    final stopwatch = Stopwatch()..start();
    engine.plan(coldSource, target);
    stopwatch.stop();
    coldSamples.add(stopwatch.elapsedMicroseconds);
  }
  final warmStopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    engine.plan(source, target);
  }
  warmStopwatch.stop();
  coldSamples.sort();
  final coldP95 = coldSamples[
      (coldSamples.length * 0.95).floor().clamp(0, coldSamples.length - 1)];
  final warmAverage = warmStopwatch.elapsedMicroseconds / iterations;
  final result = <String, Object>{
    'coldSamples': coldSamples.length,
    'coldP95Micros': coldP95,
    'warmIterations': iterations,
    'warmAverageMicros': warmAverage,
    'cacheHits': engine.cacheStats.hits,
    'cacheMisses': engine.cacheStats.misses,
  };
  if (json) {
    stdout.writeln(jsonEncode(result));
  } else {
    stdout.writeln('Meld plan benchmark');
    stdout.writeln('coldSamples=${coldSamples.length} p95=${coldP95}us');
    stdout.writeln(
        'warmIterations=$iterations average=${warmAverage.toStringAsFixed(3)}us');
    stdout.writeln(
        'cache hits=${engine.cacheStats.hits} misses=${engine.cacheStats.misses}');
  }
  if (check) {
    final baseline = jsonDecode(
      File('benchmark/baseline.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final maxCold = (baseline['maxColdP95Micros'] as num).toInt();
    final maxWarm = (baseline['maxWarmAverageMicros'] as num).toDouble();
    if (coldP95 > maxCold || warmAverage > maxWarm) {
      stderr.writeln(
        'Benchmark regression: P95 ${coldP95}us / warm ${warmAverage.toStringAsFixed(3)}us '
        'exceeds ${maxCold}us / ${maxWarm.toStringAsFixed(3)}us.',
      );
      exitCode = 1;
    }
  }
}
