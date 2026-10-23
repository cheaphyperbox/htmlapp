# HTMLApp 1.6.10 (build 17)

## Native iOS tab bridge
HTMLApp's saved-app JavaScript API remains:
```js
const available = await HTMLAppNative.capabilities();
if (available.methods.includes("tabs.configure")) {
  HTMLAppNative.tabs.onSelect(id => renderScreen(id));
  await HTMLAppNative.tabs.configure([
    { id: "home", title: "Home", symbol: "house.fill" },
    { id: "tasks", title: "Tasks", symbol: "checkmark.circle" },
    { id: "settings", title: "Settings", symbol: "gearshape" }
  ]);
}
```
The host creates a real `UITabBarController` with system-supplied tab bar
appearance. Previously `tabs.configure` could run from WebKit before the
WebView was attached to a `UIWindow`, so no tab controller was mounted while
the bridge still claimed success. Mounting now retries briefly as the view
enters its UIKit hierarchy. The controller is embedded in its parent host,
not the WebView. Generated apps supply valid tab IDs, labels, SF Symbols and
destination event handlers; navigation content stays in the HTMLApp.

**Limitations:** the host still embeds the UIKit controller over the WebView
rather than making the WebView itself a child per tab. The iOS 26 SDK, OS
rendering, content interception, and iPad system appearance need a signed
device build and interactive verification. Existing generated HTML containing
a fake tab strip is not automatically rewritten; it must be edited to use
the host API. UIKit controls whether Liquid Glass appears, not the HTML
content or this bridge.

## First-use contextual education
After completing onboarding, users receive once-per-device, dismissible
tips (stored in UserDefaults) for first opening a saved HTMLApp, app context
menu, icon regeneration, AI edit history, nearby sharing, first Forge run,
mockup viewing, drag-to-edit microphone, active generation timeline, optional
UI polish, AI & Creation settings, attempted switching while an HTMLApp runs,
and copying a saved app URL scheme link.

Tips are short toasts rather than modal tutorials. They auto-dismiss after
seven seconds or when the close button is tapped. They can be bypassed
without disabling the feature. The saved flags are not reset after updates.

The app long-press menu now groups its actions under Everyday Usage,
Sharing, Developer, and Delete. Restore AI Edit is within Developer.
The style picker retains only regenerate and Use this look as main actions;
the separate text feedback and skip/build-now buttons were removed. The
floating drag microphone remains.

## Mockup layout and activity
The three sketches use full-height WebView previews inside rounded
phone-like surrounds, with the numbered style selector on the right.
The activity ring now calls its QA timing stage **Creating App** rather
than App tests; the underlying quality tests are not removed.

## HTMLApp launch warm-up
When the Library appears, one light, blank `WKWebView` primes a shared
`WKProcessPool`. Saved apps use that pool. This may reduce first-open
WebKit process startup latency; no time measurements have been made.
Low Power Mode skips priming to avoid unnecessary resources. The priming
WebView is released when a real app is created.

## Verification
The source changes are committed but **an Xcode build was not run** here.
Run XcodeGen, iOS builds and test suites; verify real tab selections on
iPhone and iPad iOS 26, check system glass materials, foreground deep links,
WebKit load speed, first-use toast placement over full-screen/sheet flows,
long-press category order, and generation UI.
