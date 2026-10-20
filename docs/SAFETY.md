# Safety contract

1. **No automatic deletion.** A large file is a finding, not disposable data. Live databases, historical snapshots, market data, VM images, and personal files require contextual review and consent.
2. **Read-only scanning.** Do not follow junctions, hydrate cloud placeholders, or hide partial-scan warnings. Logical sizes are estimates, not allocated disk usage.
3. **Stable identity before mutation.** Disk numbers and letters can change. Require the intended USB disk's UniqueId/serial, validate non-system status, and recheck after confirmation. Refuse ambiguity.
4. **No forced eject escalation.** Never climb into USB hubs/PCI/ACPI nodes, force-dismount, offline the disk, kill applications, or disable indexing to override a veto. A rejected request must stop visibly.
5. **No drive-letter takeover.** Do not remove an occupied mount merely because assignment failed. Missing/stale mappings need separate explicit diagnosis.
6. **VHD ownership.** Require an explicit literal image path, reject already-attached/busy images, attach read-only, and release only an attachment acquired by the current operation. Do not automatically stop WSL/Docker or detach another owner's image.
7. **Checked native failures.** Failure or ambiguous compaction output is not success. Locale-dependent acknowledgement supports English and Simplified Chinese; other output fails closed.
8. **Log ownership.** Acquire new logs atomically with `FileMode.CreateNew` and keep the owned stream for all writes. Never overwrite an existing destination or append failure details to a path whose acquisition failed. This includes aliases/hardlinks to operational inputs.
9. **Review combined operations.** Completed hibernation/pagefile changes remain if a later independent step fails. WMI pagefile maintenance supports Windows PowerShell 5.1 only; unsupported capability must fail before the first mutation.
10. **WhatIf is side-effect-free.** No logs, native calls, repairs, registry writes, service changes, or task creation. It previews intent; it does not prove a real device will accept the operation.
11. **Tests are not maintenance.** CI and unit tests must never run real DiskPart, DISM, powercfg, CHKDSK, Handle, device eject, network sweeps, or remote-PC commands. Keep dangerous boundaries mocked and Pester's registry fixture disabled.
12. **No implicit downloads or license acceptance.** Development setup is explicit and hash-verified; tests never bootstrap themselves. Handle execution requires reviewed EULA acceptance and a verified executable.
13. **Keep local evidence private.** Archives, runtime logs, captures, installers, dependency caches, credentials, and keys must remain ignored. Review Git status before any publication.

If real hardware refuses an operation, do not add a broader force fallback to make a test or demonstration succeed. Diagnose the owner/driver and preserve availability and data integrity.
