# meld

The one-import Flutter facade for deterministic vector shape morphing. `meld` combines the geometry planner, native `MeldIcon` widget, spring motion, diagnostics, and optional font-outline adapter.

## Install

```yaml
dependencies:
  meld: ^1.0.0
```

```dart
import 'package:meld/meld.dart';

const menu = PathDataSource('M3 6H21M3 12H21M3 18H21');
const close = PathDataSource('M5 5L19 19M19 5L5 19');

const icon = MeldIcon(
  from: menu,
  to: close,
  progress: 0.5,
  size: 32,
  label: 'Menu',
);
```

Use `progress` for deterministic scrubbing, `icon` for declarative transitions, or `MeldIconController` for commands and sequences. `MeldPaintStyle.fill`, `stroke`, and `fillAndStroke` cover both outline and filled geometry.

## Inputs and docs

The facade accepts SVG path data, structured geometry, SVG markup, cubic sources, and caller-owned static font bytes. The complete guide covers platform support, reduced motion, accessibility, performance, and troubleshooting:

- [Meld guide](https://github.com/fluttercandies/meld#3-minute-start)
- [Live Showcase](https://fluttercandies.github.io/meld/)
- [API documentation](https://pub.dev/documentation/meld/latest/)

Meld never downloads or bundles font files. Check the license of any font supplied by your application before distributing it.
