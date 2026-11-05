# Contributing and validation

[README](README.md) · [Commands](docs/COMMANDS.md) · [Architecture](docs/ARCHITECTURE.md) · [Safety](docs/SAFETY.md)

## Set up

Use fresh, noninteractive Windows PowerShell 5.1 and PowerShell 7 processes on Windows. Tests do not require elevation. Choose a checkout path without wildcard characters (square brackets, asterisk, question mark) or backticks: the pinned module loader, test discovery, and coverage backend reject these locations. Ordinary report input paths can contain brackets.

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tools\Install-DevDependencies.ps1
```

[Dependencies.psd1](tools/Dependencies.psd1) is the source of truth for exact versions, official package URLs, and Base64 SHA-512 hashes. Setup verifies downloaded bytes before extraction and installs only under `.tools`; it does not install modules globally. Testing never bootstraps dependencies. Updating a pin requires reviewing the version, source, and hash and validating both engines.

## Validate

```powershell
powershell.exe -NoProfile -NonInteractive -File .\Test.ps1 -Coverage
pwsh.exe -NoProfile -NonInteractive -File .\Test.ps1 -Coverage
```

`Test.ps1` accepts:

| Parameter | Behavior |
|---|---|
| `-Coverage` | Instrument `src/*.ps1` recursively and enforce the minimum in [Quality.psd1](tools/Quality.psd1), currently 90% command coverage |
| `-OutputPath` | Override the default `artifacts/ps-<engine-major>` directory; use an absolute path when running elsewhere |
| `-SkipLint` | Local diagnosis only; CI runs the full lint gate |

The gate parses owned PowerShell files, applies the configured correctness/security/compatibility lint rules, and runs all discovered tests. Lint diagnostics, discovery failures, empty runs, failed containers/tests, skipped tests, and unrun tests fail validation. Coverage-enabled runs also fail on missing, invalid, or insufficient coverage. Do not lower the threshold or remove helpers from coverage to hide a missing case.

After changing path resolution, also validate from an unrelated working directory:

```powershell
$projectRoot = 'C:\path\pc_cleanup'
Set-Location $env:TEMP
powershell.exe -NoProfile -NonInteractive -File (Join-Path $projectRoot 'Test.ps1') -Coverage
```

Each completed run can produce these files in its output directory:

| File | Contents |
|---|---|
| `environment.json` | Engine, Pester, and platform versions |
| `lint.json` | Diagnostics from the configured rules; `[]` means none |
| `tests.xml` | NUnit-format test results |
| `coverage.xml` | JaCoCo command coverage, only with `-Coverage` |

Inspect timestamps and the process exit code; a prior artifact is not evidence that the latest command passed. Early failures can leave incomplete output.

## Change code safely

- Reproduce a defect with a disposable fixture or mocked boundary, then preserve the existing safety cases.
- Give external commands throwing test stubs before mocking them, so missing Windows optional features cannot expose real operations.
- Use Pester TestDrive for files. Remove fixture junctions without traversing their targets. TestRegistry stays disabled; registry adapters are mocked.
- Check failure cleanup, confirmation-time changes, native errors, and `-WhatIf` without mutation.
- Native status fixtures may launch fixed, harmless `cmd.exe` exit/echo commands through a mocked resolver. Never substitute maintenance executables.
- Inspect entrypoint metadata/AST or use mocked boundaries; do not execute operational scripts as import smoke tests.

Production WMI pagefile maintenance is Windows PowerShell 5.1-only; its mocked logic runs in both test lanes. Command coverage does not validate native C#, hardware, drivers, or actual maintenance behavior. Any new lint suppression should be narrow and explained; the enabled rules are in [PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1).

## Maintain documentation

Keep task selection in the [README](README.md), parameter/default/effect details in [COMMANDS.md](docs/COMMANDS.md), recovery guidance in [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md), and shared invariants in [SAFETY.md](docs/SAFETY.md). Update the relevant guide when changing a parameter, default, output, supported engine, or side effect. The local Defender scripts have their own [guide](docs/DEFENDER-STARTUP.md) because their behavior differs from the guarded toolkit.

For documentation-only changes, check relative links, PowerShell example syntax, and parameters against source. Do not run maintenance, active network scans, task setup, or rollback commands to validate examples. Run the code gate when code/tooling changes or when checking the current project baseline; documentation checks are manual and are not part of `Test.ps1`.

## Repository hygiene and CI

Follow `.editorconfig` and `.gitattributes`: Markdown uses UTF-8/LF; PowerShell uses UTF-8 with BOM/CRLF. Keep local history in `archive`, vendor files and runtime logs in `.local`, dependencies in `.tools`, and test results in `artifacts`. Those directories are ignored. The root Defender JSON outputs currently are not ignored; inspect `git status` and stage deliberately. Do not publish credentials, hardware-specific history, installers, vendor binaries, or local result files.

[Windows CI](.github/workflows/ci.yml) uses `windows-2022`, both engines, pinned action revisions, read-only repository permissions, and `Test.ps1 -Coverage`. It uploads available artifacts after failures. Hosted CI must be observed on GitHub before claiming a hosted run passed; a workflow file or local passing run is insufficient. Publishing and pushing remain separate actions requiring authorization.
