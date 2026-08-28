# meld_flutter

Native Flutter rendering for Meld. `MeldIcon` paints normalized geometry through a precise `CustomPainter` repaint boundary, while `MeldIconController` provides interruptible spring motion, scrubbing, pause/resume, and sequences.

## Install

```yaml
dependencies:
  meld_flutter: ^1.0.0
```

```dart
import 'package:meld_flutter/meld_flutter.dart';

final controller = MeldIconController(initialSource: from);

// Put the controller in a MeldIcon, then call:
await controller.morphTo(to, preset: SpringPreset.snappy);
```

The widget supports declarative, controlled-progress, and command-driven modes; `MeldIconTheme` supplies shared paint tokens; `MeldPaintStyle` supports explicit outlines, source-faithful original rendering, and combined fill-plus-outline rendering; and `MeldMotionMode.user` follows Flutter reduced-motion settings. Add a `label` for semantics or set `excludeFromSemantics` for decorative icons.

## Links

- [Three control modes](https://github.com/fluttercandies/meld#three-control-modes)
- [Live Showcase](https://fluttercandies.github.io/meld/)
- [API documentation](https://pub.dev/documentation/meld_flutter/latest/)
