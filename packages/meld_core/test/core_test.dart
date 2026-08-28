import 'dart:math' as math;

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
}

double _maxDifference(List<double> a, List<double> b) {
  expect(a.length, b.length);
  var result = 0.0;
  for (var i = 0; i < a.length; i++) {
    result = math.max(result, (a[i] - b[i]).abs());
  }
  return result;
}
