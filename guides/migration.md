# Migration notes

Meld is a Flutter-native API with a pure Dart core. Migrate in layers:

1. Convert endpoint strings to `PathDataSource`.
2. Use `MeldEngine.plan` in asset tooling when a pair is reused often.
3. Replace frame callbacks with `MeldIcon` and a controller.
4. Add a semantic `label` or explicitly exclude decorative icons.
5. For font icons, pass static licensed bytes to
   `Meld.sourceFromIconData`; a code point alone is not geometry.

The core output is deterministic, but it is not a drop-in replacement for a
DOM renderer. Bake transforms and unsupported SVG effects before migration.
Keep the original endpoint fixture and compare the canonical path plus the
four progress snapshots during rollout.
