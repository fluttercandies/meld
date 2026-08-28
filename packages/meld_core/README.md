# meld_core

[![pub package](https://img.shields.io/pub/v/meld_core.svg)](https://pub.dev/packages/meld_core)
[![CI](https://github.com/fluttercandies/meld/actions/workflows/ci.yml/badge.svg)](https://github.com/fluttercandies/meld/actions/workflows/ci.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-6D5EF7.svg)](https://github.com/fluttercandies/meld/blob/main/LICENSE)

Pure Dart geometry planning for Meld. It has no Flutter or platform dependency, so the same deterministic plan can run in Dart VM, isolates, servers, and Flutter applications.

## Install

```yaml
dependencies:
  meld_core: ^1.0.0
```

```dart
import 'package:meld_core/meld_core.dart';

const from = PathDataSource('M3 6H21M3 12H21M3 18H21');
const to = PathDataSource('M5 5L19 19M19 5L5 19');

final engine = MeldEngine();
final plan = engine.plan(from, to);
final frame = allocateOutputs(plan);
interpolatePlan(plan, 0.5, frame);
```

The engine handles SVG commands and primitives, viewBox fitting, arc-length sampling, subpath matching, topology-aware alignment, similarity transforms, spring stepping, bounded caches, diagnostics, and JSON plan serialization. Endpoint frames remain canonical while flight frames use reusable typed buffers. Set `maxCacheBytes` when an application needs a tighter memory budget; the retained byte estimate is available from `engine.cacheStats`.

Sources carry the paint intent used by Flutter's `MeldPaintStyle.original`:
`PathDataSource`, `GeometrySource`, and `CubicSource` accept explicit
`MeldSourcePaintStyle` values, while `SvgMarkupSource` derives `fill`,
`stroke`, or `both` from inline SVG paint attributes unless overridden.

## Links

- [Meld guide](https://github.com/fluttercandies/meld#physics-quality-and-observability)
- [Performance notes](https://github.com/fluttercandies/meld/blob/main/guides/performance.md)
- [API documentation](https://pub.dev/documentation/meld_core/latest/)
