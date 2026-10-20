# Architecture

## Boundaries

- `src/DirectoryScan.ps1`: metadata traversal and report assembly; skips reparse/recall/offline entries and reports partial reads visibly.
- `src/UsbEject.ps1`: stable disk identity validation, PnP mapping, and a single checked native eject request. Native calls are behind replaceable PowerShell adapters.
- `src/DiskRecovery.ps1`: identity-based online and drive-letter recovery, including confirmation-time revalidation and collision refusal.
- `src/VhdMaintenance.ps1`: VHD preflight/owned attachment lifecycle, checked native commands, pagefile changes/rollback, and maintenance logging.
- `scripts/`: user entrypoints. They resolve imports from their own location, not the caller's current directory.
- `scripts/compat/`: thin aliases for old eject names. These are not alternative fallback strategies.
- `tools/ProjectTools.ps1`: exact dependency resolution, owned-source inventory, lint, test configuration, result gating, and optional coverage.

The project intentionally uses small dot-sourced libraries rather than introducing a packaging/module layer merely for reorganization. Definitions do not run maintenance when a library is imported.

## State-changing operations

User entrypoints use `SupportsShouldProcess` and high-impact confirmation. Logs are acquired atomically as new files and retained as owned streams until `finally` closes them; no failure path reopens a rejected caller-controlled path. Approval of a compound operation is explicit, but it does not make independent steps transactional. Helpers preserve their narrower guarantees: identity revalidation, owned attachment cleanup, and best-effort pagefile rollback.

`finally` is failure-path cleanup, not protection against process termination, power loss, concurrent device replacement, or driver bugs. Native commands and actual driver behavior require separately approved manual validation.

## Tests

Tests retain the previous safety cases and add layout, command, runner, and dependency contracts. External OS/native boundaries are replaced with throwing stubs and mocks. Filesystem integration uses small disposable local fixtures; external sentinels verify junction cleanup does not delete linked targets.

The syntax inventory is an allowlist of owned root PowerShell files plus `src`, `scripts`, `tools`, and `tests`, using exact extensions. It excludes `.tools`, `.local`, `archive`, and `artifacts`; dependency XML is not PowerShell source.

Pester 5.5.0 and PSScriptAnalyzer 1.24.0 are pinned with package SHA-512 hashes. Dependencies install only inside `.tools`; test execution does not contact the network. TestRegistry is disabled, and failure/skip/empty-run conditions fail validation.

## Quality gates

- Parsing runs with each CI lane's parser: Windows PowerShell 5.1 and PowerShell 7.
- PSScriptAnalyzer uses the explicit rules in the root settings file. These cover unsafe dynamic evaluation, credentials, weak hashes, empty catches, overwritten built-ins, encoding, and compatible syntax. All diagnostics from those configured rules fail the gate. This is not an assertion that every optional style rule is enabled.
- The full unit/contract suite is mandatory. Diagnostic `-SkipLint` is never used by CI.
- Coverage instruments reusable source only. The measured reconstruction baseline exceeded 92% command coverage in both engines; `tools/Quality.psd1` now sets an enforced **90%** minimum for coverage-enabled runs. CI always enables coverage. Missing/empty/invalid coverage fails closed. Native C# and real hardware are not validated by a percentage; do not lower the threshold to hide a missing safety case.

Generated artifacts are per-engine NUnit XML, lint JSON, environment metadata, and optional JaCoCo coverage. They are local/CI outputs, not checked-in evidence of a current successful run.
