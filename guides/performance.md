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
- Use `MeldPaintStyle.original` for filled glyphs instead of inflating them into
  stroke paths.

Plan and sample caches are separate bounded LRU caches. Clearing a controller
does not allow a process-wide cache to grow without limit.

## Regression policy

The default target is a desktop plan P95 below 2 ms for typical icon pairs. If
the benchmark exceeds the target, inspect sample count, residual, and subpath
count in diagnostics before changing quality settings. Record visual or
performance changes in `GOALS.md` with a fixture and acceptance criterion.
