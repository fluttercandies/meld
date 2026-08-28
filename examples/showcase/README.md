# Meld Showcase

An interactive inspection app for the Meld Flutter workspace. It demonstrates responsive layout, independent start/end icon selection, reusable quick-pair plans, path data, SVG markup, and real font glyph outlines from a bundled Cupertino TTF. Controlled scrubbing, spring parameters, outline/original/both paint modes, quality presets, reduced-motion behavior, and live diagnostics are available in the same flow.

```bash
flutter run -d chrome
flutter run -d macos
flutter build apk --debug
flutter build ios --debug --no-codesign
```

The showcase is intentionally built from the public `meld` facade so every interaction exercises the same API a downstream app uses.

Use the `Build a transition` panel to choose the start and end independently, including mixed-format transitions. `Path data` uses raw SVG `d` strings, `SVG markup` exercises the portable element parser and viewBox handling, and `Font glyphs` converts Flutter's `IconData` references into geometry through caller-owned font bytes. The swap action, progress scrubber, spring playback, and reverse-to-start action work across all three input families. Reverse-to-start swaps the endpoint definitions first, then plays the new transition forward so the displayed path remains canonical and stable.
