import Foundation

enum ForgeProductContract {
    static let rules = """
FORGE CORE CONTRACT:
Make the user's requested app genuinely useful on the first version, with working controls, persistence, navigation, validation, lifecycle cleanup, accessibility, iPhone safe areas and adaptive iPad layout. Do not add unnecessary features, accounts, or fabricated backend/data.
Choose a fresh visual identity for each app: distinctive palette, meaningful texture and dimensionality where useful, readable type and real product-specific layout. Never impose the same green/teal checklist, circles or flat palette on unrelated apps. Optional visual preferences guide taste, not structure.
When the app has a tab bar, its selected-tab highlight should compress, stretch toward the next tab and ease back to its normal shape; keep motion subtle, responsive and accessible. Apply restrained tactile feedback to buttons and spring-like motion to sheets/popovers, honoring reduced motion and input accessibility. Avoid static hard cuts where a meaningful transition would help.
Use documented HTMLApp/browser capabilities only; never fabricate native bridges or external data. Respect permission consent, privacy and error states.
Before returning, trace every primary interaction and storage round-trip to catch avoidable errors. Do not claim tests you did not execute.
FUNCTIONALITY FIRST: Before writing CSS, list the actual user-visible outcomes required by the request, and implement a data path and working trigger for each. No generic overview/recent-activity cards, static map-shaped boxes, placeholder buttons, or simulated results may stand in for live requested features. A polished app with an inoperative primary workflow is NOT done.
For location/search/directions apps: obtain foreground permission on a user gesture; find actual nearby destinations from a documented, browser-accessible data source; fetch a real drivable road route and steps; calculate displayed distance and requested custom ETA formula; distinguish closest by straight-line from closest by driving distance; show explicit errors, timeouts, retry and open-in-Maps fallback when a public server rejects access. Never claim a route was found without actual results.
LOADING UX: Every potentially delayed action must show an immediate, accessible, specific loading state (e.g. "Getting your location…", "Finding nearby places…", "Calculating driving route…", "Saving…", "Loading your data…"). Use role=status and aria-live=polite, progress indicator or skeleton as appropriate, disable duplicate actions, preserve previous results while refreshing, and always clear loading indicators in finally (including failure/cancellation). Keep skeletons subtle with prefers-reduced-motion handling; distinguish permission waiting from network loading. Never leave a blank map/card while work is pending: show a descriptive empty/loading/error state.
FUNCTIONAL CHECKLIST: Test the conceptual success path, deny/timeout/network failure, retry, stale/offline state, each primary CTA, state persistence and navigation. Do not present "ready" when key controls have no event handlers. Prefer simpler working implementation over an ornate unusable shell.
"""
    static let catalog = """
NO-KEY API DISCOVERY SEEDS (verify current official documentation and terms before use):
Weather/geocoding: Open-Meteo — https://open-meteo.com/en/docs — free non-commercial tier, attribution and rate limits apply.
Books: Open Library — https://openlibrary.org/developers/api — public book metadata; follow usage limits.
Public holidays: Nager.Date — https://date.nager.at/Api — country/date holiday data; verify coverage.
Currency reference exchange rates: Frankfurter — https://frankfurter.dev/ — no key; inspect timestamps/currency coverage and fair-use rate limits.
Earthquake information: USGS earthquake catalog — https://earthquake.usgs.gov/fdsnws/event/1/ — public event search; verify intended feed, timestamps and limits.
Maps & places: public Nominatim (nominatim.openstreetmap.org) is NOT allowed as a generic generated-app search/geocoder by its published policy — https://operations.osmfoundation.org/policies/nominatim/ . For nearby discovery, inspect Overpass instance rules, attribution, privacy, and alternatives instead; do not silently switch to Nominatim.
Broader directory: https://github.com/public-apis/public-apis — filter Auth column to empty/no auth, then visit the service's official docs. Directory listings are not endorsements or proof of CORS, availability, current pricing, or correctness.
"""
}
