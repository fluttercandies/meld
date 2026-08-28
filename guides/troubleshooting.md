# Troubleshooting

## `invalid-path`

The exception includes an `offset` into the original `d` string. Check the
command immediately before that offset, especially arc flags (`0` or `1`) and
scientific notation.

## Filled SVG or glyphs look hollow

Use `MeldPaintStyle.fill` or `fillAndStroke` for closed glyph geometry. The
default stroke mode is intentionally optimized for line icons.

## `unsupported-element` or `unsupported-transform`

Meld supports portable geometry rather than a full XML renderer. Bake
transforms into coordinates and convert filters, masks, symbols, and strokes
with external tooling before handing the result to Meld.

## `unsupported-font`

Only static TrueType `glyf` outlines are decoded. CFF, color, and variable
fonts are rejected explicitly. Supply a licensed static font file or convert
the glyph to a `CubicSource` during asset generation.

## A transition does not animate

`MeldIconController` needs a mounted `MeldIcon` (or another `TickerProvider`)
for a live spring. Without a ticker, command mode completes immediately and
updates the endpoint safely. Set `motionMode: MeldMotionMode.always` for a
demo, or leave `user` to follow reduced-motion settings.

## Jank or too many points

Share one engine, prewarm known pairs, and lower
`SamplingConfig.maxPointCount`. Use the diagnostics overlay to distinguish
planning cost from painting cost; changing stroke width does not change a
plan.
