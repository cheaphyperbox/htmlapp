# HTMLApp 1.6.12 (build 19) — Optional iCloud synchronization

## Settings
Open **Settings → iCloud Sync**. **Sync HTMLApps with iCloud** is off by default.
Only when it is enabled does **Sync HTMLApp Data** appear immediately below
it. A **Sync Now** button appears alongside those controls.

- Apps on: mirror saved HTMLApp code, names, summaries, icons and folder
  structure through the user's iCloud Documents container.
- App data on: additionally mirror portable app data created through
  HTMLApp's native `appStorage` bridge; the source remains per saved app.
- Data off: portable data stays local; only saved apps are mirrored.
- Both off: no iCloud exchange is made; disabling does not delete local or
  already-uploaded copies.

The app attempts an exchange on launch and when resumed, and requests one
after local app saves and portable-data edits. "Sync Now" also requests one.
This is **best effort, not instant background push**. iOS controls iCloud
uploads and downloads, network availability, and background execution.

## Privacy and collision behavior
Local Library recovery safeguards remain in force. No iCloud failure deletes
the local Library. App records merge by stable ID and the record's
`updatedAt` date; the newer known version wins. App deletions produce
timestamped cloud tombstones to avoid immediately resurrecting removed apps.
Folders are mirrored so synced apps' placements remain available.

Portable app data is stored under each HTMLApp ID and mirrored only when
both switches are enabled. Permission grants, OS authorization state,
provider credentials, Keychain contents, and device-specific settings are
not intentionally uploaded. Portable app data itself may contain personal or
sensitive values written by a generated HTMLApp, so enable its toggle only
if those values should be present in iCloud.

Conflict handling is **record-level**, not a multiuser CRDT. Simultaneous
edits or writes on offline devices may prefer the later timestamp; individual
app-storage keys are not independently merged. The first iCloud download
may be deferred until the network is available; unreadable app documents
are not overwritten while waiting.

## Required Apple signing setup
The app entitlement now declares `CloudDocuments` and the iCloud container
`iCloud.com.mekabrine.htmlapp`. The app's Info.plist declares it as a
private document-scope container.

**The developer account/App ID and the actual IPA provisioning profile
must also authorize that exact iCloud container.** This configuration
cannot be completed by changing GitHub source code alone. If the IPA is
signed using a profile without iCloud entitlement support, code signing
or installation may fail, and iCloud storage will be unavailable.
The widget extension does not require the iCloud entitlement; only the
hosting HTMLApp reads/writes the cloud documents.

Apple's documentation:
https://developer.apple.com/documentation/xcode/configuring-icloud-services
https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)

## Verification
This commit contains source code and source-level assertions; no Xcode
compiler or real iPhone/iPad is available in this session.
Test initial enable, no iCloud account, both data-toggle positions, cross-device
app edits, large HTML/icon storage, deletion propagation, offline conflicts,
same Apple Account/signing team, and account change. Verify generated
HTMLApps' own browser-localStorage databases separately: the portable
appStorage bridge is synchronized, but arbitrary WKWebView localStorage,
IndexedDB, cookies, external service accounts, and permissions are **not**
mirrored by the optional data toggle.
