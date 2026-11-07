# Architecture

[README](../README.md) · [Commands](COMMANDS.md) · [Contributing](../CONTRIBUTING.md) · [Safety](SAFETY.md)

## Boundaries

- `src/DirectoryScan.ps1`: metadata traversal and report assembly; skips reparse/recall/offline entries and reports partial reads visibly.
- `src/UsbEject.ps1`: stable disk identity validation, PnP mapping, and a single checked native eject request. Native calls are behind replaceable PowerShell adapters.
- `src/DiskRecovery.ps1`: identity-based online and drive-letter recovery, including confirmation-time revalidation and collision refusal.
- `src/VhdMaintenance.ps1`: VHD preflight/owned attachment lifecycle, checked native commands, pagefile changes/rollback, and maintenance logging.
- `scripts/`: user entrypoints. They resolve imports from their own location, not the caller's current directory.
- `scripts/compat/`: thin aliases for old eject names. These are not alternative fallback strategies.
- `tools/ProjectTools.ps1`: exact dependency resolution, owned-source inventory, lint, test configuration, result gating, and optional coverage.
- Root `configure-defender-startup.ps1` and `verify-defender-startup.ps1`: separate local task configuration/inspection scripts. No toolkit entrypoint imports them. Their actual task behavior is outside the mocked test coverage; see the [Defender startup guide](DEFENDER-STARTUP.md).

The project intentionally uses small dot-sourced libraries rather than introducing a packaging/module layer merely for reorganization. Definitions do not run maintenance when a library is imported.

## State-changing operations

Guarded storage/maintenance entrypoints and the Handle diagnostic use `SupportsShouldProcess` and high-impact confirmation. Their `-WhatIf` paths perform no mutation; some return before full preflight. Reports do not need confirmation; LAN probes run immediately when explicitly invoked. The local Defender scripts do not implement this confirmation contract.

Maintenance and Handle logs are acquired atomically as new files and retained as owned streams until `finally` closes them; no failure path reopens a rejected caller-controlled path. Approval of a compound operation is explicit, but it does not make independent steps transactional. Helpers preserve their narrower guarantees: identity revalidation, owned attachment cleanup, and best-effort pagefile rollback.

`finally` is failure-path cleanup, not protection against process termination, power loss, concurrent device replacement, or driver bugs. Native commands and actual driver behavior require separately approved manual validation.

## Tests

Tests retain the previous safety cases and add layout, command, runner, and dependency contracts. External OS/native boundaries are replaced with throwing stubs and mocks. Filesystem integration uses small disposable local fixtures; external sentinels verify junction cleanup does not delete linked targets.

The syntax inventory includes all root `.ps1`/`.psd1` files and recursively includes `.ps1`/`.psm1`/`.psd1` files under `src`, `scripts`, `tools`, and `tests`. It excludes `.tools`, `.local`, `archive`, and `artifacts`; dependency XML is not PowerShell source. Root files are discovered from the working tree, including untracked additions, rather than from a fixed filename allowlist. Production lint uses the same inventory without `tests`.

Pester and PSScriptAnalyzer versions, download URLs, and package SHA-512 hashes are pinned in [Dependencies.psd1](../tools/Dependencies.psd1). Dependencies install only inside `.tools`; test execution does not contact the network. TestRegistry is disabled, and failure/skip/empty-run conditions fail validation.

## Quality gates

- Parsing runs with each CI lane's parser: Windows PowerShell 5.1 and PowerShell 7.
- PSScriptAnalyzer uses the explicit rules in the root settings file. These cover unsafe dynamic evaluation, credentials, weak hashes, empty catches, overwritten built-ins, encoding, and compatible syntax. All diagnostics from those configured rules fail the gate. This is not an assertion that every optional style rule is enabled.
- The full unit/contract suite is mandatory. Diagnostic `-SkipLint` is never used by CI.
- Coverage instruments reusable `src` source only. [Quality.psd1](../tools/Quality.psd1) sets the command-coverage minimum, currently **90%**, for coverage-enabled runs. CI always enables coverage. Missing/empty/invalid coverage fails closed. Native C# and real hardware are not validated by a percentage; do not lower the threshold to hide a missing safety case.

Generated artifacts are per-engine NUnit XML, lint JSON, environment metadata, and optional JaCoCo coverage. They are local/CI outputs, not checked-in evidence of a current successful run.

## Large-file report selection

`Get-DirectoryLargeFileReport` consumes one metadata traversal and retains at most `Top` rows in each of its image and ordinary-file categories. Binary insertion orders retained rows by exact Int64 byte length; equal sizes retain encounter order. Each category temporarily holds at most `Top + 1` rows during insertion. Candidate storage is therefore proportional to `Top`, with at most `Top` shifts per accepted row. The scanner still keeps its directory traversal stack, and the report still visits all readable entries.

Images qualify regardless of size; ordinary files must be strictly larger than `MinimumFileBytes`. Unreadable entries and skipped links retain the existing partial-scan warning behavior. Selection does not estimate reclaimable space or authorize maintenance. Tests cover category separation, cutoff ties, empty results, exact large integer ordering, a single traversal, and partial-scan retention.
