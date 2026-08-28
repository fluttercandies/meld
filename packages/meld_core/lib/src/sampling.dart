import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart';
import 'normalize.dart';

const List<double> _gaussNodes = <double>[
  0.1834346424956498,
  0.525532409916329,
  0.7966664774136267,
  0.9602898564975363,
];
const List<double> _gaussWeights = <double>[
  0.362683783378362,
  0.3137066458778873,
  0.2223810344533745,
  0.1012285362903763,
];

double _speed(Float64List points, int segment, double t) {
  final i = segment * 6;
  final u = 1 - t;
  final c0 = 3 * u * u;
  final c1 = 6 * u * t;
  final c2 = 3 * t * t;
  final dx = c0 * (points[i + 2] - points[i]) +
      c1 * (points[i + 4] - points[i + 2]) +
      c2 * (points[i + 6] - points[i + 4]);
  final dy = c0 * (points[i + 3] - points[i + 1]) +
      c1 * (points[i + 5] - points[i + 3]) +
      c2 * (points[i + 7] - points[i + 5]);
  return math.sqrt(dx * dx + dy * dy);
}

double _segmentLength(Float64List points, int segment, [double end = 1]) {
  final half = end / 2;
  var total = 0.0;
  for (var j = 0; j < 4; j++) {
    total += _gaussWeights[j] *
        (_speed(points, segment, half + half * _gaussNodes[j]) +
            _speed(points, segment, half - half * _gaussNodes[j]));
  }
  return total * half;
}

void _pointAt(
    Float64List points, int segment, double t, Float64List out, int offset) {
  final i = segment * 6;
  final u = 1 - t;
  final b0 = u * u * u;
  final b1 = 3 * u * u * t;
  final b2 = 3 * u * t * t;
  final b3 = t * t * t;
  out[offset] = b0 * points[i] +
      b1 * points[i + 2] +
      b2 * points[i + 4] +
      b3 * points[i + 6];
  out[offset + 1] = b0 * points[i + 1] +
      b1 * points[i + 3] +
      b2 * points[i + 5] +
      b3 * points[i + 7];
}

(double, double)? _tangent(Float64List points, int segment, bool atEnd) {
  final i = segment * 6;
  final base = atEnd ? i + 6 : i;
  final sign = atEnd ? -1.0 : 1.0;
  final candidates = atEnd ? const <int>[4, 2, 0] : const <int>[2, 4, 6];
  for (final candidate in candidates) {
    final dx = sign * (points[i + candidate] - points[base]);
    final dy = sign * (points[i + candidate + 1] - points[base + 1]);
    if (dx * dx + dy * dy > 1e-18) return (dx, dy);
  }
  return null;
}

List<int> detectCorners(CubicPath path, [double threshold = math.pi / 8]) {
  final points = path.points;
  final segments = path.segmentCount;
  final active = <int>[
    for (var i = 0; i < segments; i++)
      if (_segmentLength(points, i) > 1e-9) i,
  ];
  if (active.isEmpty) return const <int>[];
  final corners = <int>{};
  void test(int a, int b) {
    final u = _tangent(points, a, true);
    final v = _tangent(points, b, false);
    if (u == null || v == null) return;
    final angle =
        math.atan2(u.$1 * v.$2 - u.$2 * v.$1, u.$1 * v.$1 + u.$2 * v.$2).abs();
    if (angle > threshold) corners.add(b);
  }

  for (var i = 0; i + 1 < active.length; i++) {
    test(active[i], active[i + 1]);
  }
  if (path.closed && active.length > 1) test(active.last, active.first);
  return corners.toList()..sort();
}

double arcLength(CubicPath path) {
  var total = 0.0;
  for (var i = 0; i < path.segmentCount; i++) {
    total += _segmentLength(path.points, i);
  }
  return total;
}

double _invert(Float64List points, int segment, double target, double length) {
  if (target <= 0) return 0;
  if (target >= length) return 1;
  var low = 0.0;
  var high = 1.0;
  var t = target / length;
  for (var i = 0; i < 12; i++) {
    final error = _segmentLength(points, segment, t) - target;
    if (error.abs() < 1e-10 * length + 1e-14) break;
    if (error > 0) {
      high = t;
    } else {
      low = t;
    }
    final speed = _speed(points, segment, t);
    var next = speed > 1e-12 ? t - error / speed : (low + high) / 2;
    if (!(next > low && next < high)) next = (low + high) / 2;
    t = next;
  }
  return t;
}

Float64List resamplePath(CubicPath path, int count,
    {double cornerThreshold = math.pi / 8}) {
  if (count < 8) {
    throw MeldException(
        'sample-count-too-small', 'A path requires at least 8 sample points.');
  }
  final points = path.points;
  final segments = path.segmentCount;
  final out = Float64List(count * 2);
  void fill() {
    for (var i = 0; i < count; i++) {
      out[i * 2] = points[0];
      out[i * 2 + 1] = points[1];
    }
  }

  if (segments < 1) {
    fill();
    return out;
  }
  final lengths =
      List<double>.generate(segments, (i) => _segmentLength(points, i));
  final totalLength = lengths.fold<double>(0, (sum, value) => sum + value);
  if (totalLength < 1e-12) {
    fill();
    return out;
  }
  final corners = detectCorners(path, cornerThreshold);
  final anchors = path.closed
      ? (corners.isEmpty ? <int>[0] : corners)
      : (<int>{0, ...corners, segments}.toList()..sort());
  final runs = <(int, int)>[];
  if (path.closed) {
    for (var i = 0; i < anchors.length; i++) {
      runs.add((
        anchors[i],
        i + 1 < anchors.length ? anchors[i + 1] : anchors.first + segments
      ));
    }
  } else {
    for (var i = 0; i + 1 < anchors.length; i++) {
      runs.add((anchors[i], anchors[i + 1]));
    }
  }
  final runLengths = runs.map((run) {
    var length = 0.0;
    for (var i = run.$1; i < run.$2; i++) {
      length += lengths[i % segments];
    }
    return length;
  }).toList(growable: false);
  final intervalCount = path.closed ? count : count - 1;
  if (runs.length > intervalCount) {
    throw MeldException('sample-count-too-small',
        '$count samples cannot preserve ${runs.length} corner runs.');
  }
  final ideal = runLengths
      .map((length) => intervalCount * length / totalLength)
      .toList(growable: false);
  final allocations = ideal.map((value) => math.max(1, value.floor())).toList();
  var remainder =
      intervalCount - allocations.fold<int>(0, (sum, value) => sum + value);
  if (remainder > 0) {
    final order = <(int, int)>[
      for (var i = 0; i < ideal.length; i++)
        (((ideal[i] - ideal[i].floor()) * 1e9).round(), i),
    ]..sort((a, b) => b.$1.compareTo(a.$1) != 0
        ? b.$1.compareTo(a.$1)
        : a.$2.compareTo(b.$2));
    for (var i = 0; i < remainder; i++) {
      allocations[order[i % order.length].$2]++;
    }
  }
  while (remainder < 0) {
    var largest = 0;
    for (var i = 1; i < allocations.length; i++) {
      if (allocations[i] > allocations[largest]) largest = i;
    }
    if (allocations[largest] <= 1) break;
    allocations[largest]--;
    remainder++;
  }
  var write = 0;
  for (var r = 0; r < runs.length; r++) {
    final run = runs[r];
    final intervals = allocations[r];
    final runLength = runLengths[r];
    final anchorIndex = 6 * (run.$1 % segments);
    out[write * 2] = points[anchorIndex];
    out[write * 2 + 1] = points[anchorIndex + 1];
    write++;
    var segment = run.$1;
    var consumed = 0.0;
    for (var j = 1; j < intervals; j++) {
      final target = runLength * j / intervals;
      while (segment < run.$2 - 1 &&
          consumed + lengths[segment % segments] < target) {
        consumed += lengths[segment % segments];
        segment++;
      }
      final actual = segment % segments;
      final t = _invert(points, actual, target - consumed, lengths[actual]);
      _pointAt(points, actual, t, out, write * 2);
      write++;
    }
  }
  if (!path.closed) {
    out[write * 2] = points[segments * 6];
    out[write * 2 + 1] = points[segments * 6 + 1];
  }
  return out;
}

int adaptiveSampleCount(List<CubicPath> paths, SamplingConfig config) {
  if (!config.adaptive) return config.pointCount;
  var complexity = 0;
  for (final path in paths) {
    complexity += path.segmentCount * 3 +
        detectCorners(path, config.cornerThreshold).length * 4;
    for (var segment = 0; segment < path.segmentCount; segment++) {
      final index = segment * 6;
      final chord = math.sqrt(
        math.pow(path.points[index + 6] - path.points[index], 2) +
            math.pow(path.points[index + 7] - path.points[index + 1], 2),
      );
      final control = _controlPolygonLength(path.points, index);
      if (chord > 1e-9) {
        complexity += ((control / chord - 1) * 8).ceil().clamp(0, 24);
      }
    }
  }
  final recommended = math.max(config.pointCount, 16 + complexity);
  return math.min(config.maxPointCount, recommended);
}

double _controlPolygonLength(Float64List points, int index) {
  var length = 0.0;
  for (var i = index; i < index + 6; i += 2) {
    final next = i + 2;
    length += math.sqrt(
      math.pow(points[next] - points[i], 2) +
          math.pow(points[next + 1] - points[i + 1], 2),
    );
  }
  return length;
}

/// Estimates normalized geometric error left by a fixed sample budget.
/// The value is a conservative control-polygon excess divided by the square
/// of the sample count, so diagnostics can explain adaptive decisions.
double samplingErrorEstimate(List<CubicPath> paths, int sampleCount) {
  if (sampleCount < 1) {
    throw MeldException(
        'sample-count-too-small', 'Sample count must be positive.');
  }
  var maximum = 0.0;
  for (final path in paths) {
    for (var segment = 0; segment < path.segmentCount; segment++) {
      final index = segment * 6;
      final chord = math.sqrt(
        math.pow(path.points[index + 6] - path.points[index], 2) +
            math.pow(path.points[index + 7] - path.points[index + 1], 2),
      );
      if (chord > 1e-9) {
        maximum = math.max(
          maximum,
          (_controlPolygonLength(path.points, index) / chord - 1).abs(),
        );
      }
    }
  }
  return maximum / (sampleCount * sampleCount);
}

List<SampledPath> resampleIcon(MeldSource source,
    [SamplingConfig config = const SamplingConfig()]) {
  final paths = iconToCubics(source);
  if (paths.isEmpty)
    throw MeldException(
        'empty-icon', 'The icon contains no drawable geometry.');
  final count = adaptiveSampleCount(paths, config);
  return paths
      .map(
        (path) => SampledPath(
          resamplePath(path, count, cornerThreshold: config.cornerThreshold),
          closed: path.closed,
        ),
      )
      .toList(growable: false);
}
