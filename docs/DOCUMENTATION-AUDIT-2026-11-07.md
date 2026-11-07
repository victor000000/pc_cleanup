# Documentation audit — 2026-11-07

[README](../README.md) · [Commands](COMMANDS.md) · [Architecture](ARCHITECTURE.md) · [Contributing](../CONTRIBUTING.md)

## Scope and disposition

The audit starts from published `20599078990a3d233df8e24658c4f852e4eb24bd`, tree `3a94f07647975bb4cf85987a46ec6f5d99d9ddd2`. Anonymous Git fetch confirmed this tree equals the previously tested integration candidate `97d724a`. Runtime source, dependency pins, and version 0.0.3 are unchanged by this documentation revision.

The original publication inventory contains **10 tracked Markdown files and two reference text templates**. All were reviewed. This audit adds one Markdown record, giving 11 Markdown documents. The separate native checkout contains **eight owned Markdown guides and the same two templates**; its preexisting uncommitted changes are preserved, with narrow documentation corrections applied afterward. Ignored archives, runtime output, dependencies, and third-party documentation are not canonical owned guides and are excluded from revision and automated link/example checks. Their contents are not claimed reviewed for correctness or publication.

| Owned document | Review and disposition |
|---|---|
| `README.md` | Correct tracked-script claims; document configuration/platform boundaries and navigation |
| `CONTRIBUTING.md` | Verify bootstrap/CI pins and quality gates; add repeatable documentation acceptance procedure |
| `CHANGELOG.md` | Record source publication and documentation-only changes without changing runtime version |
| `docs/ARCHITECTURE.md` | Add structured helper, data flow, bounded aggregation rationale, API and failure boundaries |
| `docs/COMMANDS.md` | Verify all entrypoints/defaults; distinguish formatted reports from JSON; document complete schema, precision and errors |
| `docs/SAFETY.md` | Correct ignored-output statement and precise logical-size wording; retain mutation safeguards |
| `docs/TROUBLESHOOTING.md` | Add current diagnosis above dated failure evidence; add JSON/WSL troubleshooting |
| `docs/MIGRATION.md` | Preserve dated layout history; document 0.0.3 consumer differences and tracked Defender additions |
| `docs/DEFENDER-STARTUP.md` | Correct clean-clone/output facts; qualify historical machine observations; verify setup/removal prose against source |
| `docs/RELEASE-0.0.3.md` | Preserve original design and checkpoint bytes; current status correction appears below |
| `docs/reference/compact_docker.txt`, `compact_ubuntu.txt` | Reviewed unchanged: deliberately invalid placeholders and explicit wrapper-only guidance; no current Docker installation implied |

Native README and command guide lack the published structured review additions. Native contributing guidance lacks the PATHEXT fix/deployment scope and retains an old output-ignore statement. The other five native guides match their pre-audit published counterparts and share the stale statements corrected here. The native checkout does not contain the publication changelog/release record. All eight native guides subsequently received explicit native-versus-publication scope and published-guide links. Narrow additional corrections qualify unverified installed-task claims, logical byte meaning, Top selection semantics, historical Defender observations, and the native fixture diagnosis. Native ignore rules really do leave Defender JSON unignored, and its scripts really are untracked; those native-specific facts were retained rather than overwritten with publication claims. No public structured-report examples or PATHEXT implementation claims were copied into native instructions. The original code, index, and unrelated edits were preserved. Published guides describe the exact publication source; native guides now explicitly identify their actual limitations.

## Release status correction

The original release record's authentication blocker and 461-test results are historical checkpoints. The integrated candidate later passed **466/466** clean-clone tests in both Windows engines, zero lint findings, coverage **94.06% (PS5.1)** and **93.78% (PS7)**. The publication coordinator reported [hosted CI 42367215761](https://github.com/victor000000/pc_cleanup/actions/runs/42367215761) successful at `20599078990a3d233df8e24658c4f852e4eb24bd`, with the source tree independently matched to the tested candidate. This supersedes the blocker without altering the historical record.

The dated 2026-10-21 native fixture failures were subsequently traced to inherited `PATHEXT` missing `.EXE`; the test runner fix at `2e963c2` restores the environment afterward. That explains the fixture failures, not hardware maintenance readiness. Neither prior hosted CI nor local tests certify a real disk, installed Defender task, reboot, live data consistency, or future source revision.

## Verification and limitations

Documentation acceptance checks local links and heading anchors, parses fenced PowerShell examples in both Windows engines without executing operational snippets, and checks explicit local-script example parameter names against AST metadata. Source inspection covers all report/storage/maintenance/diagnostic/compatibility entrypoints, the five shared libraries, both Defender scripts, manifests, ignore rules, dependency installer, test runner, and CI workflow. No device changes, task execution, active network diagnostics, production scans, or deletion are needed for this review.

Offline documentation checks passed for **11 Markdown files, 85 local links/anchors, 18 fenced PowerShell blocks parsed per engine, and 15 direct local-script invocations checked per engine** (Windows PS5.1.26100.9711 and PS7.6.9). No examples invoked operational entrypoints. The two reference text templates were inspected manually.

The existing full source gate runs from a clean publication clone in both Windows engines with pinned local dependencies. Per-engine output and documentation-check results are ignored local artifacts, not bundled evidence. Final commit/tree and final-SHA hosted CI acceptance are handed to the serialized publication coordinator; this record does not predeclare that future run successful.

The documentation checks are offline and deliberately do not verify external URL availability, render Mermaid, execute every workflow example, or prove every semantic statement mechanically. Parameter/default contracts and safety prose require source review. No deployment/CD system, runtime credentials, or application data-retention policy is introduced. Windows-native runtime APIs remain required; WSL inventory and application cleanup decisions remain separate operator work.

## Native correction provenance

Corrected native paths: `README.md`, `CONTRIBUTING.md`, and `docs/ARCHITECTURE.md`, `COMMANDS.md`, `DEFENDER-STARTUP.md`, `MIGRATION.md`, `SAFETY.md`, `TROUBLESHOOTING.md`. The incremental patch is measured against the actual dirty/untracked pre-edit bytes, not against native HEAD, so it excludes preexisting work. Local before snapshots, SHA-256 before/after manifest, and `native-docs-only.patch` are retained under ignored `artifacts/native-docs-followup/` in the publication checkout. That patch is a local handoff, not private content included in the public commit. At the initial checkpoint, the native documentation had not been staged or committed. It was subsequently committed locally in two documentation-only steps: `454ecec3ef097d664947fc93f17d16433c1ca66f` preserves the reviewed preexisting eight-guide baseline, and `7e3347999934352131b1231f6518055b400288f2` records the incremental corrections. These commits belong to the native working checkout with its existing mixed code context; they are not portable release validation or candidates for public-mirror publication. Unrelated code and private outputs remained unstaged.

Native documentation checks passed in both engines: eight Markdown documents, 16 parsed PowerShell blocks, and 13 direct-script parameter checks per engine. Local link/anchor checks cover the native guides independently. Native code was not changed to import published features or to force its source tests to match publication results; full source acceptance above applies to the publication candidate only.
