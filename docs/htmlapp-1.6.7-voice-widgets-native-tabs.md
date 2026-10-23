# HTMLApp 1.6.7 — voice, widgets, native navigation and BLE

## Lock Screen voice and mockup selection
The Lock Screen voice screen now rejects duplicate **Generate Now** taps,
waits until the Whisper transcript is complete, and persists the dictated
prompt before entering Forge. A pending deep-link flag stops old Forge
checkpoints from taking over the handoff. Inside Forge, the prompt is read
from the persisted launch value and consumed once. Siri shortcuts retain
their direct-generation behavior.

The mockup UI reserves three vertical selection slots, sized for iPhone and
iPad, with explicit availability indicators. Individual sketches appear
blurred while other requests finish. A failed mockup request cannot create
a nonexistent preview; unavailable slots stay disabled.

The draggable microphone has two outcomes: cancel when dragged out of the
target, or submit when released inside. Apple Speech may automatically
fall back to the on-device Whisper recorder if speech permission or the
recognizer is unavailable. Offline Whisper transcribes **after finger-up**.
Mockup feedback and AI editing now wait for this completion instead of
immediately sending an empty transcription. Late results from stale
recording attempts are ignored. A first-use Whisper model download may
require network access and enough storage.

## Widgets
The timeline provider reads the **committed App Group snapshot first**, and
does not block on an HTTPS fetch. Optional configured HTTPS widget refresh
has been moved into the app's opportunistic BGTask coordinator. Publishing
a widget schedules that work. Generated apps can opt in to automatic
local data binding when calling:

```js
await HTMLAppNative.widgets.configure({
  id: "steps",
  name: "Steps",
  primary: true,
  snapshot: { title: "Today's Steps", value: "0", layout: "metric" },
  dataBindings: { value: "stepsToday", subtitle: "latestNote" }
});
await HTMLAppNative.appStorage.set("stepsToday", 4500);
```

A data change updates only fields explicitly bound to that saved HTMLApp's
own storage keys, commits its shared widget snapshot, and requests an
approx. 80 ms coalesced reload of the primary/widget kind. The separate
Lock Screen voice widget uses a standard supported mic SF Symbol and a
visible system background for tinted/StandBy presentations.

**WidgetKit redraw is still controlled by iOS**, with a per-widget budget.
No app can guarantee instant rendering when suspended or when the system
decides to throttle; targeting and persisting first make requests faster,
not compulsory.

## Native tabs and gestures
Generated HTMLApps can discover the native bridge and define 2–5 host tabs:

```js
const caps = await HTMLAppNative.capabilities();
if (caps.methods.includes("tabs.configure")) {
  HTMLAppNative.tabs.onSelect(id => renderScreen(id));
  await HTMLAppNative.tabs.configure([
    { id: "home", title: "Home", symbol: "house.fill" },
    { id: "settings", title: "Settings", symbol: "gearshape.fill" }
  ]);
}
```

The iOS host draws a real **UIKit UITabBar** and dispatches selection IDs
to JavaScript. The HTMLApp implements each destination and should offer an
accessible fallback if the native bridge is unavailable. Native UIKit
appearance is OS/SDK-dependent. Full iOS 26 floating Liquid Glass bars and
automatic iPad tab/sidebar adaptivity are specifically associated with
`UITabBarController`, which this new embedded-tab integration **does not
yet implement**. It must not be described as guaranteed Liquid Glass.
Forge's generation prompt now encourages meaningful swipe, drag, long-press,
pinch and refresh gestures with equivalent accessible buttons.

Reference: https://developer.apple.com/videos/play/wwdc2025/284/

## Nearby sharing and Bluetooth
Both send and receive pages provide instructions and a system-supported
button to open the app's Settings page. iOS does **not** let HTMLApp
silently turn on Wi-Fi or Bluetooth; users must enable the radios in
Control Center or Settings. Nearby MultipeerConnectivity transfer keeps
its existing transport. Separately, saved HTMLApps may request a
2–12-second BLE discovery scan:

```js
const {devices} = await HTMLAppNative.bluetooth.scan(6);
```

This is protected by a new **Bluetooth Devices** per-HTMLApp permission,
the iOS Core Bluetooth authorization, foreground usage, and
`NSBluetoothAlwaysUsageDescription`. It discovers advertising BLE
peripherals but does not pair with Classic Bluetooth devices or access
other apps' nearby-device data. Clipboard text read/write was already
implemented and continues requiring per-app clipboard consent.

Reference: https://developer.apple.com/documentation/corebluetooth

## Onboarding and AI specialists
The onboarding calculator opens the **same Forge generation and editing
view** in a safe demo mode and uses a prebuilt calculator. It never calls
AI, never writes to the Library, and never changes a real Forge checkpoint.
Applying a practice edit shows an explicit alert explaining the edit is
not real. The advanced model-names section is hidden/removed from AI
Settings; the specialist connection pages remain, with small green
indicators for separately configured specialists.

## Verification still needed
Run `python3 scripts/test-source-invariants.py`,
`node scripts/test-widget-bridge.js`, XcodeGen generation, widget tests,
the unsigned build, and signed on-device tests on iPhone and iPad.
Test microphone permission denial/Whisper fallback, variable mockup
arrival order, Lock Screen capture after an existing checkpoint, widget
App Group entitlement availability, BLE Bluetooth denial, native tabs on
iOS 16–26, and onboarding no-side-effects.

A static source inspection is not a successful Xcode compile or hardware
test. iOS WidgetKit, Live Activities, the Lock Screen widget, and
Bluetooth hardware must be verified on real devices.
