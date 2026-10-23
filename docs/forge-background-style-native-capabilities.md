# HTMLApp 1.6.6: Forge and native capability implementation notes

## Voice widget and visual fidelity
The Lock Screen microphone widget records a prompt, then opens Forge with
`shortcutSource = "widget"`. If `ai.stylePickerEnabled` is enabled, it
automatically begins the three-mockup stage, but **never starts building the
full app until a mockup is chosen or the user selects Skip**. Siri shortcuts
retain their original immediate-build path. The nonce is consumed once.

Three style sketches now run as independent concurrent requests. Completed
sketches appear heavily blurred while the others are in progress; selection
is locked until the requests settle. A failed request does not discard the
other two. No speedup percentage has been measured on a real iPhone.

The chosen style is supplied as actual HTML and CSS token declarations, not
just a description. A local check verifies that named CSS tokens survive
generation and can request one focused repair; the generic UI overhaul
is skipped to avoid visual drift. The style reference is saved separately
under Application Support and reloaded for AI edits.

## Background work and progress
For iOS 16–25, HTMLApp requests the limited UIApplication background
grace period and saves a recovery checkpoint. iOS may suspend or kill the
process. For iOS 26+, builds with an iOS 26 SDK additionally register
`BGContinuedProcessingTask` and submit a foreground user-initiated
continued-processing request. The system can still expire or cancel it;
HTMLApp checkpoints on expiration and offers recovery later. An interrupted
provider stream is not resumable byte-for-byte and may require a new billable
provider request.

The red host Forge Live Activity displays the exact requested warning,
the stage, and approximate (not provider-verified) progress. It is
separate from the Live Activities generated HTML apps can create.
The warning is advice and does not make 20 seconds a guaranteed safe
background interval. Stale host activities are ended on cold launch.

## Widget and ActivityKit refresh limits
A successful widget publication is committed to the shared App Group before
HTMLApp requests `reloadTimelines(ofKind: "HTMLAppPrimaryWidget")`.
Portable app-data writes request the same refresh; bursts are coalesced
for ~80 ms. WidgetKit still decides when to redraw and applies a daily
budget; the system cannot guarantee immediate updates while suspended.
Apple documents roughly 40–70 refreshes per day for frequently used widgets.
Private portable data does not automatically become a widget snapshot:
apps still need to publish updated widget-visible data explicitly.
Existing generated-app Live Activities update on explicit native update
calls; native date-based timers keep counting without republishing.
High-frequency remote Live Activity updates require APNs push tokens and a
server that authenticates with Apple; the Info.plist switch alone is not a
working push delivery backend.

Sources:
- https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados

## Per-app native API audit

Already implemented in the bridge, with per-app permission and iOS prompts
where required: WebKit camera/microphone access, one-time location,
notifications, Live Activities, contacts selection/list/creation, photo
picker/save, calendar and reminder CRUD, biometrics, local-network policy,
clipboard, Files picker, opening external apps/Maps/Shortcuts, speech
synthesis, secure storage, scoped app storage, widgets, foreground/background
data refresh jobs, haptics, SF Symbols rendering, and screen wake control.

Added in this release:
- `await HTMLAppNative.capabilities()`, also `await HTMLApp.capabilities()`,
  truthfully lists implemented native methods and permission categories.
- `await HTMLAppNative.device.torch(true|false)`: requires saved-app
  Camera consent and iOS camera authorization, and a hardware torch.
- `await HTMLAppNative.device.brightness(level?)`: requires saved-app
  Display Control consent. Apps should restore the previous brightness.
- `await HTMLAppNative.motion.pedometer(days)`: reads 1–7 days of steps,
  distance and floors where supported. Requires separate saved-app Motion & Steps
  consent plus the iOS Motion & Fitness authorization dialog.

Capabilities **not** implemented or advertised as working:
HealthKit health data, HomeKit, NFC writing, Bluetooth central/peripheral,
Nearby Interaction, geofencing/background location, Apple Pay, Wallet,
CallKit/PushKit, critical alerts, push registration/server integration,
StoreKit purchases, secure enclave keys, ARKit/LiDAR, background audio,
advanced CoreMotion activity classification, barometer, advanced camera/Vision capture,
MusicKit, extensions for third-party share workflows, and Apple Intelligence
on-device model integration. Some require extra provisioned entitlements,
account/service configuration, suitable hardware, App Review scrutiny,
or iOS-version-specific APIs. Many cannot be provided safely to arbitrary
HTML content through the sandbox. They require dedicated opt-in native
handlers and real user consent before being exposed.

Do not add entitlement keys speculatively to unsigned or sideloaded builds;
capabilities must be provisioned in the signing team, and some require
Apple approval. No normal iOS application can read other apps' private
data or grant itself permissions without consent.

## Test requirements
1. Build with XcodeGen and Xcode 16.4 or 26.x; validate generated app and
   Widget extension targets plus iOS 16 deployment constraints.
2. Test voice widget → OS unlock → dictation → mockup picker → build, and
   Siri direct build separately.
3. Test large/small phone mockup fidelity and subsequent AI edits.
4. Test a 30-second/90-second hold-to-talk including transcription changes.
5. Test widget reassignments and data writes with the actual App Group signed.
6. Test red Forge Live Activity during creation, edit, cancel and app kill,
   and iOS 26 continued processing on a supported device.
7. Test denied Camera permission and torch-less hardware; test brightness restore.

Source checks are not evidence of a successful Xcode build or hardware test.
