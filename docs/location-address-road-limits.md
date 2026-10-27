# Location, street address and road speed-limit support

## Why DashHop and similar generated apps failed

The uploaded DashHop example calls `navigator.geolocation.watchPosition` for speed/coordinates and independently POSTs public Overpass endpoints for OSM `maxspeed` tags. GPS does not provide posted road speed limits. Public Overpass endpoints may be rate-limited, unavailable, missing CORS permissions in embedded WebKit, or may return roadways with no mapped speed limit. Some road segments have no explicit `maxspeed` tag. Those cases must display *Unavailable*; never invent a speed limit.

The host already has a per-app permission-gated WebKit geolocation implementation, but previously lacked an official HTMLApp native reverse-geocoding call. This changeset introduces two native APIs to give generated apps a more dependable path and a documented fallback.

## Current address

After the saved app has received **Location** permission, use:

```js
navigator.geolocation.getCurrentPosition(async ({coords}) => {
  try {
    const address = await HTMLAppNative.location.reverseGeocode(coords.latitude, coords.longitude);
    // May be approximate, and street/houseNumber may be empty.
    console.log(address.formattedAddress, address.city);
  } catch (error) {
    console.warn('Address cannot be resolved', error);
  }
}, error => console.warn('Location denied or unavailable', error), {enableHighAccuracy: true});
```

This uses Apple's geocoding service, which may require connectivity. **Do not silently publish or upload a person's address**. Reduced-accuracy location may yield an approximate or incomplete address.

## Mapped road speed tags

```js
navigator.geolocation.getCurrentPosition(async ({coords}) => {
  try {
    const road = await HTMLAppNative.location.roadSpeedLimit(coords.latitude, coords.longitude);
    if (road.status === 'mapped') {
      console.log('Nearby OSM mapped tag:', road.speedLimit, road.unit, road.road);
    } else {
      console.log('No explicit mapped speed limit available');
    }
  } catch (error) { console.warn('Road tag lookup unavailable', error); }
}, console.error, {enableHighAccuracy: true});
```

`roadSpeedLimit` requires two separate permissions: saved-app **Location** and **Road Data Lookup**, which discloses that an approximate location goes to an OpenStreetMap Overpass server. The lookup rounds coordinates to roughly 100m, caches results for 90 seconds, and limits each app to one new query per 45 seconds. Not supported offline. An explicit tag with units such as `35 mph` or `50 km/h` is needed before a numeric limit is returned; otherwise `status` is `unknown`. Results can refer to an adjacent roadway and are **not authoritative traffic advice**. Users must follow posted signs.

## Verification

- Check iOS app per-app Location permission and iOS Settings > Privacy > Location Services > HTMLApp. Turn on Precise Location if required and approved by the user.
- Test each API in a saved app, not in preview, on an actual GPS-capable phone with internet.
- Verify that denied permission produces a rejected JS promise, no hidden network request, and a clear error UI.
- Verify that an unmapped road, rate limit, offline connection, or Apple geocoder failure shows Unavailable, not an invented address/limit.
- Existing generated apps are not automatically rewritten: they must use the new API or be edited with Forge.
- Run source invariants, JavaScript tests, Swift compile, device signing tests. Source commits do not establish a successful build.

These changes do not fix missing OSM `maxspeed` data, nor provide a guaranteed official speed-limit service. For a production turn-by-turn speed-limit app, a dedicated licensed road/speed dataset and map matching are required.
