# HTMLApp 1.6.8 (build 15): icon regeneration, iOS native tabs, installation, Forge

## Why every regenerated icon looked identical
The icon service produced valid-looking scripts such as:
```
SIZE 1024 1024
BG #26213D
FILL #E9E1F4
RECT 215 158 570 646
FILL #83A89D
TRIANGLE 510 578 424 527 458 622
```
The app's local renderer previously demanded an **inline color argument** at
the end of every RECT/CIRCLE/LINE/TRIANGLE. It silently ignored standalone
FILL commands, so every shape was ignored. It then rejected the BG-only
bitmap as blank and fell back to the same generic icon. The three repair
requests shown in the user's 2026-10-23 log were all affected.

The renderer now accepts persistent `FILL #RRGGBB` alongside the existing
optional inline shape color and one-shot gradient modifiers. The icon AI
system instruction documents this grammar. The widget test target now compiles
the local icon renderer and has an XCTest for three of the actual failing
script patterns from the debug log. The approved icon still changes only
when the user taps **This Looks Good**. No existing icons are automatically
overwritten.

## Real native iOS tab navigation
The JavaScript contract remains:
```js
if ((await HTMLAppNative.capabilities()).methods.includes("tabs.configure")) {
  HTMLAppNative.tabs.onSelect(id => renderScreen(id));
  await HTMLAppNative.tabs.configure([
    {id:"calendar", title:"Calendar", symbol:"calendar"},
    {id:"tasks", title:"Tasks", symbol:"checkmark"},
    {id:"inbox", title:"Inbox", symbol:"envelope"}
  ]);
}
```
The host now uses a `UITabBarController` to own the tabs. The HTML app
continues to own the view state and destination actions. An existing saved
HTMLApp with hand-drawn HTML navigation is **not automatically rewritten**;
it must receive an AI edit asking it to replace the CSS tab strip with native
navigation. Forge's system prompt now prefers native tabs for appropriate
new apps and avoids overlapping CSS copies.

The OS controls Liquid Glass, and compiling/linking with the iOS 26 SDK
and testing on eligible devices is required. A UIKit controller does not
override reduced-transparency accessibility settings, device restrictions,
customization, or Apple's layout decisions. The iPad adaptation and
transparency must be checked on real hardware.

Apple reference: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

## Clean screen content
Both Forge's full-app and three mockup prompts prohibit drawing fake
9:41 status bars, battery/cellular indicators, iPhone bezels, home indicators,
notches, and Dynamic Islands. iOS owns these surfaces. Older saved HTML
mockups are not silently rewritten.

## Home Screen installation
The Library's Add to Home Screen action now prepares the Web Clip profile
without an intermediate Safari-vs-export confirmation. When the local
profile URL is ready, the existing custom instructions sheet opens. It has
one primary **Continue to Safari** button that launches the profile URL in
the external browser. The old embedded `SFSafariViewController` panel and
export choice have been removed from this flow. Profile installation still
requires device confirmation in Settings; HTMLApp cannot bypass this.

## Generation safety and mini-game
The top of the Forge dashboard now shows a large red warning to keep HTMLApp
and the screen on. The red host-owned Live Activity also says Return to
HTMLApp, and its tap target is recognized as a Forge deep link. Start and
finish requests are serialized to avoid async ordering races.
ActivityKit permission/device budget restrictions still apply, and a Live
Activity itself is **not** a background execution entitlement.

The optional falling-shapes game has wider touch targets, streak scoring,
light success haptics, a restart button, and simpler instructions. It does
not replace actual generation progress or create misleading milestones.

## Verification still necessary
- XcodeGen iOS project generation and a signed build with the current iOS 26 SDK
- Unit tests for color-inheriting IconScript rendering on simulator
- On-device confirmation of glass styling, web content hit-testing, tab events,
  Safari profile download, Forge Live Activity enabled/disabled behavior,
  and icon approval/saving
- Test on iPhone and iPad. The iPad's tab-to-sidebar style is OS-controlled.
- Current fixes were committed to GitHub, but the tool environment used
  to make them has no Xcode or real iOS runtime and therefore cannot certify
  a successful compile or visual match.
