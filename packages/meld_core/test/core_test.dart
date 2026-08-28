import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meld_core/meld_core.dart';
import 'package:test/test.dart';

void main() {
  const menu = PathDataSource('M4 6h16M4 12h16M4 18h16');
  const close = PathDataSource('M18 6 6 18M6 6l12 12');

  test('parses and normalizes SVG path commands', () {
    final paths = iconToCubics(const PathDataSource('m4 6h16v6l-2 2z'));
    expect(paths, isNotEmpty);
    expect(paths.first.points.every((point) => point.isFinite), isTrue);
    expect(paths.first.closed, isTrue);
  });

  test('plan is exact at endpoints and finite during flight', () {
    final engine = MeldEngine();
    final plan = engine.plan(menu, close);
    expect(plan.items.every((item) => item.sourceIndex != null), isTrue);
    expect(plan.items.every((item) => item.targetIndex != null), isTrue);
    final output = allocateOutputs(plan);
    interpolatePlan(plan, 0, output);
    for (var item = 0; item < plan.items.length; item++) {
      expect(_maxDifference(output[item], plan.items[item].a), lessThan(1e-9));
    }
    for (final progress in <double>[0.25, 0.5, 0.75, 1]) {
      interpolatePlan(plan, progress, output);
      for (final points in output) {
        expect(points.every((point) => point.isFinite), isTrue);
      }
    }
    expect(plan.diagnostics.sampleCount, greaterThanOrEqualTo(64));
    expect(plan.diagnostics.samplingError, greaterThanOrEqualTo(0));
  });

  test('spring settles and preserves finite state', () {
    final spring = MeldSpring(springPreset(SpringPreset.snappy));
    spring.start();
    var settled = false;
    for (var i = 0; i < 600 && !settled; i++) {
      settled = spring.step(1 / 60);
    }
    expect(settled, isTrue);
    expect(spring.position, closeTo(1, 0.001));
    expect(spring.velocity, closeTo(0, 0.02));
  });

  test('spring reverses direction without resetting position', () {
    final spring = MeldSpring(springPreset(SpringPreset.snappy));
    spring.start();
    spring.step(0.12);
    final position = spring.position;
    final velocity = spring.velocity;

    spring.reverse();

    expect(spring.target, 0);
    expect(spring.position, position);
    expect(spring.velocity, closeTo(-velocity, 1e-9));
    var settled = false;
    for (var i = 0; i < 600 && !settled; i++) {
      settled = spring.step(1 / 60);
    }
    expect(settled, isTrue);
    expect(spring.position, closeTo(0, 0.001));
    expect(spring.velocity, closeTo(0, 0.02));
  });

  test('closed paths preserve topology and emerge rotation', () {
    final square = GeometrySource(<GeometryNode>[
      GeometryNode(
          'rect', <String, Object?>{'x': 2, 'y': 2, 'width': 20, 'height': 20}),
    ]);
    final diamond = GeometrySource(<GeometryNode>[
      GeometryNode(
          'polygon', <String, Object?>{'points': '12 2 22 12 12 22 2 12'}),
    ]);
    final plan = MeldEngine().plan(square, diamond);
    expect(plan.items.single.closed, isTrue);
    expect(plan.items.single.residual, lessThan(1e-5));
    expect(plan.items.single.theta.abs(), closeTo(math.pi / 4, 0.02));
  });

  test('supports primitives, viewBox fitting and fill-oriented SVG markup', () {
    final source = SvgMarkupSource(
      '<svg viewBox="10 20 100 50"><rect x="10" y="20" width="100" height="50" fill="currentColor"/></svg>',
    );
    final paths = iconToCubics(source);
    expect(paths.single.closed, isTrue);
    final values = paths.single.points;
    expect(
        values.every((value) => value >= -1e-9 && value <= 24 + 1e-9), isTrue);
  });

  test('ignores SVG comments, style and script payloads', () {
    const source = SvgMarkupSource(
      '<svg viewBox="0 0 24 24">'
      '<!-- <path d="M0 0L24 24"/> -->'
      '<style>.icon { fill: none; }</style>'
      '<script>const fake = "<path d=\\"M0 0L24 24\\"/>";</script>'
      '<path d="M2 2L22 22"/>'
      '</svg>',
    );
    expect(iconToCubics(source), hasLength(1));
  });

  test('rejects negative primitive radii with diagnostics', () {
    expect(
      () => iconToCubics(
        GeometrySource(<GeometryNode>[
          GeometryNode('circle', <String, Object?>{'r': -1}),
        ]),
      ),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-radius')),
    );
  });

  test('retains the source paint intent for Original rendering', () {
    const pathFill = PathDataSource(
      'M4 4H20V20H4Z',
      paintStyle: MeldSourcePaintStyle.fill,
    );
    expect(pathFill.paintStyle, MeldSourcePaintStyle.fill);
    expect(
      fitViewBox(pathFill, const MeldViewBox(0, 0, 24, 24)).paintStyle,
      MeldSourcePaintStyle.fill,
    );
    expect(
      SvgMarkupSource(
        '<svg viewBox="0 0 24 24"><path d="M4 4H20V20H4Z" fill="none" stroke="currentColor"/></svg>',
      ).paintStyle,
      MeldSourcePaintStyle.outline,
    );
    expect(
      SvgMarkupSource(
        '<svg viewBox="0 0 24 24"><path d="M4 4H20V20H4Z" fill="currentColor" stroke="currentColor"/></svg>',
      ).paintStyle,
      MeldSourcePaintStyle.both,
    );
    expect(
      SvgMarkupSource(
        '<svg viewBox="0 0 24 24"><path style="fill:none;stroke:#fff" d="M4 4H20V20H4Z"/></svg>',
      ).paintStyle,
      MeldSourcePaintStyle.outline,
    );
    expect(
      SvgMarkupSource(
        '<svg viewBox="0 0 24 24"><g fill="none" stroke="currentColor">'
        '<path d="M4 4H20V20H4Z"/></g></svg>',
      ).paintStyle,
      MeldSourcePaintStyle.outline,
    );
    expect(
      SvgMarkupSource(
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M4 4H20V20H4Z"/></svg>',
      ).paintStyle,
      MeldSourcePaintStyle.outline,
    );
    expect(
      SvgMarkupSource(
        '<svg viewBox="0 0 24 24"><path d="M4 4H20V20H4Z" fill="none" stroke="currentColor"/></svg>',
        paintStyle: MeldSourcePaintStyle.fill,
      ).paintStyle,
      MeldSourcePaintStyle.fill,
    );
  });

  test('serializes and restores a plan without changing its flight', () {
    final plan = MeldEngine().plan(menu, close);
    final restored = MeldPlan.fromJson(plan.toJson());
    expect(
      restored.items
          .map((item) => (item.sourceIndex, item.targetIndex))
          .toList(),
      plan.items.map((item) => (item.sourceIndex, item.targetIndex)).toList(),
    );
    final originalOutput = allocateOutputs(plan);
    final restoredOutput = allocateOutputs(restored);
    interpolatePlan(plan, 0.37, originalOutput);
    interpolatePlan(restored, 0.37, restoredOutput);
    for (var i = 0; i < originalOutput.length; i++) {
      expect(
          _maxDifference(originalOutput[i], restoredOutput[i]), lessThan(1e-9));
    }
  });

  test('cache metrics are bounded and observable', () {
    final engine = MeldEngine(maxCacheEntries: 1);
    engine.plan(menu, close);
    final cachedPlan = engine.plan(menu, close);
    engine.sample(menu);
    engine.sample(menu);
    final stats = engine.cacheStats;
    expect(stats.entries, 1);
    expect(stats.sampleEntries, 1);
    expect(stats.hits, 1);
    expect(stats.sampleHits, 1);
    expect(cachedPlan.diagnostics.cacheHit, isTrue);
    expect(stats.bytes, greaterThan(0));
    expect(stats.bytes, stats.sampleBytes + stats.planBytes);
  });

  test('cache byte budget evicts oversized plans', () {
    final engine = MeldEngine(maxCacheEntries: 8, maxCacheBytes: 64);
    engine.plan(menu, close);
    expect(engine.cacheStats.planBytes, 0);
    expect(engine.cacheStats.entries, 0);
  });

  test('cached geometry buffers cannot be mutated by callers', () {
    final engine = MeldEngine();
    final plan = engine.plan(menu, close);
    final sampled = engine.sample(menu);

    expect(() => plan.items.first.a[0] = 0, throwsUnsupportedError);
    expect(() => plan.items.first.centeredA[0] = 0, throwsUnsupportedError);
    expect(() => sampled.first.points[0] = 0, throwsUnsupportedError);

    final cached = engine.plan(menu, close);
    expect(cached.items.first.a[0], plan.items.first.a[0]);
  });

  test('cache fingerprint keeps sub-decimal geometry distinct', () {
    const base = PathDataSource('M0 0L10 0');
    const nearby = PathDataSource('M0 0L10.00004 0');
    final engine = MeldEngine();
    engine.plan(base, base);
    engine.plan(base, nearby);
    expect(engine.cacheStats.misses, 2);
  });

  test('rejects malformed public geometry and configuration', () {
    expect(
      () => CubicPath(Float64List.fromList(<double>[0, 0]), closed: false),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-cubic-path')),
    );
    expect(
      () => SamplingConfig(pointCount: 8, maxPointCount: 5000).validate(),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-sampling-config')),
    );
    expect(
      () => MeldSpring(const SpringConfig(maxStep: 2)),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-spring-config')),
    );
    expect(
      () => CubicPath(
        Float64List.fromList(<double>[0, 0, 1e10, 0, 1e10, 0, 1e10, 0]),
        closed: false,
      ),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-coordinate')),
    );
    expect(
      () => parsePath('M0 0L10000000000 0'),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-path')),
    );
  });

  test('structured geometry attributes are deeply immutable', () {
    final points = <Object?>['0', '0', '24', '24'];
    final node = GeometryNode(
      'polyline',
      <String, Object?>{'points': points},
    );
    points[0] = '999';
    final frozen = node.attributes['points']! as List<Object?>;
    expect(frozen.first, '0');
    expect(frozen.length, 4);
    expect(
      () => frozen[0] = '1',
      throwsUnsupportedError,
    );
    expect(
      () => GeometryNode(
        'path',
        <String, Object?>{'d': StringBuffer('M0 0L1 1')},
      ),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-geometry-attribute')),
    );
    expect(
      () => GeometryNode(
        'circle',
        <String, Object?>{'r': double.nan},
      ),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-geometry-attribute')),
    );
  });

  test('invalid path reports source offset', () {
    expect(
      () => parsePath('M0 0 Lbad'),
      throwsA(isA<MeldException>()
          .having((error) => error.offset, 'offset', isNotNull)),
    );
  });

  test('rejects non-finite progress before writing output', () {
    final plan = MeldEngine().plan(menu, close);
    expect(
      () => interpolatePlan(plan, double.nan, allocateOutputs(plan)),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-progress')),
    );
  });

  test('rejects unsafe serialized interpolation scale and frame size', () {
    final plan = MeldEngine().plan(menu, close);
    final item = plan.items.first;
    expect(
      () => MeldPlanItem(
        a: item.a,
        centeredA: item.centeredA,
        transformedB: item.transformedB,
        orientedB: item.orientedB,
        centerA: item.centerA,
        centerB: item.centerB,
        theta: item.theta,
        logScale: 1e9,
        residual: item.residual,
        closed: item.closed,
      ),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'invalid-plan')),
    );
    expect(
      () => MeldFrame(
        paths: List<Float64List>.generate(
          513,
          (_) => Float64List(16),
        ),
        progress: 0,
        velocity: 0,
      ),
      throwsA(isA<MeldException>()
          .having((error) => error.code, 'code', 'frame-limit')),
    );
  });
}

double _maxDifference(List<double> a, List<double> b) {
  expect(a.length, b.length);
  var result = 0.0;
  for (var i = 0; i < a.length; i++) {
    result = math.max(result, (a[i] - b[i]).abs());
  }
  return result;
}
