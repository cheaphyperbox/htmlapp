# HTMLApp 1.6.13 (build 20)

## Issue reproduced from McRoute
The user's three iPad "looks" were the same template in different colors, featuring irrelevant generic headings. The screenshot labels explicitly said "offline preview": the AI style provider had failed, so the prior deterministic fallback was displayed three times with palette-only differences.

McRoute's attached HTML did contain genuine geolocation, Overpass and OSRM network requests, ETA calculation, and widget definitions. This does **not** demonstrate that those endpoints were reachable in the running WKWebView. The debug log also showed a research model repeatedly returning an empty response; this was not verified API evidence. The map is schematic and is empty before a successful route.

## Fixes
1. Three style prompts explicitly mandate **map-first**, **action-first**, and **list-first** compositions, with different main CTA location, hierarchy, density and navigation, grounded in the actual user's app idea.
2. Offline fallback mockups now have different structural HTML: a prominent map with floating location sheet, an action-led destination screen, and a condensed directions list. Nearby/route prompts get relevant labels instead of "Your Space", "Overview" and "Recent activity".
3. The shared Forge product contract now prioritizes the working core user flow over visual polish and requires specific, accessible loading, empty, permission, retry and error states. Loading must start when work starts, prevent duplicate requests and be cleared on success or error.
4. A source-level core-workflow audit checks route/location requirements and async loading cleanup, writes findings to the debug trace, and gives the balanced QA repair stage a chance to correct missing primary functionality. This is a heuristic, **not** an end-to-end network test.

## Limits and validation
These changes improve generated outputs and heuristics, but cannot guarantee third-party routing services, CORS, data accuracy or device permissions. An offscreen WebView cannot simulate an actual drive or prove that a remote API will work. The best path for reliable in-app driving directions is a supported, documented mapping provider or future native MapKit search/route bridge.

Source-invariant checks were updated; a signed Xcode build and real device tests have **not** been run in this environment. Verify all three previews, API-provider failures, a successful location flow and the waiting/error/retry UX on iPhone and iPad.
