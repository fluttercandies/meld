# Contributing to Meld

Thanks for helping improve Meld. Read `GOALS.md` first: it defines the scope, quality bar and acceptance criteria.

## Development flow

This project does not use TDD. Work from the documented goal and design, implement the complete behavior, then run focused verification followed by the full workspace checks.

```bash
melos bootstrap
melos run format
melos run analyze
melos run test
```

Keep packages focused, preserve the public contracts, add a regression test after fixing a defect, and record new optimization ideas in `GOALS.md` with an acceptance criterion.

## Pull requests

- Explain the user-visible outcome and affected packages.
- Include benchmark or golden evidence for rendering and performance changes.
- Keep public API changes documented in both README files and the changelog.
- Do not add unlicensed assets or fonts.
