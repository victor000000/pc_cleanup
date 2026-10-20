# Contributing and validation

Use Windows PowerShell 5.1 and PowerShell 7 in fresh, noninteractive processes. Production WMI maintenance is 5.1-only even though its mocked logic is unit-tested in both lanes.

## Setup

```bash
powershell -NoProfile -NonInteractive -File ./tools/Install-DevDependencies.ps1
```

The dependency lock specifies exact versions, official download endpoints, and Base64 SHA-512 hashes of package bytes. Updating a dependency requires reviewing its source/version/hash and testing both engines. Never change the pin merely to get a different preinstalled version to pass. Do not commit `.tools`.

## Validate

```bash
powershell -NoProfile -NonInteractive -File ./Test.ps1 -Coverage
```

```bash
pwsh -NoProfile -NonInteractive -File ./Test.ps1 -Coverage
```

Use `-OutputPath` to place results elsewhere. Run once from an unrelated working directory as well, using the absolute path to `Test.ps1`.

All configured lint diagnostics and all failed/discovery/empty/skipped/unrun test conditions fail the gate. `-SkipLint` is a local debugging option, not a CI acceptance path. The lint ruleset deliberately targets correctness/security/compatibility rather than imposing every style recommendation. A new suppression must be narrow, explained, and reviewed.

## Add tests safely

- Reproduce the defect in a fixture or a mocked boundary first.
- Preserve all existing safety cases when reorganizing paths.
- Give each external command a throwing test stub before mocking it; missing Windows optional features must not make tests call real operations.
- Use Pester TestDrive for files and remove junctions explicitly without traversing their targets.
- Disable TestRegistry; mock application registry adapters.
- Test both success and failure cleanup, confirmation races, native errors, and `-WhatIf` without mutation.
- Tests for native status propagation may launch fixed, harmless `cmd.exe` exit/echo fixtures through a mocked executable resolver; never substitute real maintenance tools.
- Do not run operational entrypoints as import smoke tests. Inspect metadata/AST or invoke them with disposable targets and mocked boundaries.

Coverage-enabled runs enforce the **90% command-coverage minimum** in `tools/Quality.psd1`, established after both engines measured above 92%. CI always uses `-Coverage`. A missing safety assertion is more important than a numerical target; do not relax the threshold or remove instrumented helpers to conceal regressions.

## Repository hygiene

Historical scripts/results are preserved locally under `archive`; vendor assets under `.local`; outputs under `artifacts`. None belong in a public commit. Root operational paths changed intentionally; use the migration map. Do not stage local credentials, hardware-specific history, installers, vendor binaries, or test outputs.

Git initialization is local only. Committing, creating a remote, publishing, and pushing are separate actions requiring explicit authorization. Hosted CI results must be observed on GitHub before claiming a hosted run passed.
