# Changelog

All notable changes to ScratchMate are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-21

### Added

- Ephemeral note deck (Antinote style): a floating window that opens on a global
  hotkey, hides on blur and saves itself. Swipe sideways (or `Cmd+[` / `Cmd+]`)
  to move through notes; swiping past the newest creates a fresh one.
- Command palette (`::` or `Cmd+K`) for running native text commands inline.
- Native text commands: insert ISO 8601 date, generate UUID, format JSON, sort
  lines, dedupe, toggle case, comment lines, wrap selection in inline code, copy
  as a markdown code block, export as markdown.
- Live preview (`Cmd+R`) of markdown, JSON and code by language, with automatic
  language detection from the note's content.
- Find across all notes (`Cmd+F`) that filters every note as you type.
- Eight themes with adjustable translucency, plus a Liquid Glass material with a
  graceful fallback below macOS 26. Optionally follows the system Light/Dark
  appearance with a separate light and dark theme.
- Light first-launch onboarding and a "What's New" window after updates.
- Native Settings window (eight sections) with menu-bar / Dock presence modes,
  copy-on-select, a toggleable note counter, font family/size, and more.
- Global hotkey via Carbon, so no Accessibility permission is required.
- Sparkle auto-update (EdDSA-signed appcast).
- Local first storage: notes live in a local SQLite database with optional auto
  expiration. No account, no telemetry, no cloud.

[Unreleased]: https://github.com/leonardocandiani/scratchmate/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/leonardocandiani/scratchmate/releases/tag/v0.1.0
