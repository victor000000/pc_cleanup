# Release 0.0.4

Directory reports inspect parent directories before enumerating an explicitly
selected root. A root below an NTFS junction or cloud placeholder returns a
partial scan with a warning and zero inspected files. The structured report
keeps schema version 1 and reads its tool version from the project manifest.

The regression uses a disposable junction with a synthetic file below its
target. It verifies the report skips enumeration, preserves the warning, and
reports zero files. A complete result describes the filesystem state observed
during that traversal.

Run the full offline suite with coverage in Windows PowerShell 5.1 and
PowerShell 7 using the [development instructions](../README.md#development-quick-start).
The [Windows workflow](../.github/workflows/ci.yml) publishes synthetic validation
artifacts. See the [command reference](COMMANDS.md#structured-cleanup-review)
for the report contract and [0.0.3 release](RELEASE-0.0.3.md) for prior changes.
