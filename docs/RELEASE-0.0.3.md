# Release 0.0.3: reviewable disk inventory

## Baseline and assumptions

The published baseline is commit `2e963c2`, with no project release version or
tags. Establish 0.0.3 in `Project.psd1`; dependency versions remain independent.
No next-version work was present in the clean publication checkout. Development
uses that checkout on `codex/release-0.0.3`, preserving the original dirty checkout.

## Design and critical review

Existing reports format text and emit separate warning streams. A captured table
can lose evidence of skipped paths. Large-file reporting also retains every match.
Add a separate opt-in object/JSON report so existing commands keep their behavior.
Use the shared metadata-only scanner, one traversal, at most Top candidate rows
(plus one transient row and sorting copies), and a capped warning sample. Count
all matches and warnings, and expose truncation independently of scan completeness.
Top limits report storage, not scan duration or the traversal's directory stack.

Require an explicit root. Resolve relative paths against PowerShell's current
filesystem location without glob expansion or existence checks; reject providers
such as Env:. Include UTC timestamps, exact logical bytes, tool/schema versions,
scan completeness, and review notes. MinimumFileBytes is inclusive for this new API.
Do not classify any file as safe to delete based on name, age, or extension.

Risks reviewed: snapshots change during enumeration; links/cloud placeholders and
access failures must produce Partial, including invalid/missing roots. Complete
only means no observed scan warnings, not an atomic snapshot or deletion approval.
Logical lengths can double-count hard links and differ from allocated space. These
limits belong in every result. Filenames may be private, so output is not uploaded
or automatically persisted. JSON is one data document with warnings embedded.
No deletion, hashing/content reads, service checks, DB opens, network acquisition,
credential persistence, or maintenance behavior is added.

## Verification plan and release limits

Exercise exact threshold boundaries, top-N ordering/ties, empty/partial scans,
metadata failures, warning caps, all review categories, provider/path handling,
JSON arrays, and unchanged fixture bytes. Retain the existing junction/cloud
scanner regression suite. Run parse/lint/Pester/coverage on Windows PS5.1 and PS7
with hidden Windows processes. Review the final diff and original checkout state.
No production disk scan is necessary to test this feature. This release adds no CD.

## Final self-review and local evidence

Tests use disposable fixtures, including exclusive file locks that reject content
reads. Size/timestamp failures are caught before successful-file counters advance.
Relative paths resolve through PowerShell's filesystem provider, rather than the
process working directory. Warning samples can be disabled without hiding partial
status. Existing maintenance entrypoints and report contracts are unchanged here.

- ps51: 461 tests, 0 failures, 0 lint diagnostics; 93.82% command coverage. Evidence: `artifacts/release-003-ps51/` (ignored local NUnit XML, JaCoCo XML, lint/environment JSON).

- ps7: 461 tests, 0 failures, 0 lint diagnostics; 93.53% command coverage. Evidence: `artifacts/release-003-ps7/` (ignored local NUnit XML, JaCoCo XML, lint/environment JSON).

No production scan or maintenance was run. These are local results; this branch
has not been pushed, so hosted CI has not validated 0.0.3. Existing CI will run
the same test suite on publication. No deployment/CD target is introduced.

Development location: `C:\Users\victo\pc_cleanup-publication-20261105`, branch
`codex/release-0.0.3`. The original `pc_cleanup` checkout was not modified by this
task. The peer legacy bounded-list optimization was reviewed and integrated separately into the publication branch. It retains at most Top rows per category, preserves strict thresholds and encounter-order ties, and adds five regression tests. The structured review retains its inclusive threshold and path-based tie ordering.
The integrated command documentation distinguishes both report contracts. There is no shared-file staging in the original checkout.

## Publication checkpoint

The user authorized commit/push and full unit/CI verification. The existing
workflow already installs the pinned test dependencies in a clean Windows checkout
and runs the full suite with coverage under PS5.1 and PS7, with read-only repository
permissions and no retained checkout credentials. No CI workflow change is needed
for the new automatically discovered test file or version metadata.

Publication is blocked by authentication: connector branch creation returned HTTP
403 `Resource not accessible by integration`; no headless Git credential is
available; the earlier temporary deploy key was removed. The coordination audit
also confirmed existing SSH identities fail authentication. No keys or account
permissions were changed to work around that boundary. The remote base remains
`2e963c29076595bc0ace432f108eb0b2dbf52678`. There is no new hosted run to claim.

Fresh-clone setup and validation records are kept in ignored `artifacts/` alongside
the first validation runs: `release-003-clean-setup.log`, the `clean-checkout-003`
checkout, and `release-003-clean-ps51` / `release-003-clean-ps7` output directories.
Consult their exit statuses and timestamps; missing results are not a pass.
