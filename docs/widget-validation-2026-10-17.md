# Widget validation record — 2026-10-17

App source tested and packaged: `859ce3671f5d227d242cfb10f0b6f2f548b3b087`.
Core implementation commit: `5681c7a41f28e341732193e5c3b1a5f9aea32524`.
Delivery-only fixes: `ee3d2496fad520e2e24b2c49689351259c509b4b`, `eb64cfa51626e544258b9d5fb29406ce672a7625`.

Build run: https://github.com/mekabrine/htmlapp/actions/runs/39067318367

- Xcode 26.0.1 built the app and WidgetKit extension successfully for universal iPhone/iPad, minimum iOS 16.0.
- JavaScript bridge regression test passed locally and in CI.
- Nine Swift tests passed, zero failures, on iPad Pro 13-inch (M5), simulator OS 26.2.
- No iOS 16 simulator runtime was installed on the runner; iOS 16.2 execution is untested.
- Tests cover fresh disk reads into the shared provider timeline builder, corruption preservation, legacy migration, concurrent writes, stale network response rejection, primary normalization, missing selection, family mismatch, and write failure.
- These are hostless tests. They do not simulate two separately signed app/extension processes or verify SpringBoard pixels. The device probe is still required.
- Both final IPA ZIP archives passed integrity, bundle/extension metadata, minimum OS, and device-family checks.
- Both TrollStore executables independently contained the expected App Group entitlement after extracting the final IPA.
- Both unsigned Feather bundles contained signing requirement metadata. Actual Feather signatures/profiles are not available and have not been verified.

Downloads (artifact ZIPs contain the named IPAs):

- HTMLApp-TrollStore.ipa: https://github.com/mekabrine/htmlapp/actions/runs/39067318367/artifacts/12113786952
- HTMLApp-Feather-unsigned.ipa: https://github.com/mekabrine/htmlapp/actions/runs/39067318367/artifacts/12113223899
- Test results: https://github.com/mekabrine/htmlapp/actions/runs/39067318367/artifacts/12113258429

Delivery run: https://github.com/mekabrine/htmlapp/actions/runs/39067930409

Discord returned HTTP 200, and its response confirmed both expected filenames with nonzero sizes. The summary request through HOSTISH returned HTTP 502 after earlier connection timeouts. The workflow is intentionally failed for incomplete summary delivery; compilation/package validation and attachment delivery succeeded. Secrets and raw webhook URLs were not printed.

A local multipart reproduction showed that curl `-F` truncated a JSON field containing a semicolon. Using `--form-string` preserved the JSON; the subsequent Discord request succeeded.

## Remaining acceptance gates

Neither physical device is accessible from this session. The reported iOS 16.2 TrollStore placeholder and Feather publication/picker symptoms have not been conclusively reproduced or resolved on device. No device-specific signing, container registration, or WidgetKit cache hypothesis is declared disproven.

Run the procedure in [widget-diagnostics.md](widget-diagnostics.md). Provide the diagnostic result and visible Focus Streak widget from each installation, plus the Feather signed-profile verifier result if the container is unavailable. This establishes whether the extension read the same probe and decoded a current snapshot, or whether signing/launch/access still blocks it. Effective runtime entitlements are not claimed to be available through public iOS APIs; installed signature/profile checks are separate evidence.

Existing saved HTML/local data and import implementations were not rewritten. Backup widget definitions retain the existing file format and scoped app IDs; unreadable widget data is preserved instead of silently overwritten. Full import/upgrade and locked-device acceptance remain part of device testing.
