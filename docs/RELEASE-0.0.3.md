# Release 0.0.3 — Reviewable disk inventory

Version 0.0.3 introduced the tool version in `Project.psd1` and a read-only object/JSON report for an explicit directory.

## Report behavior

The five legacy reports emit formatted text with warnings on a separate stream. `Get-CleanupReview.ps1` returns one object, or a single JSON document with warnings included. Relative roots resolve against PowerShell's filesystem location. The report records UTC timestamps, exact logical file lengths, category hints, and the tool and schema versions.

The structured report counts all readable files and all matches at or above `MinimumFileBytes`. It retains up to `Top` candidates ordered by byte count and then path, plus a bounded warning sample. `CandidatesTruncated` and `WarningsTruncated` describe those independent limits. `ScanStatus` records whether the traversal observed a warning. Hard links can contribute more than once and files may change during a scan. [Schema 1 contract](COMMANDS.md#schema-1-output-contract)

In the legacy large-file report, images qualify at any size and other files must exceed the threshold. Selection retains up to `Top` entries per category and keeps the earlier entries at an equal-size cutoff. Both reports still visit the readable tree.

## Verification and publication

The Windows tests exercise thresholds, ties, missing and unreadable paths, warning caps, JSON arrays, and metadata-only reads against synthetic files. The published 0.0.3 source passed both Windows workflow jobs. [Published source](https://github.com/victor000000/pc_cleanup/commit/20599078990a3d233df8e24658c4f852e4eb24bd) · [Windows CI](https://github.com/victor000000/pc_cleanup/actions/runs/42367215761)

For the change to scans rooted beneath a junction or cloud placeholder, see the [0.0.4 release notes](RELEASE-0.0.4.md).
