# Native MapKit, HealthKit and NFC additions (1.6.31 development)

These APIs are added to the saved-app native bridge and to `DeviceAPICatalog.swift`. The implementation is **not device verified**. Run the manual Xcode 26 workflow and resolve any compile/signing failures before distribution.

## Native map
```js
const status = await HTMLAppNative.map.show({
  region: {latitude: 37.7749, longitude: -122.4194, latitudeDelta: 0.04, longitudeDelta: 0.04},
  annotations: [{latitude: 37.7749, longitude: -122.4194, title: "Marker"}]
});
```
Foreground modal with up to 100 validated annotations. Requires the existing saved-app Location permission. No automatic location tracking, region-change callbacks, or item-selection callbacks are implemented yet.

## HealthKit
```js
const availability = await HTMLAppNative.health.available();
if (availability.available) {
  try {
    const daily = await HTMLAppNative.health.today("steps");
    console.log(daily.value);
  } catch (error) { console.warn("Health data unavailable or unauthorized"); }
}
```
`health.today` accepts `steps`, `distance` (meters), and `activeEnergy` (kilocalories). Reads only today's HealthKit cumulative quantity data. Saved apps need explicit Health permission and the user selects allowed data in the iOS Health authorization screen. The system may return zero if reading is denied, so the app must not interpret zero as confirmed lack of activity. Heart rate, sleep and workouts are not yet implemented. Build signing requires the HealthKit entitlement supported by the provisioning method.

## NFC NDEF
```js
const state = await HTMLAppNative.nfc.available();
if (state.available) {
  try {
    const scan = await HTMLAppNative.nfc.readNDEF();
    console.log(scan.records); // payloadBase64, type, identifier
  } catch (error) { console.warn("Tag scanning unavailable or cancelled"); }
}
```
User-initiated foreground scan, at most 32 records. It requires per-app NFC permission, a compatible device, and the NFC NDEF reader signing entitlement. Tags are not written.

## Required verification
1. `python3 scripts/test-source-invariants.py` and `node scripts/test-widget-bridge.js`
2. Generate the Xcode project and compile for generic iOS device on Xcode 26.
3. On a signed iPhone test denied/allowed native permission, HealthKit authorization and denied reads, cancellation of NFC scans, malformed latitude/longitude, modal dismissal, and saved-app resume.
4. Confirm that the provisioning method authorizes both HealthKit and NFC entitlements; TrollStore-oriented builds and ordinary provisioning are not equivalent.

## Still outstanding from the full upgrade request
Cancellable streaming AI completions, verified Foundation Models fallback, stable WKURLSchemeHandler origins with old WebKit storage migration, offline precache, full data query semantics, automated browser-flow replay, generation performance measurements/creative fingerprints, full architectural decomposition, and wider behavioral tests.
