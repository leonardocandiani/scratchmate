# Contributing to ScratchMate

Thanks for your interest. ScratchMate is a native macOS app written in Swift 6
with AppKit, built with Swift Package Manager (no Xcode project).

## Build and test

```bash
swift build                              # compile
swift test --scratch-path .build-cli     # run the ScratchMateCore suite (37 tests)
./Scripts/make-app.sh debug              # bundle dist/ScratchMate.app
open dist/ScratchMate.app
```

The separate `--scratch-path .build-cli` keeps the test build from fighting the
SourceKit/editor lock on `.build`.

ScratchMate references macOS 26 symbols (`NSGlassEffectView`) guarded at runtime
with `if #available(macOS 26, *)`, so building requires the macOS 26 SDK (Xcode 26).
The minimum deployment target stays at macOS 14.

## Project layout

- `Sources/ScratchMate` the AppKit app (panel, editor, palette, search, settings, design system).
- `Sources/ScratchMateCore` the pure model layer (notes, SQLite, commands, markdown), no AppKit, fully tested.
- `Scripts/` the release pipeline (universal build, DMG, appcast, Sparkle).

## Conventions

- **Swift 6 strict concurrency.** The app target uses `.defaultIsolation(MainActor.self)`. ObjC delegates use `nonisolated func ... { MainActor.assumeIsolated { ... } }`.
- **English only** for code, comments, UI copy and docs.
- **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, ...).
- No em dash or en dash in any text: use commas, parentheses, colons or periods.
- Run `swift build` and `swift test` green before opening a PR.

## Pull requests

Keep PRs focused. Describe what changed and how you verified it. CI runs the
universal build and the test suite on every PR.
