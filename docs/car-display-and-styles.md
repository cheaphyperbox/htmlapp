# Car display compatibility and flexible styles — 1.6.47 (55)

## What is possible

HTMLApp is a general-purpose WKWebView mini-app runner. Apple's template-based CarPlay framework is category- and entitlement-controlled; it does not provide a general arbitrary-HTML surface. The app currently has neither a CarPlay category nor a CarPlay scene. Adding an unrelated entitlement or rendering HTML in a navigation-only map window would not implement legitimate native CarPlay support.

This release targets installations that **already launch the ordinary iOS app on a car screen**, such as the user's existing setup. It adds compatibility rather than claiming native CarPlay certification. It does not change signing, add private APIs, register a CPTemplateApplicationScene, or unlock installation on standard CarPlay.

Apple references:

- https://developer.apple.com/documentation/carplay
- https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements
- https://developer.apple.com/documentation/carplay/displaying-content-in-carplay

## Changes

- The app's own window trait selects a compact car launcher automatically when iOS identifies that window as CarPlay. It does not assume every connected car makes the phone itself a car display.
- Library → More (…) → **Car display** enables an explicit override for tools that report an ordinary phone window. **Phone layout** in the launcher clears the override. The override persists across relaunches.
- A scrolling adaptive launcher lists saved apps with favorites first, and opens them through the existing launch/data pipeline. Creation and editing remain accessible in the phone layout. Interactive use is for when parked; the app cannot detect vehicle motion.
- Running apps keep a visible native **Apps** exit above the WebView. Content stays inside the host display's safe bounds.
- A main-frame runtime script provides a read-only window.HTMLAppDisplay snapshot with mode, width and height in CSS pixels. htmlapp:display-change events cover mode/viewport changes, including the visual viewport/keyboard. CSS uses data-htmlapp-display and --htmlapp-viewport-height. The native host restores mode after document loads and updates it on layout changes.
- Existing apps get baseline scrolling, control size and media sizing improvements in car mode. Arbitrary old fixed portrait layouts cannot be reliably redesigned by injected CSS; use Forge's AI edit to add a proper car layout without discarding app data.
- Shared AI instructions (planner/coder/edit), the capability catalog and UI refinement instructions document the real environment API and its limitations. They require compact glanceable content, responsive short-landscape layouts, 48px car controls, native tab clearance, and no fabricated vehicle APIs.
- Initial style directions are modern/professional, technical/detailed and kiddy/easy-to-use. Each AI chooses its own composition, typography, palette and interactions. Regeneration still requests new identities; additional looks remain freeform.
- The style rail scrolls vertically, showing five full 44pt rows and half the sixth at its maximum 292pt height (10pt gaps). Short screens show fewer rows. The preview and rail share a layout region above the footer, which now occupies real layout space.
- Native tabs report their constrained/laid-out height (minimum 64pt), including safe-area clearance, after size changes. A hidden or removed bar reports zero.

## Validation and IPA build

Offline checks:

    python3 scripts/test-source-invariants.py
    node scripts/test-widget-bridge.js
    node scripts/test-car-display.js
    git diff --check

The new runtime test executes the shipped JavaScript and covers early document parsing, initial/mode/viewport changes, keyboard sizing, VisualViewport fallback, event coalescing and document reload.

This Linux environment has no Xcode or iOS SDK. Swift compilation, native layout, simulator/device behavior and installation are **not verified** here. The existing manual **Build HTMLApp IPA** workflow is the next validation step; choose the branch containing this change (or main after merge). No build is automatically started.

On an iPhone/iPad and the actual car installation, while parked:

1. Verify normal Library, running apps, native tabs and exit gestures still work.
2. Enable Car display from the Library menu; open several saved apps, use Apps to return, and use Phone layout to restore the normal Library.
3. Test a CarPlay-reported window and a mirroring tool that reports an iPhone. Verify behavior on connect/disconnect and relaunch. Some tools scale a fixed phone framebuffer without providing its true car dimensions; the override cannot change that tool's projection settings.
4. Test short/wide displays, rotation, keyboard appearance, safe edges, long app names, scrolling and native tab changes. Check that controls and content do not sit behind native tabs.
5. Generate at least nine styles, scroll to the last look and the plus button, select a look, regenerate, and build. Verify 5½ rows on screens with sufficient height and no overlap with Use this look. Also test the smallest supported phone and large text.
6. Ask Forge to adapt an existing portrait app for car display. Verify it reads the initial environment, responds to display-change events and preserves saved data and all phone workflows.

Standard template-based CarPlay would require a separately scoped eligible feature/category, Apple approval and native template UI, plus simulator and vehicle testing.
