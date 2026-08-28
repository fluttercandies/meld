# Meld Showcase Cockpit shell

This development-only package wraps the real Showcase root with Cockpit. It is
kept outside the production app and is the entrypoint for live UI inspection,
screenshots, interaction journeys, and integration evidence.

```bash
cd cockpit
flutter pub get
cockpit dev start
```

The same shell owns the source-aware integration journey:

```bash
flutter test integration_test/showcase_flow_test.dart -d macos
```

The journey drives the real Showcase through Cockpit selectors, then captures
an acceptance screenshot after changing the pair, progress, spring, and quality.
