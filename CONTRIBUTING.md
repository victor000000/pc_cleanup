# Contributing and validation

[README](README.md) · [Commands](docs/COMMANDS.md) · [Architecture](docs/ARCHITECTURE.md) · [Safety](docs/SAFETY.md)

## Set up

Start in the checkout root on Windows, with write access to `.tools`, the validation output directory, and your temporary directory. The temporary directory must support the suite's disposable junctions and hard links, as on local NTFS. Tests run as an ordinary user. Choose a checkout path free of brackets, wildcard characters, and backticks for the pinned module loader and coverage tools. Report inputs may contain literal brackets.

Both `powershell.exe` (Windows PowerShell 5.1) and `pwsh.exe` (PowerShell 7) must be available for release validation. The first setup downloads Pester 5.5.0 and PSScriptAnalyzer 1.24.0 over HTTPS from PowerShell Gallery. Both engines use the same repository-local installation. Check command availability and run setup from a Windows PowerShell session.

```powershell
Get-Command -Name powershell.exe,pwsh.exe -CommandType Application -ErrorAction Stop
powershell.exe -NoProfile -NonInteractive -File .\tools\Install-DevDependencies.ps1
if ($LASTEXITCODE -ne 0) { throw 'Development dependency setup failed.' }
```

[Dependencies.psd1](tools/Dependencies.psd1) is the source of truth for exact versions, official package URLs, and Base64 SHA-512 hashes. Setup verifies downloaded bytes before extraction and installs only under `.tools`; it does not install modules globally. Testing never bootstraps dependencies. Updating a pin requires reviewing the version, source, and hash and validating both engines.

## Validate

```powershell
powershell.exe -NoProfile -NonInteractive -File .\Test.ps1 -Coverage
if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell 5.1 validation failed.' }
pwsh.exe -NoProfile -NonInteractive -File .\Test.ps1 -Coverage
if ($LASTEXITCODE -ne 0) { throw 'PowerShell 7 validation failed.' }
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
$runner = (Get-Item -LiteralPath .\Test.ps1).FullName
Push-Location -LiteralPath ([IO.Path]::GetTempPath())
try {
    powershell.exe -NoProfile -NonInteractive -File $runner -Coverage
    if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell 5.1 validation failed.' }
    pwsh.exe -NoProfile -NonInteractive -File $runner -Coverage
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell 7 validation failed.' }
} finally { Pop-Location }
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

Follow `.editorconfig` and `.gitattributes`: Markdown uses UTF-8/LF; PowerShell uses UTF-8 with BOM/CRLF. Keep local history in `archive`, vendor files and runtime logs in `.local`, dependencies in `.tools`, and test results in `artifacts`. Those directories are ignored. The root Defender JSON outputs and installer downloads are also ignored; inspect `git status` and stage deliberately. Do not publish credentials, hardware-specific history, installers, vendor binaries, or local result files.

The Windows workflow runs on pushes, pull requests, and manual dispatches. Each `windows-2022` job installs the pinned dependencies and runs `Test.ps1 -Coverage`. The `powershell` job writes to `artifacts/powershell` and the `pwsh` job to `artifacts/pwsh`. Actions attempts to upload each directory even after failure, with artifact names `validation-powershell` and `validation-pwsh` and a 14-day retention period. An early setup error can leave only the job log. Local defaults are `artifacts/ps-5` and `artifacts/ps-7`. [Workflow](.github/workflows/ci.yml)

## Release a source version

1. Use one Git checkout and one publisher with write access to the project repository. Start from the intended upstream revision. Update the version in `Project.psd1`, the `ToolVersion` expectation in the structured report tests, the README version and release link, the changelog, and the versioned release notes. `SchemaVersion` describes the report format and has its own compatibility contract. [Manifest](Project.psd1) · [Report tests](tests/DirectoryReview.Tests.ps1) · [Changelog](CHANGELOG.md)
2. Run the two Windows coverage commands above in fresh processes. Check local Markdown links and heading anchors, parse examples in both engines, and run read-only report examples against the checkout or a disposable fixture. Use an absolute script path for a run from a different working directory.
3. Inspect the working tree, staged files, and committed changes against the intended upstream base. Include the reviewed source, tests, and guides. Keep credentials, deployment data, machine-specific reports, and local validation receipts outside the published files.
4. Push the reviewed source through the project's existing GitHub workflow. In Actions, match the final commit SHA to the published branch and confirm that `Validate (powershell)` and `Validate (pwsh)` both succeeded. If the upstream branch moved or a merge produced a new commit, check the run for the resulting SHA. The workflow distributes validation artifacts. The source checkout is the deliverable.

For a committed candidate based on `origin/main`, these read-only Git commands show pending files, the committed change set, whitespace errors, and the candidate SHA. Refresh the upstream reference before comparing it.

```powershell
git status --short --branch
git diff --cached --name-status
git diff --name-status origin/main...HEAD
git diff --check origin/main...HEAD
git rev-parse HEAD
```

If a published regression needs to be withdrawn, the release owner can revert the affected change in a new reviewed commit and run both jobs again. To use a previous version locally, open its known-good commit in a fresh checkout. For a machine already changed by a maintenance command, inspect its current device, image, or pagefile state separately. [Operational recovery](docs/TROUBLESHOOTING.md#maintenance)

## Local environment and deployment scope

When launched from WSL, PowerShell can inherit a `PATHEXT` value that omits
`.EXE`. `Test.ps1` temporarily adds `.EXE` for its validation process so the
harmless native exit/echo fixtures execute, then restores the caller's value.
It does not change user or machine environment settings or maintenance scripts.

CI validates source, lint, unit tests, and coverage in both Windows engines.
The only network setup is downloading the pinned, SHA-512-verified test modules;
the test suite does not download data, contact live services, or run maintenance.
Hardware, administrator-only maintenance, and live service integration are mocked
and are not certified by a passing CI run.

No deployment target, release publication, or CD workflow is configured. The
repository distributes source; CI does not deploy it or alter any user's PC.

## Documentation acceptance

Inventory root Markdown, `docs/*.md`, and `docs/reference/*.txt`. Compare the guides with entrypoint parameter blocks, shared helpers, `.gitignore`, manifests, and CI in the release checkout. Record user-visible changes in the release notes. Keep local checkout details, private verification receipts, and authentication history with the publisher.

Check every relative Markdown link and heading anchor. Parse fenced PowerShell examples in both engines and compare script parameters with the target entrypoint. Check bootstrap pins, engine requirements, output paths, and coverage policy against the source and workflow. Offline checks cover local targets. Run read-only report examples on the checkout or a disposable fixture to verify their text, objects, and JSON. Use syntax checks or mocked commands for examples that touch devices, services, scheduled tasks, or the network.

Run these offline documentation checks alongside the source gate. Keep the detailed results locally. Use the workflow run on the final published SHA when reporting hosted status. [Earlier documentation changes](docs/DOCUMENTATION-AUDIT-2026-11-07.md)
