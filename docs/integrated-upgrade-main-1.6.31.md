# HTMLApp 1.6.31 integration status

This document records the changes actually present on `main` after the requested integrated-upgrade work. **This is not a completion or build certification.**

## Changes committed

- `project.yml` and `HTMLAppWhatsNewView.swift` now declare version **1.6.31**, build **46**. The intentional version number reduction preserves later source capabilities rather than reverting the code.
- `NativeAPIBridge.swift` no longer repeats Vision cases inside the NaturalLanguage dispatch branch.
- Existing microphone-permission-gated transcription can now be called as `HTMLAppNative.speech.recognize({locale:'en-US'})` and stopped via `HTMLAppNative.speech.stopRecognizing()`. Older `listen` and `listenStop` methods remain supported. Speech recognition is **not guaranteed offline** on every device.
- `DeviceAPICatalog.swift` documents the new aliases. `scripts/test-source-invariants.py` asserts their catalog/bridge/wrapper parity and guards the Vision case fix.

## Capabilities found in existing code

Existing implementations include saved-app AI completion/classification, AI permission and kill switch, Vision/NaturalLanguage, foreground speech, SQLite document operations, Spotlight, Shortcuts integration, a compact-output setting, widgets, backups and WebKit runtime verification. Presence in source does not prove correct behavior or entitlement support on device.

## Major requirements not yet implemented or independently verified

- Cancellable token-by-token native AI streaming and verified Foundation Models fallback.
- HealthKit read access, NFC foreground NDEF, and native MapKit presentation with callback routing.
- Camera-based live scanning, full requested database query/cursor/full-text semantics, dynamic per-app App Intents, Spotlight item deep-link callback.
- Stable app-specific `WKURLSchemeHandler` origin, declarative offline assets and tested migration of existing localStorage/IndexedDB data.
- Fully measured prompt caching/parallel generation; compact scaffold injection and fallback; seeded creative design fingerprints and sameness correction.
- Browser-flow replay, comprehensive bridge lint, automated responsive/safe-area checks, and smaller native bridge/generation modules.
- Fresh Xcode compilation, widget tests, actual iPhone checks, entitlement-specific signing, and end-to-end backup migration.

## Validation commands

Run `python3 scripts/test-source-invariants.py`, `node scripts/test-widget-bridge.js`, `xcodegen generate` and the manually dispatched `Build HTMLApp IPA` workflow on the selected Xcode 26 environment. Enable optional simulator-based widget tests and verify the packaged app/widget. On a signed device, confirm permission-denial paths, native speech, App Groups, widgets, backup/restore, iCloud sync and saved-app data durability.

Until those pass, do not distribute the build as feature-complete or mark outstanding features as shipped.
