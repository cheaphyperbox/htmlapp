# Timer and Lock Screen refresh contracts (HTMLApp 1.6.3)

Native iOS widgets and Live Activities cannot execute an HTML app's JavaScript
while the app is suspended. Requests to refresh once per minute are not
guaranteed by WidgetKit. Prefer dates that the SwiftUI renderer can count down
from by itself.

## Countdown Live Activity

Supply the two absolute Unix timestamps **in milliseconds** on
`HTMLAppNative.liveActivities.start` and when changing deadlines:

```js
function activityDefinition() {
  return {
    id: plan.id,
    title: "Dinner Countdown",
    subtitle: "Start dinner",
    value: "Countdown",
    primaryDeadlineMs: plan.cookingAt,
    secondaryLabel: "Grandparents",
    secondaryValue: "Arrival countdown",
    secondaryDeadlineMs: plan.arrivalAt,
    systemSymbol: "timer",
    accentHex: "#FF9F0A"
  };
}
```

The supplied Dinner Countdown sample already stores both absolute timestamps in
`plan.cookingAt` and `plan.arrivalAt`. Adding these fields to its
`activityDefinition()` enables the native timer rendering. Existing Live
Activities should be ended and restarted so their state contains these fields.

## Published widgets

Set `snapshot.deadlineMs` to an absolute Unix timestamp in milliseconds
alongside readable fallback `snapshot.value`. HTMLApp's widget renderer uses
a SwiftUI timer view. Other snapshot properties still change only when WidgetKit
accepts a reload or scheduled refresh.

## Limitations

- Lock Screen and Dynamic Island time labels update via iOS timer rendering.
- Arbitrary text/data widgets cannot be forcibly updated every second.
- ActivityKit updates and WidgetKit refreshes can be delayed or throttled by iOS.
- Voice-create widget uses `htmlapp://voice-create` and opens the containing
  application. iOS may require unlocking before mic access.
- Lock Screen voice capture is intentionally initiated by the user's tap.
