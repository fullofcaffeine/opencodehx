# Changelog

OpenCodeHX uses semantic-release with `0.x` beta prereleases while the Haxe port works toward upstream OpenCode parity.

Release notes are generated here during release preparation.

Current beta packaging expectations include a local `npm pack` plus temporary global-install smoke for the generated `opencodehx` bin; keep that gate in sync with package metadata changes before the next generated release notes are prepared.

Current platform-parity expectations include the Windows shell smoke workflow for `cmd.exe`, PowerShell, Git Bash, PTY shell args, and `killTree` behavior; keep `npm run windows:shell:smoke`, `.github/workflows/ci.yml`, and release-contract checks synchronized when changing shell or process teardown behavior.
