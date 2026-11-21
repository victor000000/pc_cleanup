# Changelog

## 0.0.4 — Directory scan boundary (2026-11-21)

- Check parent directories before enumerating an explicit scan root. A junction or cloud placeholder in the path produces a partial scan with a warning.
- Document the structured report version and completeness fields, Windows setup and CI outputs, and read-only checks after USB and VHD operations. [0.0.4 release notes](docs/RELEASE-0.0.4.md)

## 0.0.3 — Published source (2026-11-07)

- Bound legacy large-file selection to Top rows per category while preserving threshold and tie behavior.

First explicit project version. Add `Get-CleanupReview.ps1` with object/JSON output,
explicit scan completeness, bounded candidate and warning samples, exact logical
byte totals, UTC timestamps, and review cautions for sensitive file categories.
Existing report and maintenance command behavior is preserved.

Documentation review on 2026-11-07 corrected tracked/ignored asset claims, documented the complete structured result contract, expanded architecture and recovery guidance, and superseded historical validation/publication status. Runtime behavior and version are unchanged by that documentation revision.
