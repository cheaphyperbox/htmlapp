import Foundation

enum ForgeProductContract {
    static let rules = """
FORGE CORE CONTRACT:
Make the user's requested app genuinely useful on the first version, with working controls, persistence, navigation, validation, lifecycle cleanup, accessibility, iPhone safe areas and adaptive iPad layout. Do not add unnecessary features, accounts, or fabricated backend/data.
Choose a fresh visual identity for each app: distinctive palette, meaningful texture and dimensionality where useful, readable type and real product-specific layout. Never impose the same green/teal checklist, circles or flat palette on unrelated apps. Optional visual preferences guide taste, not structure.
When the app has a tab bar, its selected-tab highlight should compress, stretch toward the next tab and ease back to its normal shape; keep motion subtle, responsive and accessible. Apply restrained tactile feedback to buttons and spring-like motion to sheets/popovers, honoring reduced motion and input accessibility. Avoid static hard cuts where a meaningful transition would help.
Use documented HTMLApp/browser capabilities only; never fabricate native bridges or external data. Respect permission consent, privacy and error states.
Before returning, trace every primary interaction and storage round-trip to catch avoidable errors. Do not claim tests you did not execute.
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
