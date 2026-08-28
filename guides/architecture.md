# Meld architecture

Meld is split into packages with one-way dependencies:

```text
meld (facade)
├── meld_flutter ── meld_core
└── meld_font ──── meld_core
```

`meld_core` owns geometry decisions. Sources are normalized to cubic paths,
transformed into a common viewBox, sampled by arc length, and matched by
subpath cost. A `MeldPlan` stores immutable flight buffers, similarity
transforms, residuals, closure state, and optional global rigid blocks.

The Flutter layer never reparses geometry during paint. `MeldIconController`
owns the plan, preallocated output buffers, and spring state. `MeldIconPainter`
listens to the controller, so a frame repaints the icon without rebuilding the
surrounding widget subtree.

## Invariants

- `interpolatePlan(plan, 0)` reproduces each source buffer within tolerance.
- `interpolatePlan(plan, 1)` reproduces the oriented target buffer.
- Public numeric buffers are finite and copied at API boundaries.
- Cache size is bounded by its configured capacity.
- Invalid source data raises `MeldException` with a stable code and, for path
  syntax, an offset.

## Data flow

1. Parse source text or structured nodes.
2. Lower lines, curves, arcs, and primitives to cubic segments.
3. Apply explicit `viewBox` fitting when supplied.
4. Allocate equal arc-length samples and preserve corners.
5. Match subpaths, test winding/cyclic cuts, and solve Procrustes similarity.
6. Interpolate in polar, linear, or tangent-aware mode.
7. Advance the deterministic spring and repaint reusable output buffers.

The font adapter follows the same source contract. It reads caller-owned static
TrueType bytes, resolves `cmap`, expands `glyf` composites, converts quadratic
contours to cubic paths, and marks the result as a filled source. Geometry-only
sources declare their paint intent explicitly; SVG markup derives it from
inline `fill`, `stroke`, and basic `style` declarations. Unsupported outline
semantics fail with a diagnostic instead of silently producing a different
shape.
