import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart';

const double _lengthWeight = 0.35;
const double _rotationTieBreak = 0.05;
const double _globalEpsilon = 5e-3;
const double _maxLogScale = 128;

double _finiteNumber(double value, String name) {
  if (!value.isFinite) {
    throw MeldException(
        'invalid-plan', 'Plan field "$name" must be finite and in range.');
  }
  return value;
}

double _nonNegativeNumber(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw MeldException(
        'invalid-plan', 'Plan field "$name" must be finite and non-negative.');
  }
  return value;
}

void _validatePair((double, double) value, String name) {
  if (!value.$1.isFinite ||
      !value.$2.isFinite ||
      value.$1.abs() > kMeldMaxCoordinate ||
      value.$2.abs() > kMeldMaxCoordinate) {
    throw MeldException('invalid-plan', 'Plan field "$name" must be finite.');
  }
}

void _validatePlanBuffer(Float64List values, String name) {
  if (values.length > kMeldMaxSamplePoints * 2 ||
      values.any(
          (value) => !value.isFinite || value.abs() > kMeldMaxCoordinate)) {
    throw MeldException(
        'invalid-plan', 'Plan field "$name" contains invalid coordinates.');
  }
}

final class Similarity {
  const Similarity(this.theta, this.scale, this.residual);
  final double theta;
  final double scale;
  final double residual;
}

final class Alignment extends Similarity {
  Alignment({
    required this.centerA,
    required this.centerB,
    required Float64List a,
    required Float64List b,
    required double theta,
    required double scale,
    required double residual,
  })  : a = Float64List.fromList(a).asUnmodifiableView(),
        b = Float64List.fromList(b).asUnmodifiableView(),
        super(theta, scale, residual);
  final (double, double) centerA;
  final (double, double) centerB;
  final Float64List a;
  final Float64List b;
}

final class BlockTransport {
  const BlockTransport({required this.offset, required this.drift});
  final (double, double) offset;
  final (double, double) drift;
}

final class MeldPlanItem {
  MeldPlanItem({
    required Float64List a,
    required Float64List centeredA,
    required Float64List transformedB,
    required Float64List orientedB,
    required this.centerA,
    required this.centerB,
    required double theta,
    required double logScale,
    required double residual,
    required this.closed,
    BlockTransport? block,
  })  : a = Float64List.fromList(a).asUnmodifiableView(),
        centeredA = Float64List.fromList(centeredA).asUnmodifiableView(),
        transformedB = Float64List.fromList(transformedB).asUnmodifiableView(),
        orientedB = Float64List.fromList(orientedB).asUnmodifiableView(),
        theta = _finiteNumber(theta, 'theta'),
        logScale = _finiteNumber(logScale, 'logScale'),
        residual = _nonNegativeNumber(residual, 'residual'),
        block = block {
    _validatePlanBuffer(this.a, 'a');
    _validatePlanBuffer(this.centeredA, 'centeredA');
    _validatePlanBuffer(this.transformedB, 'transformedB');
    _validatePlanBuffer(this.orientedB, 'orientedB');
    _validatePair(centerA, 'centerA');
    _validatePair(centerB, 'centerB');
    if (logScale.abs() > _maxLogScale) {
      throw MeldException(
        'invalid-plan',
        'Plan field "logScale" is outside the supported interpolation range.',
      );
    }
    if (this.a.length != this.centeredA.length ||
        this.a.length != this.transformedB.length ||
        this.a.length != this.orientedB.length ||
        this.a.length < 16 ||
        this.a.length.isOdd) {
      throw MeldException('invalid-plan',
          'Plan item buffers must have matching non-empty lengths.');
    }
    if (block != null) {
      _validatePair(block.offset, 'block.offset');
      _validatePair(block.drift, 'block.drift');
    }
  }

  final Float64List a;
  final Float64List centeredA;
  final Float64List transformedB;
  final Float64List orientedB;
  final (double, double) centerA;
  final (double, double) centerB;
  final double theta;
  final double logScale;
  final double residual;
  final bool closed;
  final BlockTransport? block;
}

final class MeldPlan {
  factory MeldPlan.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version != null && version != 1) {
      throw MeldException(
          'unsupported-plan-version', 'Unsupported MeldPlan version $version.');
    }
    final sampleCount = json['sampleCount'];
    if (sampleCount is! int ||
        sampleCount < 8 ||
        sampleCount > kMeldMaxSamplePoints) {
      throw MeldException(
          'invalid-plan',
          'Plan sampleCount must be an integer between 8 and '
              '$kMeldMaxSamplePoints.');
    }
    final rawItems = json['items'];
    if (rawItems is! List<Object?> ||
        rawItems.isEmpty ||
        rawItems.length > 512) {
      throw MeldException(
          'invalid-plan', 'Plan items must contain between 1 and 512 entries.');
    }
    Float64List points(Object? value, String name) {
      if (value is! List<Object?> || value.length != sampleCount * 2) {
        throw MeldException(
            'invalid-plan', 'Plan field "$name" has an invalid length.');
      }
      final output = Float64List(value.length);
      for (var i = 0; i < value.length; i++) {
        final item = value[i];
        if (item is! num || !item.isFinite) {
          throw MeldException('invalid-plan',
              'Plan field "$name" contains a non-finite value.');
        }
        output[i] = item.toDouble();
      }
      return output;
    }

    (double, double) center(Object? value, String name) {
      if (value is! List<Object?> ||
          value.length != 2 ||
          value.any((item) => item is! num || !item.isFinite)) {
        throw MeldException('invalid-plan',
            'Plan field "$name" must contain two finite values.');
      }
      return ((value[0] as num).toDouble(), (value[1] as num).toDouble());
    }

    double number(Map<String, Object?> item, String name) {
      final value = item[name];
      if (value is num && value.isFinite) return value.toDouble();
      throw MeldException('invalid-plan', 'Plan field "$name" must be finite.');
    }

    final items = <MeldPlanItem>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, Object?>)
        throw MeldException(
            'invalid-plan', 'Each plan item must be an object.');
      final blockValue = raw['block'];
      BlockTransport? block;
      if (blockValue != null) {
        if (blockValue is! Map<String, Object?>)
          throw MeldException('invalid-plan', 'Plan block must be an object.');
        block = BlockTransport(
          offset: center(blockValue['offset'], 'block.offset'),
          drift: center(blockValue['drift'], 'block.drift'),
        );
      }
      final closed = raw['closed'];
      if (closed is! bool)
        throw MeldException(
            'invalid-plan', 'Plan field "closed" must be boolean.');
      items.add(
        MeldPlanItem(
          a: points(raw['a'], 'a'),
          centeredA: points(raw['centeredA'], 'centeredA'),
          transformedB: points(raw['transformedB'], 'transformedB'),
          orientedB: points(raw['orientedB'], 'orientedB'),
          centerA: center(raw['centerA'], 'centerA'),
          centerB: center(raw['centerB'], 'centerB'),
          theta: number(raw, 'theta'),
          logScale: number(raw, 'logScale'),
          residual: number(raw, 'residual'),
          closed: closed,
          block: block,
        ),
      );
    }
    final rawDiagnostics = json['diagnostics'];
    final diagnostics = rawDiagnostics is Map<String, Object?>
        ? PlanDiagnostics.fromJson(rawDiagnostics)
        : PlanDiagnostics(
            sourceSubpaths: items.length,
            targetSubpaths: items.length,
            sampleCount: sampleCount,
            meanResidual: items
                    .map((item) => item.residual)
                    .fold<double>(0, (sum, value) => sum + value) /
                items.length,
            maxResidual:
                items.map((item) => item.residual).fold<double>(0, math.max),
            usedGlobalBlock: items.any((item) => item.block != null),
            elapsedMicros: 0,
            cacheHit: false,
          );
    return MeldPlan(
        items: items, sampleCount: sampleCount, diagnostics: diagnostics);
  }
  MeldPlan(
      {required Iterable<MeldPlanItem> items,
      required this.sampleCount,
      required this.diagnostics})
      : items = List<MeldPlanItem>.unmodifiable(items) {
    if (sampleCount < 8 || sampleCount > kMeldMaxSamplePoints) {
      throw MeldException('invalid-plan',
          'Plan sampleCount must be between 8 and $kMeldMaxSamplePoints.');
    }
    if (this.items.isEmpty || this.items.length > 512) {
      throw MeldException(
          'invalid-plan', 'Plan must contain between 1 and 512 subpath items.');
    }
    for (final item in this.items) {
      if (item.a.length != sampleCount * 2) {
        throw MeldException(
            'invalid-plan', 'Plan item buffers do not match sampleCount.');
      }
    }
    diagnostics.validate();
    if (diagnostics.sampleCount != sampleCount) {
      throw MeldException(
        'invalid-plan',
        'Plan diagnostics sampleCount does not match the plan.',
      );
    }
  }

  final List<MeldPlanItem> items;
  final int sampleCount;
  final PlanDiagnostics diagnostics;

  MeldPlan copyWithDiagnostics(PlanDiagnostics nextDiagnostics) => MeldPlan(
      items: items, sampleCount: sampleCount, diagnostics: nextDiagnostics);

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'sampleCount': sampleCount,
        'diagnostics': diagnostics.toJson(),
        'items': <Object?>[
          for (final item in items)
            <String, Object?>{
              'a': item.a.toList(),
              'centeredA': item.centeredA.toList(),
              'transformedB': item.transformedB.toList(),
              'orientedB': item.orientedB.toList(),
              'centerA': <double>[item.centerA.$1, item.centerA.$2],
              'centerB': <double>[item.centerB.$1, item.centerB.$2],
              'theta': item.theta,
              'logScale': item.logScale,
              'residual': item.residual,
              'closed': item.closed,
              if (item.block != null)
                'block': <String, Object?>{
                  'offset': <double>[
                    item.block!.offset.$1,
                    item.block!.offset.$2
                  ],
                  'drift': <double>[item.block!.drift.$1, item.block!.drift.$2],
                },
            },
        ],
      };
}

(double, double) centroid(Float64List points) {
  final count = points.length ~/ 2;
  var x = 0.0;
  var y = 0.0;
  for (var i = 0; i < count; i++) {
    x += points[i * 2];
    y += points[i * 2 + 1];
  }
  return (x / count, y / count);
}

double polylineLength(Float64List points) {
  var length = 0.0;
  for (var i = 2; i < points.length; i += 2) {
    length += math.sqrt(
      math.pow(points[i] - points[i - 2], 2) +
          math.pow(points[i + 1] - points[i - 1], 2),
    );
  }
  return length;
}

Float64List reversePoints(Float64List points) {
  final count = points.length ~/ 2;
  final out = Float64List(points.length);
  for (var i = 0; i < count; i++) {
    out[i * 2] = points[(count - 1 - i) * 2];
    out[i * 2 + 1] = points[(count - 1 - i) * 2 + 1];
  }
  return out;
}

Float64List rotatePoints(Float64List points, int offset) {
  final count = points.length ~/ 2;
  final out = Float64List(points.length);
  for (var i = 0; i < count; i++) {
    final source = (i + offset) % count;
    out[i * 2] = points[source * 2];
    out[i * 2 + 1] = points[source * 2 + 1];
  }
  return out;
}

Similarity procrustes(
  Float64List a,
  Float64List b,
  (double, double) centerA,
  (double, double) centerB,
) {
  var sxx = 0.0;
  var sxy = 0.0;
  var syx = 0.0;
  var syy = 0.0;
  var energyA = 0.0;
  var energyB = 0.0;
  for (var i = 0; i < a.length; i += 2) {
    final ax = a[i] - centerA.$1;
    final ay = a[i + 1] - centerA.$2;
    final bx = b[i] - centerB.$1;
    final by = b[i + 1] - centerB.$2;
    sxx += ax * bx;
    syy += ay * by;
    sxy += ax * by;
    syx += ay * bx;
    energyA += ax * ax + ay * ay;
    energyB += bx * bx + by * by;
  }
  final theta = math.atan2(sxy - syx, sxx + syy);
  final numerator =
      math.cos(theta) * (sxx + syy) + math.sin(theta) * (sxy - syx);
  var scale = energyA > 1e-12 ? numerator / energyA : 1.0;
  if (!(scale > 1e-6)) scale = 1e-6;
  final residualSquared =
      math.max(0, scale * scale * energyA - 2 * scale * numerator + energyB);
  final residual = energyB > 1e-12 ? math.sqrt(residualSquared / energyB) : 0.0;
  return Similarity(theta, scale, residual);
}

Alignment alignPair(Float64List a, Float64List b,
    {bool closedA = false, bool closedB = false}) {
  final centerA = centroid(a);
  final centerB = centroid(b);
  final varyA = closedA && !closedB;
  final base = varyA ? a : b;
  final offsets = closedA || closedB ? base.length ~/ 2 : 1;
  var bestScore = double.infinity;
  var best = base;
  var bestSimilarity = const Similarity(0, 1, 0);
  for (var direction = 0; direction < 2; direction++) {
    final walk = direction == 0 ? base : reversePoints(base);
    for (var offset = 0; offset < offsets; offset++) {
      final candidate = offset == 0 ? walk : rotatePoints(walk, offset);
      final similarity = varyA
          ? procrustes(candidate, b, centerA, centerB)
          : procrustes(a, candidate, centerA, centerB);
      final score = similarity.residual +
          _rotationTieBreak * similarity.theta.abs() / math.pi;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
        bestSimilarity = similarity;
      }
    }
  }
  return Alignment(
    centerA: centerA,
    centerB: centerB,
    a: varyA ? best : a,
    b: varyA ? b : best,
    theta: bestSimilarity.theta,
    scale: bestSimilarity.scale,
    residual: bestSimilarity.residual,
  );
}

List<List<double>> _costMatrix(List<Float64List> a, List<Float64List> b) {
  final centersB = b.map(centroid).toList(growable: false);
  final lengthsB = b.map(polylineLength).toList(growable: false);
  return a.map((points) {
    final center = centroid(points);
    final length = polylineLength(points);
    return <double>[
      for (var j = 0; j < b.length; j++)
        math.sqrt(math.pow(center.$1 - centersB[j].$1, 2) +
                math.pow(center.$2 - centersB[j].$2, 2)) +
            _lengthWeight * (length - lengthsB[j]).abs(),
    ];
  }).toList(growable: false);
}

List<int> _bestPermutation(List<List<double>> costs) {
  final count = costs.length;
  if (count > 8) {
    final pairs = <(double, int, int)>[];
    for (var i = 0; i < count; i++) {
      for (var j = 0; j < count; j++) {
        pairs.add((costs[i][j], i, j));
      }
    }
    pairs.sort((a, b) => a.$1.compareTo(b.$1));
    final output = List<int>.filled(count, -1);
    final used = List<bool>.filled(count, false);
    for (final pair in pairs) {
      if (output[pair.$2] < 0 && !used[pair.$3]) {
        output[pair.$2] = pair.$3;
        used[pair.$3] = true;
      }
    }
    return output;
  }
  final values = List<int>.generate(count, (i) => i);
  var best = List<int>.from(values);
  var bestCost = double.infinity;
  void permute(int index, double cost) {
    if (cost >= bestCost) return;
    if (index == count) {
      bestCost = cost;
      best = List<int>.from(values);
      return;
    }
    for (var i = index; i < count; i++) {
      final temp = values[index];
      values[index] = values[i];
      values[i] = temp;
      permute(index + 1, cost + costs[index][values[index]]);
      values[i] = values[index];
      values[index] = temp;
    }
  }

  permute(0, 0);
  return best;
}

List<int> _bestSurjection(List<List<double>> costs) {
  final big = costs.length;
  final small = costs.first.length;
  final assignment = costs.map((row) {
    var best = 0;
    for (var j = 1; j < row.length; j++) {
      if (row[j] < row[best]) best = j;
    }
    return best;
  }).toList();
  final counts = List<int>.filled(small, 0);
  for (final value in assignment) {
    counts[value]++;
  }
  for (var target = 0; target < small; target++) {
    if (counts[target] > 0) continue;
    var donor = -1;
    var extraCost = double.infinity;
    for (var i = 0; i < big; i++) {
      if (counts[assignment[i]] < 2) continue;
      final cost = costs[i][target] - costs[i][assignment[i]];
      if (cost < extraCost) {
        extraCost = cost;
        donor = i;
      }
    }
    if (donor < 0)
      throw MeldException('matching-failed',
          'Unable to build a surjective subpath assignment.');
    counts[assignment[donor]]--;
    assignment[donor] = target;
    counts[target]++;
  }
  return assignment;
}

MeldPlan buildPlan(List<SampledPath> source, List<SampledPath> target,
    {bool cacheHit = false}) {
  final stopwatch = Stopwatch()..start();
  if (source.isEmpty || target.isEmpty)
    throw MeldException(
        'empty-icon', 'Both icons must contain at least one subpath.');
  final sampleCount = source.first.pointCount;
  if (source.any((path) => path.pointCount != sampleCount) ||
      target.any((path) => path.pointCount != sampleCount)) {
    throw MeldException('sample-count-mismatch',
        'All source and target subpaths must use the same sample count.');
  }
  final a = source.map((path) => path.points).toList(growable: false);
  final b = target.map((path) => path.points).toList(growable: false);
  final pairs = <(int, int)>[];
  if (a.length == b.length) {
    final permutation = _bestPermutation(_costMatrix(a, b));
    for (var i = 0; i < a.length; i++) {
      pairs.add((i, permutation[i]));
    }
  } else if (a.length < b.length) {
    final assignment = _bestSurjection(_costMatrix(b, a));
    for (var j = 0; j < b.length; j++) {
      pairs.add((assignment[j], j));
    }
  } else {
    final assignment = _bestSurjection(_costMatrix(a, b));
    for (var i = 0; i < a.length; i++) {
      pairs.add((i, assignment[i]));
    }
  }
  final items = <MeldPlanItem>[];
  for (final pair in pairs) {
    final alignment = alignPair(
      a[pair.$1],
      b[pair.$2],
      closedA: source[pair.$1].closed,
      closedB: target[pair.$2].closed,
    );
    final centeredA = Float64List(sampleCount * 2);
    final transformedB = Float64List(sampleCount * 2);
    final orientedB = Float64List(sampleCount * 2);
    final cos = math.cos(-alignment.theta);
    final sin = math.sin(-alignment.theta);
    for (var i = 0; i < sampleCount; i++) {
      centeredA[i * 2] = alignment.a[i * 2] - alignment.centerA.$1;
      centeredA[i * 2 + 1] = alignment.a[i * 2 + 1] - alignment.centerA.$2;
      final bx = alignment.b[i * 2] - alignment.centerB.$1;
      final by = alignment.b[i * 2 + 1] - alignment.centerB.$2;
      transformedB[i * 2] = (bx * cos - by * sin) / alignment.scale;
      transformedB[i * 2 + 1] = (bx * sin + by * cos) / alignment.scale;
      orientedB[i * 2] = alignment.b[i * 2];
      orientedB[i * 2 + 1] = alignment.b[i * 2 + 1];
    }
    items.add(
      MeldPlanItem(
        a: alignment.a,
        centeredA: centeredA,
        transformedB: transformedB,
        orientedB: orientedB,
        centerA: alignment.centerA,
        centerB: alignment.centerB,
        theta: alignment.theta,
        logScale: math.log(alignment.scale),
        residual: alignment.residual,
        closed: source[pair.$1].closed && target[pair.$2].closed,
      ),
    );
  }
  final plannedItems = items.length > 1
      ? _applyGlobal(items, sampleCount)
      : List<MeldPlanItem>.unmodifiable(items);
  stopwatch.stop();
  final residuals = plannedItems.map((item) => item.residual);
  final diagnostics = PlanDiagnostics(
    sourceSubpaths: source.length,
    targetSubpaths: target.length,
    sampleCount: sampleCount,
    meanResidual:
        residuals.fold<double>(0, (sum, value) => sum + value) / items.length,
    maxResidual: residuals.fold<double>(0, math.max),
    usedGlobalBlock: plannedItems.any((item) => item.block != null),
    elapsedMicros: stopwatch.elapsedMicroseconds,
    cacheHit: cacheHit,
  );
  return MeldPlan(
      items: plannedItems, sampleCount: sampleCount, diagnostics: diagnostics);
}

List<MeldPlanItem> _applyGlobal(List<MeldPlanItem> items, int sampleCount) {
  final allA = Float64List(items.length * sampleCount * 2);
  final allB = Float64List(items.length * sampleCount * 2);
  for (var i = 0; i < items.length; i++) {
    allA.setRange(i * sampleCount * 2, (i + 1) * sampleCount * 2, items[i].a);
    allB.setRange(
        i * sampleCount * 2, (i + 1) * sampleCount * 2, items[i].orientedB);
  }
  final centerA = centroid(allA);
  final global = procrustes(allA, allB, centerA, centroid(allB));
  if (global.residual >= _globalEpsilon) {
    return List<MeldPlanItem>.unmodifiable(items);
  }
  final cos = math.cos(-global.theta);
  final sin = math.sin(-global.theta);
  final restoreCos = math.cos(global.theta);
  final restoreSin = math.sin(global.theta);
  final output = <MeldPlanItem>[];
  for (final item in items) {
    final transformedB = Float64List(sampleCount * 2);
    var error = 0.0;
    var energy = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final bx = item.orientedB[i * 2] - item.centerB.$1;
      final by = item.orientedB[i * 2 + 1] - item.centerB.$2;
      transformedB[i * 2] = (bx * cos - by * sin) / global.scale;
      transformedB[i * 2 + 1] = (bx * sin + by * cos) / global.scale;
      final ex = global.scale *
              (restoreCos * item.centeredA[i * 2] -
                  restoreSin * item.centeredA[i * 2 + 1]) -
          bx;
      final ey = global.scale *
              (restoreSin * item.centeredA[i * 2] +
                  restoreCos * item.centeredA[i * 2 + 1]) -
          by;
      error += ex * ex + ey * ey;
      energy += bx * bx + by * by;
    }
    final residual =
        energy > 1e-12 ? math.sqrt(error / energy).toDouble() : 0.0;
    final offsetX = item.centerA.$1 - centerA.$1;
    final offsetY = item.centerA.$2 - centerA.$2;
    final c1 = math.cos(item.theta) * global.scale;
    final s1 = math.sin(item.theta) * global.scale;
    final rotatedX = offsetX * c1 - offsetY * s1 - offsetX;
    final rotatedY = offsetX * s1 + offsetY * c1 - offsetY;
    output.add(
      MeldPlanItem(
        a: item.a,
        centeredA: item.centeredA,
        transformedB: transformedB,
        orientedB: item.orientedB,
        centerA: item.centerA,
        centerB: item.centerB,
        theta: global.theta,
        logScale: math.log(global.scale),
        residual: residual,
        closed: item.closed,
        block: BlockTransport(
          offset: (offsetX, offsetY),
          drift: (
            item.centerB.$1 - item.centerA.$1 - rotatedX,
            item.centerB.$2 - item.centerA.$2 - rotatedY,
          ),
        ),
      ),
    );
  }
  return List<MeldPlanItem>.unmodifiable(output);
}

List<Float64List> allocateOutputs(MeldPlan plan) => plan.items
    .map((_) => Float64List(plan.sampleCount * 2))
    .toList(growable: false);

void interpolatePlan(
  MeldPlan plan,
  double progress,
  List<Float64List> output, {
  MeldInterpolationStrategy strategy = MeldInterpolationStrategy.polar,
}) {
  if (!progress.isFinite) {
    throw MeldException('invalid-progress', 'Progress must be finite.');
  }
  progress = progress.clamp(0, 1).toDouble();
  if (output.length != plan.items.length) {
    throw MeldException(
        'output-size-mismatch', 'Output buffers do not match the plan.');
  }
  for (final buffer in output) {
    if (buffer.length != plan.sampleCount * 2) {
      throw MeldException(
          'output-size-mismatch', 'Output buffers do not match the plan.');
    }
  }
  switch (strategy) {
    case MeldInterpolationStrategy.linear:
      _interpolateLinear(plan, progress, output);
    case MeldInterpolationStrategy.polar:
      _interpolatePolar(plan, progress, output, progress);
    case MeldInterpolationStrategy.tangentAware:
      final blend = progress * progress * (3 - 2 * progress);
      _interpolatePolar(plan, progress, output, blend);
  }
}

void _interpolatePolar(MeldPlan plan, double progress, List<Float64List> output,
    double shapeProgress) {
  for (var itemIndex = 0; itemIndex < plan.items.length; itemIndex++) {
    final item = plan.items[itemIndex];
    final out = output[itemIndex];
    final scale = math.exp(item.logScale * progress);
    final angle = item.theta * progress;
    final cos = math.cos(angle) * scale;
    final sin = math.sin(angle) * scale;
    double centerX;
    double centerY;
    final block = item.block;
    if (block != null) {
      centerX = item.centerA.$1 +
          block.drift.$1 * progress +
          block.offset.$1 * cos -
          block.offset.$2 * sin -
          block.offset.$1;
      centerY = item.centerA.$2 +
          block.drift.$2 * progress +
          block.offset.$1 * sin +
          block.offset.$2 * cos -
          block.offset.$2;
    } else {
      centerX =
          item.centerA.$1 + (item.centerB.$1 - item.centerA.$1) * progress;
      centerY =
          item.centerA.$2 + (item.centerB.$2 - item.centerA.$2) * progress;
    }
    for (var i = 0; i < plan.sampleCount; i++) {
      final px = item.centeredA[i * 2] +
          (item.transformedB[i * 2] - item.centeredA[i * 2]) * shapeProgress;
      final py = item.centeredA[i * 2 + 1] +
          (item.transformedB[i * 2 + 1] - item.centeredA[i * 2 + 1]) *
              shapeProgress;
      out[i * 2] = centerX + px * cos - py * sin;
      out[i * 2 + 1] = centerY + px * sin + py * cos;
    }
  }
}

void _interpolateLinear(
    MeldPlan plan, double progress, List<Float64List> output) {
  for (var itemIndex = 0; itemIndex < plan.items.length; itemIndex++) {
    final item = plan.items[itemIndex];
    final out = output[itemIndex];
    for (var i = 0; i < item.a.length; i++) {
      out[i] = item.a[i] + (item.orientedB[i] - item.a[i]) * progress;
    }
  }
}

String sampledPathData(List<Float64List> paths, List<bool> closed) {
  if (paths.length != closed.length) {
    throw MeldException('output-size-mismatch',
        'Path and closure lists must have equal lengths.');
  }
  final buffer = StringBuffer();
  for (var p = 0; p < paths.length; p++) {
    final points = paths[p];
    if (points.length < 2 ||
        points.length.isOdd ||
        points.any((value) => !value.isFinite)) {
      throw MeldException('invalid-sampled-path',
          'Sampled path data must contain finite point pairs.');
    }
    buffer.write('M${_frameNumber(points[0])} ${_frameNumber(points[1])}');
    for (var i = 2; i < points.length; i += 2) {
      buffer
          .write('L${_frameNumber(points[i])} ${_frameNumber(points[i + 1])}');
    }
    if (closed[p]) buffer.write('Z');
  }
  return buffer.toString();
}

String _frameNumber(double value) => ((value * 100).round() / 100).toString();
