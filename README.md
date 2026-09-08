<!-- readme-padrao:header -->
<!-- Banner -->
<div align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:1a1a2e,100:00d9ff&height=200&section=header&text=ScratchMate&fontSize=54&fontColor=ffffff&animation=fadeIn&fontAlignY=36&desc=A%20programmable%2C%20ephemeral%20scratchpad%20for%20macOS&descAlignY=58&descSize=16" alt="ScratchMate" width="100%" />
</div>

<!-- Typing -->
<div align="center">
  <img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&weight=600&size=21&duration=2800&pause=900&color=00d9ff&center=true&vCenter=true&width=840&lines=A+programmable%2C+ephemeral+scratchpad+for+macOS;Global+hotkey%2C+throwaway+buffers%2C+%3A%3A+text+commands;Live+format+preview%2C+everything+local+in+SQLite;Liquid+Glass%2C+native+Swift%2C+no+account" alt="A programmable, ephemeral scratchpad for macOS" />
</div>

<div align="center">

  <br>
  <img src="Branding/screenshots/editor.png" alt="ScratchMate editor with the command reference and footer" width="720" />

  <br>
  <img src="Branding/screenshots/settings.png" alt="ScratchMate settings, General tab" width="560" />
  <br><br>

  <p>The mental lightness of <a href="https://antinote.io">Antinote</a> with the workbench soul of <a href="https://macromates.com/">TextMate</a>: throwaway notes, navigable by swipe, with <code>::</code> commands and live format preview.</p>

  <p>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-00d9ff?style=for-the-badge" alt="License: MIT" /></a>
    <img src="https://img.shields.io/badge/macOS-14%2B-1a1a2e?style=for-the-badge&logo=apple&logoColor=white" alt="macOS: 14+" />
    <a href="https://github.com/leonardocandiani/scratchmate/releases"><img src="https://img.shields.io/github/v/release/leonardocandiani/scratchmate?display_name=tag&style=for-the-badge&color=00d9ff&labelColor=1a1a2e" alt="Release" /></a>
    <a href="https://github.com/leonardocandiani/scratchmate/actions/workflows/build-check.yml"><img src="https://img.shields.io/github/actions/workflow/status/leonardocandiani/scratchmate/build-check.yml?style=for-the-badge&labelColor=1a1a2e&label=CI" alt="CI" /></a>
    <a href="https://github.com/leonardocandiani/scratchmate/pulls"><img src="https://img.shields.io/badge/PRs-welcome-1a1a2e?style=for-the-badge" alt="PRs: welcome" /></a>
  </p>

  <p>
    <a href="#features">Features</a> •
    <a href="#install">Install</a> •
    <a href="#shortcuts">Shortcuts</a> •
    <a href="#build-from-source">Build from source</a> •
    <a href="#acknowledgments">Acknowledgments</a> •
    <a href="#project">Project</a> •
    <a href="#license">License</a>
  </p>
</div>

<br>

> **ScratchMate** opens instantly from a global hotkey and hands you a buffer that understands code. Write, transform with `::` commands, swipe to the next note, throw it away. Nothing you type leaves your Mac.

## What it is

```yaml
product:  ephemeral scratchpad for developers, native to macOS
platform: macOS 14+, Swift + AppKit, Liquid Glass on macOS 26
open:     global hotkey, menu bar app, no Dock icon
commands: :: text commands (format, transform, preview) inside the buffer
storage:  local SQLite only, no account, no cloud, no sync
install:  Homebrew cask or signed DMG from Releases
license:  MIT
```

<!-- /readme-padrao:header -->

ScratchMate opens instantly from a global hotkey and hands you a throwaway buffer
that understands code. It lives in the menu bar, has no account and no cloud, and
nothing you write leaves your Mac. Everything is local in SQLite. The capture is
native Swift on AppKit, the glass is the system material, and the whole thing is
designed to disappear the moment you stop typing.

## Features

- **Ephemeral note deck (Antinote style).** A floating window that opens on a hotkey, hides on blur, and saves itself. Swipe two fingers sideways (or `Cmd+[` / `Cmd+]`) to move through notes; swiping past the newest creates a fresh one.
- **Command palette (`::` or `Cmd+K`)** with native text commands: insert date, UUID, format JSON, sort lines, dedupe, case transform, comment lines, wrap selection, copy as code block, export markdown.
- **Find across all notes (`Cmd+F`)** with a search bar that filters every note as you type.
- **Live preview (`Cmd+R`)** of markdown, JSON and code by language.
- **Native look.** Liquid Glass material (with a graceful fallback below macOS 26), eight themes, adjustable translucency, hover reveal chrome, and full respect for Reduce Transparency, Reduce Motion and Increase Contrast.
- **Local first.** Notes live in SQLite with optional auto expiration. No account, no telemetry, no cloud.
- **Global hotkey** via Carbon, so it needs no Accessibility permission.

## Install

### Homebrew (cask)

```bash
brew install --cask leonardocandiani/tap/scratchmate
```

### Download

Grab the latest `.dmg` from [Releases](https://github.com/leonardocandiani/scratchmate/releases), open it, and drag ScratchMate to Applications.

ScratchMate is ad-hoc signed (not notarized yet). If macOS blocks the first launch:

```bash
xattr -rd com.apple.quarantine /Applications/ScratchMate.app
```

## Shortcuts

| Shortcut | Action |
|---|---|
| <kbd>Cmd</kbd><kbd>Shift</kbd><kbd>Space</kbd> | Toggle the window |
| <kbd>Cmd</kbd><kbd>K</kbd> | Command palette |
| <kbd>Cmd</kbd><kbd>F</kbd> | Find across notes |
| <kbd>Cmd</kbd><kbd>R</kbd> | Toggle preview |
| <kbd>Cmd</kbd><kbd>[</kbd> | Older note |
| <kbd>Cmd</kbd><kbd>]</kbd> | Newer note |
| <kbd>Cmd</kbd><kbd>N</kbd> | New note |
| <kbd>Cmd</kbd><kbd>P</kbd> | Pin to screen |
| <kbd>Cmd</kbd><kbd>,</kbd> | Settings |

You can also type `::` anywhere to open the command palette inline.

## Build from source

```bash
swift build
swift test --scratch-path .build-cli   # 49 tests
./Scripts/make-app.sh debug
open dist/ScratchMate.app
```

ScratchMate references macOS 26 symbols (`NSGlassEffectView`) for Liquid Glass,
guarded at runtime with `if #available(macOS 26, *)` and falling back to
`NSVisualEffectView`. Building requires the macOS 26 SDK (Xcode 26); the minimum
deployment target stays at macOS 14.

## Acknowledgments

- [Antinote](https://antinote.io) for the ephemeral, hotkey-first scratchpad model.
- [TextMate](https://macromates.com/) for treating text as a programmable surface.
- [Krit](https://github.com/leonardocandiani/krit) for the native macOS OSS scaffolding.

## Project

- [Contributing](CONTRIBUTING.md) for how to set up, build and send changes.
- [Code of Conduct](CODE_OF_CONDUCT.md) for community expectations.
- [Security policy](SECURITY.md) for reporting vulnerabilities.
- [Changelog](CHANGELOG.md) for release notes.
- [Third party notices](THIRD_PARTY_NOTICES.md) for bundled dependencies.

## License

MIT. See [LICENSE](LICENSE).

<!-- readme-padrao:footer -->
<br>

---

<div align="center">
  <p><strong>Built by <a href="https://github.com/leonardocandiani">Leonardo Candiani</a></strong> · More projects at <a href="https://github.com/leonardocandiani?tab=repositories">github.com/leonardocandiani</a></p>
  <p>Leonardo Candiani builds AI agents that talk, decide and close deals. Cofounder of SixQuasar, operating Proteauto, SegSmart and IACall end to end.</p>
  <a href="https://leonardocandiani.com.br">
    <img src="https://img.shields.io/badge/-Website-0d1117?style=for-the-badge&logo=safari&logoColor=00d9ff" alt="Website" />
  </a>
  <a href="https://github.com/leonardocandiani">
    <img src="https://img.shields.io/badge/-GitHub-0d1117?style=for-the-badge&logo=github&logoColor=00d9ff" alt="GitHub" />
  </a>
  <a href="https://instagram.com/leonardocandiani">
    <img src="https://img.shields.io/badge/-Instagram-E4405F?style=for-the-badge&logo=instagram&logoColor=white" alt="Instagram" />
  </a>
  <a href="https://youtube.com/@oleonardocandiani">
    <img src="https://img.shields.io/badge/-YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="YouTube" />
  </a>
</div>

<br>

<div align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:00d9ff,50:1a1a2e,100:0d1117&height=120&section=footer&text=Thanks%20for%20stopping%20by&fontSize=18&fontColor=ffffff&fontAlignY=72" alt="Thanks for stopping by" width="100%" />
</div>
<!-- /readme-padrao:footer -->
