# Security Policy

## Supported versions

ScratchMate is a single-track desktop app: only the latest release receives
security fixes. Please update to the newest version before reporting an issue.

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please do not open a public issue for security problems.

Report vulnerabilities privately by email to llima.leo.lima@gmail.com. Include:

- A description of the issue and its impact.
- Steps to reproduce, or a proof of concept.
- The ScratchMate version and your macOS version.

You can expect an initial acknowledgment within a few days. Once the issue is
confirmed, a fix will be prepared and released, and the report will be credited
in the release notes unless you ask to stay anonymous. Please give us a
reasonable window to ship a fix before any public disclosure.

ScratchMate stores all notes locally in SQLite and has no account, no telemetry
and no cloud sync, so the attack surface is the local app and its update channel
(Sparkle, EdDSA-signed appcast).
