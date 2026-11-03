# HTMLApp

HTMLApp is an iOS 16+ app for creating, saving, running, editing, and privately sharing single-file HTML mini apps on iPhone and iPad.

## Current features

- Forge AI app generation, edits, style previews, and per-app timing history
- Local Library with folders, favorites, search, import/export, and guarded backups
- HTML/CSS/JavaScript runtime using WKWebView and native permission bridges
- Nearby sharing without transferring stored personal data
- Home Screen installation guidance, native widget snapshots, and Live Activities
- Siri/Shortcuts entry points, debug history, and an onboarding walkthrough
- Car display compatibility for setups that already launch arbitrary iOS apps: compact launcher, Apps exit, adaptive runtime and AI guidance
- Flexible style directions and a vertically scrolling look picker with reserved footer space
- Manual-only device IPA builds; app and widget version metadata is validated before packaging

## Building

The active XcodeGen project is `project.yml`. It compiles `HTMLAppV3/`, `HTMLAppShared/`, `HTMLApp/WebClipSupport.swift`, widget sources, and app icon assets. The older app entry points were removed because they were not part of the target.

**GitHub Actions does not run on push.** Start the `Build HTMLApp IPA` workflow manually, or use your own macOS/Xcode build process. The workflow reads the release identity from `HTMLAppV3/HTMLAppWhatsNewView.swift`, verifies that the built app and widget Info.plists contain that version/build, and checks the packaged IPA with `scripts/verify-ipa.py`.

The workflow packages an unsigned app and then produces a TrollStore-oriented IPA using `ldid`. Other installation methods may require different signing profiles and authorized App Group entitlements. Building successfully does not prove that an IPA is installable under every signing method.

## Safety and testing

Car display compatibility does not grant native CarPlay installation or entitlements. Enable **Car display** from the Library's More menu when a mirroring tool reports an iPhone screen. See [car display behavior, limitations and device checks](docs/car-display-and-styles.md).

A Library load failure preserves the damaged file and blocks empty-library overwrites; a rolling backup supports recovery. Native clipboard reads require per-app permission; WebView native bridge messages from subframes are rejected. External source caching limits file sizes and budgets.

Forge performs local WebKit smoke tests. Advisory findings (for example, preview-only network failures) do not automatically launch expensive model repairs. Blocking defects can receive one targeted AI patch. Real iPhone/iPad testing remains necessary.

The repository includes widget tests and a packaged IPA verification script. The debug log is stored locally and may contain user prompts or generated app code; review logs before sharing them.

## Security note

Store Discord webhook URLs as GitHub Actions secrets. The current build and delivery scripts contact Discord directly, not a proxy. Rotate any webhook URL previously sent to an untrusted intermediary.


## Generated app viewport contract

Saved/generated HTMLApps use a fixed page scale to avoid pinch, double-tap and input-focus zoom. The host also prevents document-level horizontal scrolling; explicitly designed horizontal carousels, chip strips, graphs and table wrappers opt in via `data-htmlapp-horizontal-scroll="true"`. Forge validates multiple phone/iPad/landscape widths and treats measured horizontal overflow as a blocking defect. An overflow-clipping safety net is not a substitute for responsive layouts. Generated typography must remain legible at accessibility text sizes; these restrictions are for app surfaces, not ordinary website browsing.

## Semantic Forge editing

Forge now creates a conservative value-free semantic model of saved apps (DOM/component identifiers, storage keys, database collections, native integrations and acceptance invariants). The local `ForgeSemanticModels` sidecars remember short edit summaries without storing prompts, secret values or full code. Short requests such as 'cleaner', 'more native', 'faster', and 'add reminders' are turned into bounded edit contracts before patching. The literal request remains authoritative. Full-source fallback is preserved when a focused selector is ambiguous; the system does not claim full automated workflow verification.

## Bridge protocol and introspection

The documented native dispatcher surface is enumerated in `HTMLAppV3/HTMLAppBridgeRegistry.swift`; the repository's consistency check compares it to Swift dispatch cases. The JS bridge now supports `AbortSignal` on `HTMLAppNative.call` (stopping the underlying native job only for explicitly supported methods), adds `capabilities.has/describe`, protocol metadata, and per-app host permission status/request. Permission status deliberately reports system authorization as unknown unless the underlying iOS framework checks it.

## Native public API requests

`HTMLAppNative.network.request({url, method, headers, body, signal})` is an optional public-HTTPS, text/JSON-only native networking API for servers lacking browser CORS. It requires the saved app's **Internet API Requests** permission and a separate consent prompt per hostname. Direct IPs, LAN/loopback hosts, redirects, cookies, insecure HTTP, credentialed URLs, oversized bodies and binary responses are prohibited. `network.allowedDomains()` lists approved hosts and `network.revokeDomain(host)` revokes one. The feature does not install a backend or circumvent API authentication and it should never be used to ship secret keys embedded in HTML.

## Native UI and domain management

Saved apps can optionally invoke UIKit alerts, action menus and date/time pickers through `HTMLAppNative.ui`, with bounded action counts and throttling. `HTMLAppNative.events.on` provides a JS unsubscribe wrapper for existing native events. The per-app Permissions screen lists approved native-network API domains so each can be revoked independently.
