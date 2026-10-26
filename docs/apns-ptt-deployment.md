# Remote notifications and Push-to-Talk deployment

HTMLApp has local notifications, custom notification sound installation, and a native `HTMLAppNative.push.register()` bridge. These are **not** a push delivery service. An Apple developer team must provision the exact signed bundle identifier with the appropriate capabilities and operate a trusted server.

## APNs setup (ordinary messaging)

1. Enable **Push Notifications** for `com.mekabrine.htmlapp` in Apple Developer Certificates, Identifiers & Profiles. For the signed build **only**, add `aps-environment` = `development` or `production` to `HTMLApp/HTMLApp.entitlements` according to its provisioning profile. The default entitlement file intentionally does *not* assume the fork can sign for APNs.
2. Rebuild and sign with a profile matching that entitlement. Unsigned sideloaded packages cannot receive ordinary APNs just by editing an Info.plist key.
3. Install the app, allow notifications, and call `const {token,appID} = await HTMLAppNative.push.register()` after an intentional user action. Deliver the token to your own authenticated backend, associated with the app ID and owning user. Device tokens can rotate.
4. Backend: sign APNs requests with the team's private `.p8` signing key and send over HTTP/2 to `api.push.apple.com`. Set `apns-topic: com.mekabrine.htmlapp` and `apns-push-type: alert`. Never embed a private signing key in HTML, JavaScript or GitHub.
5. A normal alert payload can contain `{"aps":{"alert":{"title":"New message","body":"You have a message"},"sound":"ping.caf"},"htmlAppID":"saved-app-id"}`. The sound must exist in the signed app bundle or `Library/Sounds`; audio must meet Apple's supported duration/format requirements. HTMLApp already provides a gated install-sound API. Tapping an alert must route to the corresponding saved HTML app through the notification delegate.
6. A silent background push is **best effort**: APNs throttles delivery. It cannot guarantee continuous WebView execution or user-defined JavaScript sound playback. A visible push is displayed by iOS even while the app is suspended.
7. Optional: add a Notification Service Extension target when remote messages need downloaded attachments or customized notification content. This is a separate extension, with its own provisioning and App Group constraints.

## Push-to-Talk (walkie-talkie)

A real locked-screen voice channel requires iOS 16+ PushToTalk framework, Apple's Push to Talk capability `com.apple.developer.push-to-talk`, and a provisioned notification topic. A secure relay must authenticate channel membership and relay audio, typically via WebRTC or another low-latency audio transport. The host app must manage `PTChannelManager` and implement its delegates; an HTML app can provide only the foreground user interface and opt-in channel controls. Never expose arbitrary incoming pushes as a mechanism to silently activate microphones or execute HTML JavaScript. Do not add the entitlement to the default unsigned build without a provisioning profile.

## Other iOS capability candidates

Potential future native bridges: speech recognition (must request Speech permission), heading/geofencing/always-location (additional location consent and Info.plist usage strings), VisionKit scanning, ReplayKit screen recording, media-library access, passkeys, Accessibility-safe OCR via Vision, and optional Foundation Models where supported. Restricted or team-specific capabilities include HealthKit, HomeKit, NFC, UWB, Wallet, FamilyControls, WeatherKit, and Critical Alerts. Each needs separate privacy review, Info.plist additions, bridge authorization, device tests, and where relevant entitlements or Apple approval.

## Background generations

Real user-selected audible playback can continue under iOS background-audio policy, but interruptions and suspension remain possible. The experimental silent-buffer toggle is not a reliable or App Store-safe execution guarantee. Continue using the background URLSession handoff and, where eligible, `BGContinuedProcessingTask`. Never advertise force-quit survival or guaranteed execution while locked.
