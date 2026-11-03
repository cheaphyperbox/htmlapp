# Forge app manifests and semantic editing

Every generated or edited saved HTMLApp now has two value-free metadata files in Application Support:

- `ForgeSemanticModels/<app-id>.json`: compact DOM/screen/route/storage/native API information and the last accepted edit summaries.
- `ForgeAppManifests/<app-id>.json`: versioned product and regression contract with declared screen/component identifiers, storage keys, collections, native methods, host permission candidates, public HTTPS hosts referenced in source and design tokens.

These are **advisory metadata**, not executable code, native entitlements, saved user data, permission grants, verified correctness proofs, or actual stored app records. Both files are removed when an app is deleted. Metadata is regenerated when app HTML is saved or imported, preserving accepted regression criteria on ordinary edits.

## Edit policy

Forge interprets short changes against the semantic model, the current app, its previous accepted edit notes and the package manifest. It generates a minimal patch where possible, checks native method candidates against the installed catalog, and preserves old storage identities. Significant capability changes use research/planning rather than silently bypassing the relevant authorization contracts. Complex edits still require model judgment; these heuristics are not guarantees that ambiguous requests will be interpreted correctly.

App authors should give major screens stable `data-forge-screen` or `data-screen` names, important controls `data-forge-id` names, and routes `data-route` names. Use CSS tokens for shared colors, spacing, type and corner radii. Keep these identifiers and persistence keys stable through visual revisions.

## Capability planning

`ForgeCapabilityPlan.infer(request)` maps plain-English hints to **candidate** documented method names. It does not grant access. E.g. voice notes -> `audio.record`, photo capture -> `camera.capturePhoto`, movie recording -> `video.capture`, receipts -> `documents.scan` and `vision.recognizeText`; location tracking -> foreground `navigator.geolocation`, not invented unrestricted background GPS. Feature detection, per-saved-app permission and iOS system authorization are independent.

## Portable archives

Version 6 of the `.htmlapp.zip` package retains its full HTML and optional personal-data backup behavior while including `appManifests` as optional descriptive metadata. Archives from earlier format versions still decode. Permission grants are never transported. Nearby sharing omits semantic edit history, and imports regenerate structural metadata from the app's HTML rather than blindly trusting executable-looking instructions in transferred manifest text.

## Layout contract

Document-level horizontal overflow and page zoom are prohibited in saved/generated app mode. Components such as carousels and timelines may opt in to horizontal scrolling using `data-htmlapp-horizontal-scroll="true"`. The host injects a fixed viewport policy, while the offscreen verifier tests multiple iPhone and iPad sizes and reports individual overflow offenders, unmarked horizontal scrollers and zoom policy failures. Simply clipping an oversized layout is not considered a correct repair; generated layouts must reflow.

## Limitations

Offscreen QA mocks real iOS permissions and hardware; it cannot prove full device functionality. Native widgets, Bluetooth, recording hardware, camera, HealthKit and background scheduling require an appropriate actual device, signing/entitlements and user approval. No generated app or prompt can override iOS sandbox rules. The generated manifest and semantic tests are a foundation for increasingly comprehensive scenario-based QA, not a substitute for on-device workflow and accessibility testing.
