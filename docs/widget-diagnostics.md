# Native widget investigation and device acceptance

## Verified source defects

- `persist` previously caught write failures and returned Void; `widgets.configure` still resolved successfully. Container lookup alone did not establish write/read access.
- Read/decode failures silently became an empty list or stale preferences. A subsequent write could replace unreadable data with a partial collection.
- Both providers saved their whole definition after an asynchronous refresh, including its old primary flag. This raced newer publications and selections. Atomic file replacement prevented torn JSON, not lost updates.
- Backup `replace` could preserve multiple primary flags. Default primary selection during publication was per app, not global.
- The configured snapshot and timeline used different fallback rules. A missing explicit selection could silently display another app. Entity resolution could return no entity for a previously selected ID.
- The provider ignored declared families. Read errors became the generic gallery placeholder.

These defects are real; they do not conclusively identify either reported device failure. Shared-directory mismatch, registration, provisioning, failure to launch the extension, and WidgetKit retaining a gallery placeholder remain competing device hypotheses.

## Data flow after changes

`HTMLAppNative.widgets.configure` -> bridge validates ID/snapshot -> scoped appID plus widgetID -> coordinated JSON read/modify/write -> protected atomic replacement -> decode and compare read-back -> resolve Published -> request WidgetCenter reload.

WidgetKit independently launches the extension -> provider resolver opens its own group container -> decodes JSON -> chooses explicit composite ID or unique global Primary -> checks family -> records probe receipt and definition SHA-256 -> timeline builder optionally fetches HTTPS values -> native SwiftUI renders snapshot. Providers never write definitions. Background app fetch uses compare-before-update to reject stale responses.

A reload does not capture DOM/localStorage or guarantee immediate rendering. Forge must republish on state changes. Existing saved HTML is not rewritten; bridge failures now display a dismissible diagnostic even if generated JS catches them with a generic message.

## State meanings

- Published: main-process shared-file write and decoded read-back succeeded.
- Selected Primary: chosen for the static Primary widget (including iOS 16).
- Configured instances: WidgetCenter reports configurations; this API does not prove Home Screen placement or visible pixels.
- Extension acknowledged: this probe was read by an actual `.appex` process and a receipt returned through shared storage.
- Timeline decoded current snapshot: receipt hash matches a current published definition. This is evidence of provider execution, not proof of SpringBoard rendering. Network refresh may subsequently transform the entry.

Probe/receipt files contain a nonce, time, family, status and digest; no content, file paths, credentials, or app identifiers. One latest timeline receipt is retained, so another widget can replace it. To isolate Focus Streak, test with only its widget configured. A snapshot preview never counts as a timeline receipt.

## Device acceptance (required; not replaced by CI)

1. Export a backup before installation. Upgrade in place using the same identifiers; do not uninstall or delete app data.
2. Publish Focus Streak for Small with goal 10 and streak 7. In Widgets & Background select it as Primary.
3. Start Extension Read Test. Add **HTMLApp Primary**, Small, on iOS 16. On iOS 17+ add **HTMLApp Widget** and select Focus Streak, or Selected Primary.
4. Return to Widgets & Background and Read Diagnostic Result. Record main container availability, probe nonce, extension status/family, timestamp, and snapshot match. A pending receipt is not automatically an entitlement failure.
5. Confirm the actual Home Screen displays goal 10 / streak 7. Change to streak 8; the generated app must call configure again. Confirm the next provider receipt and visible value.
6. Publish Daywell, select it as Primary, and verify exactly one Primary. Confirm an explicit Focus Streak selection remains Focus Streak on modern OS versions.
7. Test Small versus Medium, deleted selection, background/locked device after first unlock, relaunch, and upgrade with existing imports and backups.

## TrollStore evidence when the receipt is absent

In Filza locate the *installed* HTMLApp.app and copy its path. In NewTerm set APP to that path (do not use a downloaded IPA's staging folder):

```sh
APP='/actual/installed/path/HTMLApp.app'
ldid -e "$APP/HTMLApp" > /tmp/htmlapp-main-entitlements.plist
ldid -e "$APP/PlugIns/HTMLAppWidgets.appex/HTMLAppWidgets" > /tmp/htmlapp-widget-entitlements.plist
```

Inspect both files in Filza. Report only whether `com.apple.security.application-groups` contains exactly `group.com.mekabrine.htmlapp`, and whether both installed executables exist. Do not send complete entitlements or filesystem paths. These are embedded signature entitlements, not proof that the running process has received a registered container. The app's diagnostic and extension acknowledgement test actual access separately. No private entitlement inspection APIs are used.

If the main container is available but no receipt returns, capture the widget's displayed error code and any extension crash report from Settings > Privacy & Security > Analytics & Improvements > Analytics Data. Redact paths and personal data. A missing extension/crash distinguishes launch failure from store decoding. If it shows `widget_not_found` while the app lists definitions, the extension reached the resolver but did not see the same definitions. If an acknowledgement matches, container communication and decoding worked; investigate rendering/WidgetKit caching rather than re-injecting entitlements.

## Feather prerequisites

Feather must preserve the extension and sign the app and extension with profiles that authorize the same registered App Group. A certificate by itself is insufficient. Enable App Groups for both App IDs in the owning Apple Developer team and regenerate both provisioning profiles. Keep the `.appex` enabled. Do not strip App Group entitlements.

The unsigned artifact includes `WidgetSigningRequirements.plist` in each bundle as metadata for the signer. It is not authorization, and Feather is not assumed to consume it automatically. Verify the exported **signed** IPA on a Mac with `python3 scripts/verify-signed-widget-ipa.py Signed.ipa` before installing. A pass checks signatures/profile declarations, not device registration or profile validity/revocation.

If your team cannot register `group.com.mekabrine.htmlapp`, you cannot grant it by injecting XML. A supported custom build must change the group constant and both entitlement files to a group owned by that team and use matching profiles. Group changes cannot read the previous group's data; preserve the app's local data and republish snapshots into the new group. No sandbox-safe arbitrary local-file fallback connects unrelated containers; this patch deliberately does not claim one.

## Validation boundaries

CI compiles the app/extension for iOS 16+, runs hostless storage/resolver/timeline tests on available iOS 16/26 simulators, and warns when a requested runtime is absent. Independent repository objects test fresh disk reads, but these are not separate app/extension processes. Real cross-process execution and Home Screen rendering must be established by the probe procedure above. CI checks both final IPA archives and independently reads both TrollStore executable entitlements. It cannot validate the later Feather signatures, device provisioning, TrollStore container registration, or real device WidgetKit scheduling.
