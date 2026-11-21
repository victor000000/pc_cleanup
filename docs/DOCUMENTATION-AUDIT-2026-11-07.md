# Documentation audit — 2026-11-07

The November 7 documentation update described the published 0.0.3 source. It covered the command entrypoints, schema 1 report fields, partial scans, USB and VHD safeguards, development dependency pins, and the Windows test workflow.

## Release status correction

Version 0.0.3 was published as source. Its Windows PowerShell 5.1 and PowerShell 7 jobs both passed. The subsequent documentation update also passed both jobs. [0.0.3 source validation](https://github.com/victor000000/pc_cleanup/actions/runs/42367215761) · [Documentation revision validation](https://github.com/victor000000/pc_cleanup/actions/runs/42369905173)

## Verification and limitations

The documentation checks resolved local links and heading anchors, parsed PowerShell examples in both engines, and compared local-script parameters with their entrypoints. Hardware and system-changing examples received source review. Device, task, service, and maintenance behavior depend on the machine running the command.

Use the current guides for command defaults, troubleshooting, and release validation. [Commands](COMMANDS.md) · [Troubleshooting](TROUBLESHOOTING.md) · [Contributor guide](../CONTRIBUTING.md)
