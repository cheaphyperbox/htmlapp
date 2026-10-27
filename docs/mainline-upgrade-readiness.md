# HTMLApp mainline implementation and build-readiness status

This is a **development snapshot**, not a successful Xcode build report. Work is committed exclusively to `mekabrine/htmlapp` `main`; `cheaphyperbox/htmlapp` remains the external IPA build fork.

## Changes integrated in source

- **Offline Forge (experimental):** iOS 26-gated Apple Foundation Models availability, explicit offline consent, Quick/Balanced/Thorough attempt budgets, local planning/generation/repair, isolated WebKit verification, cancellation, a settings panel and both Generate/Edit entry points. Retains the existing HTML until an offline edit completes. Hardware verification and compiler checks remain outstanding. Large edits are deliberately rejected instead of risking truncated rewrites.
- **Storage inspection:** Saved-app Developer context menu shows a source/icon size approximation and portable data + SQLite size. Manage Storage lists portable keys and SQLite documents with separate destructive deletion confirmation and an up-front warning. These figures **exclude WKWebView localStorage/IndexedDB, WebKit cache and other external assets** and are not a total sandbox accounting.
- **Portable storage safety:** native appStorage set/remove/clear routes now call checked atomic writes; failures reject with `storage_write_failed`. Explicit empty portable snapshots are persisted and offered to iCloud instead of deleting the local file. Cross-device conflict resolution for simultaneous edits remains incomplete.
- **QA fixes:** native bridge mock answers capability and storage requests deterministically without touching device hardware, offscreen tap tests skip invisible controls, post-repair checks include original core workflows, bridge calls now expire, and the source asserts these invariants.
- **Other reliability fixes:** trailing-slash provider endpoint normalization, HealthKit missing-data state, prompt contract deduplication, and cleanup of BLE scans, speaking, brightness, and keep-awake on app exit.

## Still incomplete from the 39-item audit

1. Full iCloud folder conflict merges, revisioned folder deletions and multi-device merge tests.
2. SQLite background/sync transport, record-level conflicts and migration tests.
3. True per-app WebKit origin migration, offline asset precache and safe WebKit storage inspection.
4. Fully scripted user-flow acceptance testing and visual screenshot comparisons.
5. More generation throughput work: icon deadline, per-provider request scheduling, useful-token stream watchdog, async checkpoints and artwork manifests.
6. Database actor, connection reuse and indexed search; portable data caching and batch writes.
7. Native tab-bar controller migration, precise measured obstruction, Reduce Motion host animations, mount acknowledgement and consistent ownership contracts.
8. Shared iOS component kit, accessibility/dynamic type/theme matrices, selectable mockup source scaffold, and themed widget error components.
9. Machine-readable API schema that generates all bridge surfaces, detailed capabilities availability states and verified public API endpoint examples.
10. Interactive Widget/App Intent actions, typed Shortcuts app entities, richer MapKit callbacks/routing, expanded BLE, HealthKit and NFC workflows, and optional authenticated APNs delivery backend.
11. Larger architecture decomposition and executable automated tests for the new Apple Intelligence and storage flows.
12. Source-level tested complete cancellation/thermal/battery behavior for every generation stage, runtime mocks with denial and error modes, and real-device testing.

## Build readiness

No local Xcode 26 device SDK or iOS simulator is available in this environment. Source changes were confirmed in the GitHub repository and selected invariants were checked by inspection, **not executed as a complete Python regression suite**. Swift compilation and signing have not been verified. Do not mark this build ready for distribution.

When ready to test: sync `cheaphyperbox/htmlapp` from upstream `mekabrine/htmlapp`, run the existing manual GitHub Actions workflow, then inspect the full failing job logs. Build source stays in `mekabrine/htmlapp`; the fork should not be edited as part of debugging.
