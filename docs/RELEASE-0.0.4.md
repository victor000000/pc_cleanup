# Release 0.0.4

Directory reports inspect parent directories before enumerating an explicitly
selected root. A root below an NTFS junction or cloud placeholder returns a
partial scan with a warning and zero inspected files. The structured report
keeps schema version 1 and reads its tool version from the project manifest.

The regression uses a disposable junction with a synthetic file below its
target. It verifies the report skips enumeration, preserves the warning, and
reports zero files. A complete result describes the filesystem state observed
during that traversal.

## Use this source version

From the checkout root, read the tool version and run a small metadata-only report.

```powershell
(Import-PowerShellDataFile -LiteralPath .\Project.psd1).Version
$report = .\scripts\reports\Get-CleanupReview.ps1 -RootPath .\docs -MinimumFileBytes 0 -Top 1
$report | Select-Object ToolVersion, SchemaVersion, ScanStatus, WarningCount, FilesScanned
```

This checkout reports tool version `0.0.4` and schema version `1`. A skipped root can produce zero candidates. Consumers should check `ScanStatus` and `WarningCount` before treating a directory as empty. [Report contract](COMMANDS.md#structured-cleanup-review) · [Previous release](RELEASE-0.0.3.md)

Maintainers bootstrap the pinned development modules once, then run the offline coverage suite under both supported Windows engines. Match the published commit to its two Windows CI jobs. The release procedure also explains how to return to a known-good source revision. [Setup and validation](../CONTRIBUTING.md#set-up) · [Source release procedure](../CONTRIBUTING.md#release-a-source-version)
