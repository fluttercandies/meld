# Meld performance

Performance is part of the API contract. Planning is separated from painting
so expensive work is cacheable and measurable.

## Measurement

```bash
melos bootstrap
melos run benchmark
```

The benchmark executes repeated plans for a representative line-icon pair and
reports timing and cache hit/miss counts. Keep the machine, Dart SDK, and build
mode fixed when comparing results.

## Runtime practices

- Share one `MeldEngine` for repeated icon pairs.
- Call `prewarm` before the first interactive frame when pairs are known.
- Use adaptive sampling for general UI and raise `maxPointCount` only for
  detailed artwork.
- Keep `MeldDiagnosticsOverlay` out of release layouts.
- Use `MeldPaintStyle.original` to retain a filled glyph's source intent instead
  of inflating it into stroke paths.
- `MeldIcon` controllers share one frame ticker per Flutter isolate and the
  painter reuses its `Path` and `Paint` instances. Avoid rebuilding large
  ancestor subtrees from a per-frame listener when targeting 120 Hz displays.

Plan and sample caches are separate bounded LRU caches with both entry and
approximate byte limits. `MeldCacheStats.bytes` exposes the retained budget so
production diagnostics can detect pressure before it becomes a GC problem.

## Regression policy

The default target is a desktop plan P95 below 2 ms for typical icon pairs. If
the benchmark exceeds the target, inspect sample count, residual, and subpath
count in diagnostics before changing quality settings. Record visual or
performance changes in `GOALS.md` with a fixture and acceptance criterion.
