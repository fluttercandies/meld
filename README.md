<p align="center">
  <img src="assets/meld-lockup.svg" alt="Meld" width="280">
</p>

<p align="center"><strong>Shape transitions with a point of view.</strong><br>Deterministic geometry, spring motion, and a native Flutter surface in one small API.</p>

<p align="center">
  <a href="https://github.com/fluttercandies/meld">Repository</a> ·
  <a href="https://fluttercandies.github.io/meld/">Live showcase</a> ·
  <a href="examples/showcase">Showcase source</a> ·
  <a href="README.zh-CN.md">中文文档</a>
</p>

Meld turns one vector shape into another without the “rubber stamp” feeling of point-by-point interpolation. It plans correspondence, rotation, scale, topology, and spring state once, then keeps every frame cheap and inspectable.

## 3-minute start

```yaml
dependencies:
meld: ^1.0.0
```

```dart
import 'package:flutter/material.dart';
import 'package:meld/meld.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  static const menu = PathDataSource('M3 6H21M3 12H21M3 18H21');
  static const close = PathDataSource('M5 5L19 19M19 5L5 19');

  @override
  Widget build(BuildContext context) {
    return const MeldIcon(
      from: menu,
      to: close,
      progress: 0.5,
      size: 32,
      label: 'Menu',
    );
  }
}
```

The same `MeldIcon` supports an `icon` endpoint for declarative updates and a `controller` for imperative motion. `progress` is controlled and deterministic; it is ideal for a drag gesture, a scrubber, or a timeline editor.

## Three control modes

```dart
final controller = MeldIconController(initialSource: MenuButton.menu);

// Command mode: attach the controller through MeldIcon, then await completion.
await controller.morphTo(MenuButton.close, preset: SpringPreset.snappy);

// Scrub mode: no ticker, no hidden state.
controller.seek(MenuButton.close, 0.72);

// Sequence mode: transitions remain composable.
await controller.playSequence([MenuButton.menu, MenuButton.close]);
```

Use `MeldIconTheme` for a shared visual language. `MeldPaintStyle.stroke` draws the geometry outline, `fill` preserves closed glyph fills and holes, and `fillAndStroke` fills first before adding an outline.

## Inputs

- `PathDataSource`: SVG path commands including relative commands, shorthand curves, arcs, scientific notation, and implicit repeats.
- `SvgMarkupSource`: portable SVG geometry (`path`, `line`, `circle`, `ellipse`, `rect`, `polyline`, `polygon`) with `viewBox` support.
- `GeometrySource`: structured, serializable geometry for generated icons and fixtures.
- `CubicSource`: normalized cubic paths for precomputed assets and adapters.
- `meld_font`: optional static TTF/OTF outline adapter. Pass the font bytes you already have; Meld never downloads or bundles a font.

Font outlines are filled glyph geometry, not strokes. The adapter supports Unicode cmap, simple and composite TrueType glyphs, and quadratic-to-cubic conversion. CFF, color, and variable outlines fail explicitly with a diagnostic so a visual fallback cannot silently ship.

```dart
final data = await rootBundle.load('assets/YourLicensedFont.ttf');
final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
final home = Meld.sourceFromIconData(Icons.home_rounded, fontBytes: bytes);
final homeIcon = MeldIcon(
  icon: home,
  paintStyle: MeldPaintStyle.fillAndStroke,
  label: 'Home',
);
```

The font asset and its license stay in your application; only the outline geometry enters the plan.

## Why it feels natural

Ordinary interpolation assumes point *n* in one icon belongs to point *n* in the next. Meld first matches subpaths, searches closed-path cuts and winding, then solves a similarity transform. Polar interpolation lets a shape rotate and scale as a coherent object while tangent-aware easing protects smooth curves and real corners. If topology is ambiguous, the plan keeps the ambiguity in diagnostics instead of hiding it in a frame.

## Physics, quality, and observability

```dart
final plan = MeldEngine(
  sampling: const SamplingConfig(pointCount: 64, adaptive: true),
).plan(MenuButton.menu, MenuButton.close);

final json = plan.toJson();
final restored = MeldPlan.fromJson(json);
```

Plans are deterministic and serializable. Caches are bounded LRU caches with hit/miss metrics. `MeldDiagnosticsOverlay` is an opt-in panel for cache, residual, sample, spring, and planning information; keep it out of release layouts when you do not need it.

Run the reproducible desktop benchmark from the workspace:

```bash
melos bootstrap
melos run benchmark
```

Benchmark output is intentionally machine-readable enough to compare in CI. Treat a regression as a design problem and inspect the plan diagnostics before changing quality settings.

## Accessibility and platform behavior

`MeldIcon` is a regular Flutter widget: it works on mobile, desktop, and web without platform channels. Supply a `label` for image semantics or use `excludeFromSemantics` when the icon is purely decorative. `MeldMotionMode.user` follows `MediaQuery.disableAnimations`; `never` snaps to the endpoint and `always` is useful for a demo or a controlled preview.

## Showcase and documentation

The [`examples/showcase`](https://fluttercandies.github.io/meld/) app is a responsive inspection tool, not mock product data. It includes independent start/end selection, quick icon pairs, raw path data, SVG markup, real Flutter font glyph outlines, a progress scrubber, spring controls, quality presets, and a live diagnostics panel.

- [Architecture](guides/architecture.md)
- [Performance](guides/performance.md)
- [Troubleshooting](guides/troubleshooting.md)
- [Migration notes](guides/migration.md)

## Development

Meld uses Melos. Read `GOALS.md` before changing the workspace. The development flow is design → complete implementation → static checks → focused verification → full regression. This project does not use TDD.

```bash
melos bootstrap
melos run format
melos run analyze
melos run test
melos run benchmark
```

## License

Meld is released under the [MIT License](LICENSE). Font files remain the responsibility of the application that supplies them; check the font's own license before distributing its bytes.

If Meld helps your interface, try it in the showcase, open an issue with a reproducible fixture, or send a focused pull request: <https://github.com/fluttercandies/meld>.
