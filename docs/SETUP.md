# Release and auto-update setup

The pipeline (scripts + appcast + Sparkle wiring) is already in the repo. Three
steps are still missing, all depending on your own decisions or credentials, to
turn on auto-update end to end. Without them the app runs at 100%; only
auto-update stays inactive (the "Check for Updates" menu falls back to opening
the releases page).

## Build from source

```bash
swift build                            # build the SPM package
swift test --scratch-path .build-cli   # run the test suite (separate scratch path avoids a SourceKit lock)
./Scripts/make-app.sh debug            # assemble dist/ScratchMate.app from the debug binary
open dist/ScratchMate.app
```

`make-app.sh` produces the quick debug bundle. `build-app.sh` produces the
release build: a universal binary (arm64 + x86_64), a signed `.app` with the
full Info.plist (Sparkle + URL scheme) and the embedded Sparkle framework when
present.

## 1. GitHub repository

The scripts assume `github.com/leonardocandiani/scratchmate`. Create the repo and
adjust the URL in `Scripts/build-app.sh` (FEED_URL), `appcast.xml`,
`Scripts/update-appcast.sh` and `Sources/ScratchMate/Updater.swift` if you use a
different name.

```bash
gh repo create leonardocandiani/scratchmate --public --source=. --remote=origin
```

## 2. Wire up Sparkle (real auto-update)

Add the dependency to `Package.swift` (the code in `Updater.swift` activates on
its own through `#if canImport(Sparkle)`):

```swift
// in the Package:
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
],
// in the ScratchMate target, under dependencies:
.product(name: "Sparkle", package: "Sparkle"),
```

Generate the EdDSA key pair (`generate_keys` ships with the Sparkle that SPM
downloads):

```bash
swift build   # downloads Sparkle
BIN=$(find .build -name generate_keys -type f | head -1)
"$BIN"                                 # stores the PRIVATE key in the Keychain
"$BIN" -p > Branding/ed_public.key     # PUBLIC key (goes into Info.plist via build-app.sh)
```

`build-app.sh` reads `Branding/ed_public.key` and injects it as `SUPublicEDKey`.
The private key never leaves the Keychain; `sign_update` uses it inside
`release.sh`.

## 3. Code signing (optional, recommended for distribution)

- Ad-hoc (default): works locally, but Gatekeeper warns on other machines.
- Developer ID: export `SCRATCHMATE_CODESIGN_IDENTITY="Developer ID Application: ..."`
  before running `build-app.sh`, and notarize the DMG with `xcrun notarytool` +
  `stapler`.

## Cutting a release

```bash
Scripts/release.sh 0.2.0            # bump + universal build + DMG + sign + appcast (local)
Scripts/release.sh 0.2.0 --publish  # the above + commit + tag vX.Y.Z + GitHub release
```

Sparkle compares `CFBundleVersion` (a `YYYYMMDD.HHMM` stamp) to decide on an
update; the user sees `CFBundleShortVersionString` (the semver from the `VERSION`
file).
