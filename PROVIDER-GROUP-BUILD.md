# Provider group test build

One HTMLApp.ipa carries the original App Group declaration for TrollStore. Feather must re-sign both executables. In Widgets & Background, choose a common declared signing group, accept the shared-data warning, republish, and run the extension read test. Only a matching extension receipt proves cross-process access. Code signature inspection reads XML declarations; unknown/DER-only formats fail closed. Provisioning profiles still need to authorize each executable and its group. This build cannot fix invalid profiles or missing extension authorization.

Saved HTMLApps are not moved. Alternate groups use a dedicated HTMLApp-Widget-Storage-v1 directory. Old widget snapshots remain in their original store. Switching requires republication. Background job configuration stays in the main app defaults for provider groups. Original group data paths remain compatible.

Provider groups can expose published snapshots, widget refresh configuration and diagnostics to other apps authorized for the group. Do not publish sensitive content there. Data Protection is retained for shared files; encryption with a key in that same group would not isolate other group members. No claim of provider-isolated encryption is made. A dedicated App Group and app/extension profiles are the supported private installation configuration.

Automated tests cover bounded signature parsing, malformed inputs, explicit group selection, storage, migration, primary normalization, stale writes, family resolution and provider timelines. Physical-device rendering and Feather re-signing must be tested after installation.
