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

