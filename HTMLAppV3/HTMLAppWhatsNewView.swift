import SwiftUI

/// Curated release notes travel with the app, without network access.
/// Add a new entry when shipping another release line; never infer changes
/// from a build number or claim an unavailable remote changelog.
enum HTMLAppReleaseNotes {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let description: String
        let symbol: String
        let tint: Color
    }

    // Compile-time release identity. This is not computed from a possibly
    // stale IPA Info.plist or the GitHub runner's commit count.
    static let compiledVersion = "1.6.47"
    static let compiledBuild = "55"

    static var installedVersion: String { compiledVersion }
    static var installedBuild: String { compiledBuild }
    static var packagedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Missing"
    }
    static var packagedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Missing"
    }
    static var packagingMatchesCode: Bool {
        packagedVersion == compiledVersion && packagedBuild == compiledBuild
    }

    static func entries(for version: String) -> [Entry] {
        if version == "1.6.47" { return [
            Entry(id: "car-display", title: "Car display mode", description: "A compact app launcher, visible Apps exit, safe display bounds and adaptive HTML runtime for setups that already launch HTMLApp on a car screen. Enable Car display in the Library menu when your mirroring tool reports an iPhone screen. This is compatibility mode, not Apple's native CarPlay templates.", symbol: "car.fill", tint: .blue),
            Entry(id: "free-styles", title: "More creative looks", description: "Modern/professional, technical/detailed and kiddy/easy-to-use are broad directions. AI chooses the composition freely. Look choices scroll vertically above the selection controls.", symbol: "paintpalette", tint: .orange)
        ] }
        if version == "1.6.46" { return [
            Entry(id: "whisper-retry", title: "Reliable Whisper microphone", description: "Transient microphone startup failures retry automatically while the user keeps holding, without another manual attempt.", symbol: "mic", tint: .blue),
            Entry(id: "mic-recording-status", title: "Clear recording indicator", description: "The microphone turns red only after recording begins, and enlarges while held to make its state more visible.", symbol: "waveform", tint: .orange)
        ] }
        if version == "1.6.45" { return [
            Entry(id: "forge-planner", title: "Smarter Forge planning", description: "Provider-gated creative sampling and planner-specific reasoning improve design planning without changing reliable coding defaults.", symbol: "sparkles", tint: .blue),
            Entry(id: "taste-memory", title: "Optional visual taste memory", description: "Learn small style preferences from selected designs and edits when enabled, with a clear settings switch and reset option.", symbol: "paintpalette", tint: .purple),
            Entry(id: "health-history", title: "HealthKit date ranges", description: "Generated apps can request permission to inspect bounded HealthKit history with accurate missing-data states.", symbol: "heart.text.square", tint: .red),
            Entry(id: "nfc-writing", title: "NFC text writing", description: "User-confirmed writes to compatible NDEF tags now include capacity and writable-status checks.", symbol: "wave.3.right", tint: .orange),
            Entry(id: "native-media", title: "Native document and image tools", description: "VisionKit scanning, PDF page/text inspection and file-backed Core Image filters add media functions without large WebKit data messages.", symbol: "doc.viewfinder", tint: .blue),
            Entry(id: "bluetooth-gatt", title: "Bluetooth GATT controls", description: "Bounded read, confirmed write and foreground notification subscriptions for discovered BLE devices, with app-exit cleanup.", symbol: "dot.radiowaves.left.and.right", tint: .cyan),
            Entry(id: "core-haptics", title: "Custom haptics", description: "Generated apps can play bounded Core Haptics patterns on supported devices.", symbol: "hand.tap", tint: .indigo),
            Entry(id: "offline-app-ai", title: "On-device AI for saved apps", description: "Eligible iOS 26 devices can grant permission for short local Foundation Models text and JSON responses without cloud API requests.", symbol: "apple.intelligence", tint: .purple),
            Entry(id: "gamepads-pencil", title: "Gamepads and drawing", description: "Generated apps can listen to foreground game controller events and open a native PencilKit canvas with sandboxed image output.", symbol: "gamecontroller", tint: .green)
        ] }
        if version == "1.6.44" { return [Entry(id: "forge-voice-bridge", title: "Smarter Forge instructions and voice", description: "Reordered stable AI capability instructions for provider prompt caching, added punctuation and app vocabulary to voice dictation, and expanded native bridge argument checks.", symbol: "sparkles", tint: .blue)] }
        if version == "1.6.43" { return [Entry(id: "photo-bridge-js-fix", title: "Photo bridge build fix", description: "Fixed injected JavaScript syntax in the photo importer and made bridge script tests work without a browser fetch implementation.", symbol: "checkmark.shield", tint: .green)] }
        if version == "1.6.42" { return [Entry(id: "photos-import-reliability", title: "Reliable multi-photo imports", description: "Photo import now transfers originals to generated apps in bounded WebKit chunks and prefers native file representations without unnecessary conversion. Large selections no longer require one enormous bridge response.", symbol: "photo.on.rectangle", tint: .blue)] }
        if version == "1.6.41" { return [Entry(id: "photo-picker-resilience", title: "Reliable bulk photo import", description: "Native photo picks now stage files without blocking the UI and load originals on demand, preventing oversized selection callbacks.", symbol: "photo.on.rectangle.angled", tint: .blue)] }
        if version == "1.6.40" { return [Entry(id: "road-throttle", title: "Road lookup resilience", description: "Road speed lookups now return an explicit cooling-down status rather than immediate failures on repeated GPS fixes, and favor nearby roads with speed tags.", symbol: "road.lanes", tint: .blue)] }
        if version == "1.6.39" { return [Entry(id: "road-data-reliability", title: "Road data diagnostics", description: "Improved mapped road lookup failure reporting and reduced throttling after provider outages. Each new source update now increments the release identity.", symbol: "road.lanes", tint: .blue)] }
        if version == "1.6.38" { return [Entry(id: "spotlight", title: "Spotlight indexing", description: "Saved apps can request permission to index, remove, and clear their own searchable titles and summaries.", symbol: "magnifyingglass", tint: .blue)] }
        if version == "1.6.37" { return [Entry(id: "db-search-shortcuts", title: "Search documents and run Shortcuts actions", description: "Saved apps can search their local documents and consume pending named actions from Siri Shortcuts.", symbol: "magnifyingglass", tint: .blue)] }
        if version == "1.6.36" { return [Entry(id: "portable-db-shortcuts", title: "Portable app data and Shortcuts", description: "SQLite document snapshots can be bundled with portable app data, and Shortcuts can request a named saved-app action.", symbol: "square.and.arrow.up", tint: .blue)] }
        if version == "1.6.35" { return [Entry(id: "sqlite-docs", title: "Local document database", description: "Saved apps can now store, retrieve, list, count, and delete JSON documents in an isolated SQLite database.", symbol: "externaldrive", tint: .blue)] }
        if version == "1.6.34" { return [Entry(id: "vision-tools", title: "On-device image analysis", description: "Saved HTML apps can recognize text and barcodes, classify images, and detect face rectangles using Apple Vision.", symbol: "viewfinder", tint: .blue)] }
        if version == "1.6.33" { return [Entry(id: "language-tools", title: "On-device language tools", description: "Saved HTML apps can detect languages, tokenize text, analyze sentiment and extract named entities using Apple NaturalLanguage.", symbol: "text.book.closed", tint: .blue)] }
        if version == "1.6.32" { return [Entry(id: "ai-bridge", title: "AI in saved apps", description: "Opt-in per-app AI completion and classification with permission checks and request limits. Experimental compact-output preference added.", symbol: "sparkles", tint: .blue)] }
        if version == "1.6.31" { return [
            Entry(id: "location-address-road", title: "Street addresses and road data", description: "Saved apps can resolve approximate street addresses via Apple geocoding and, with separate consent, request optional OpenStreetMap road speed tags. Unavailable data is never guessed.", symbol: "mappin.and.ellipse", tint: .blue),
            Entry(id: "offline-forge", title: "Offline Forge (experimental)", description: "Eligible iOS 26 devices can use on-device Apple Intelligence for small app generation and editing after a clear effort-and-battery warning.", symbol: "wifi.slash", tint: .indigo),
            Entry(id: "storage-write-safety", title: "Safer portable storage", description: "App data writes now report disk errors instead of falsely succeeding; clearing data produces an explicit iCloud-syncable empty state.", symbol: "internaldrive", tint: .green),
            Entry(id: "storage-developer", title: "App storage inspection (experimental)", description: "The app permissions screen now offers a developer storage inspector with portable data and SQLite document removal warnings.", symbol: "externaldrive", tint: .orange),
            Entry(id: "qa-reliability", title: "AI and QA reliability fixes", description: "Improved provider endpoint normalization, native request timeouts, offscreen touch tests, and missing Health data reporting.", symbol: "checkmark.shield", tint: .green),
            Entry(id: "health-nfc-map", title: "Health, NFC and native maps (experimental)", description: "Saved apps can request read-only daily Health totals, foreground NFC NDEF scans, and a native map modal. Supported devices and signing entitlements are required.", symbol: "heart.text.square", tint: .red),
            Entry(id: "speech-aliases", title: "Speech recognition API compatibility", description: "Saved HTML apps can call speech.recognize and speech.stopRecognizing through the existing permission-controlled foreground transcription engine.", symbol: "waveform", tint: .blue),
            Entry(id: "bridge-lint", title: "Generated app API checks", description: "Runtime verification now reports unsupported native bridge method calls and Web Bluetooth requestDevice usage.", symbol: "checkmark.shield", tint: .orange),
            Entry(id: "native-routing", title: "Native bridge reliability", description: "Corrected duplicate Vision dispatch patterns and added source regression checks.", symbol: "checkmark.shield", tint: .green),
            Entry(id: "adaptive-fade", title: "Adaptive shake exit", description: "The exit fade uses the last resting phone orientation sampled every three seconds; the torch flash uses a gentler intensity.", symbol: "iphone.radiowaves.left.and.right", tint: .blue)
        ] }
        if version == "1.6.30" { return [
            Entry(id: "capability-lookup", title: "On-demand native capability research", description: "Forge can request the complete HTMLApp capability catalog or focused sections such as Bluetooth, widgets, tabs, and device information before generating or editing apps.", symbol: "books.vertical", tint: .blue)
        ] }
        if version == "1.6.29" { return [
            Entry(id: "motion-settings", title: "Custom motion settings", description: "Set the shake time and, in Developer Mode, the fade disappearance angle. Settings displays the selected values.", symbol: "slider.horizontal.3", tint: .blue)
        ] }
        if version == "1.6.28" { return [
            Entry(id: "shake-completion", title: "More reliable face-down shake", description: "Shake progress now accumulates across natural motion impulses instead of requiring uninterrupted acceleration, allowing the exit animation and flashlight cue to trigger.", symbol: "iphone.radiowaves.left.and.right", tint: .blue)
        ] }
        if version == "1.6.27" { return [
            Entry(id: "shake-regression", title: "Shake exit build validation", description: "Regression tests now protect the new fade and flashlight exit flow instead of requiring the removed legacy gesture handler.", symbol: "checkmark.shield", tint: .blue)
        ] }
        if version == "1.6.26" { return [
            Entry(id: "tab-ci", title: "Build validation for native tabs", description: "Updated the source regression check to require tab bars to remain inside their HTML app instead of appearing in editing screens.", symbol: "checkmark.shield", tint: .blue)
        ] }
        if version == "1.6.25" { return [
            Entry(id: "native-tab-isolation", title: "Native tabs stay inside apps", description: "The real native tab bar no longer mounts onto the global app screen while editing.", symbol: "rectangle.bottomthird.inset.filled", tint: .blue),
            Entry(id: "shake-transition", title: "Shake exit transition improvements", description: "A dedicated overlay window keeps the black-and-blurred fade visible while returning to the Library.", symbol: "iphone.radiowaves.left.and.right", tint: .purple),
            Entry(id: "torch", title: "Exit flashlight cue", description: "The shake-exit flashlight now targets the rear torch for a short pulse after closing an HTML app.", symbol: "flashlight.on.fill", tint: .orange)
        ] }
        if version == "1.6.24" { return [
            Entry(id: "music-source", title: "Two ways to add generation music", description: "Switch between picking an audio file from Files and downloading audio from a direct HTTPS URL. Your previous audio URL is preserved.", symbol: "music.note.list", tint: .purple),
            Entry(id: "previous-release", title: "Recent HTMLApp improvements", description: "Includes the updated face-down shake exit, AI generation controls, photo compatibility, and improved app sharing.", symbol: "sparkles", tint: .blue)
        ] }
        if version == "1.6.23" { return [
            Entry(id: "shake-exit", title: "Face-down shake exit", description: "Shake a face-down iPhone to close the running HTML app, with a flashlight cue and a black-and-blurred screen that fades as you rotate it.", symbol: "iphone.radiowaves.left.and.right", tint: .blue),
            Entry(id: "photo-compat", title: "Photo picker compatibility", description: "Selected images are easier for both new and older HTML apps to display.", symbol: "photo.on.rectangle", tint: .green),
            Entry(id: "music-files", title: "Choose generation music from Files", description: "Pick a local audio track instead of entering a URL, with clearer guidance for background generation.", symbol: "music.note", tint: .purple),
            Entry(id: "forge-controls", title: "More AI generation controls", description: "Add three original AI looks, speed up a run with Hurry Up!, undo unsaved edits and approve rare full rewrites.", symbol: "sparkles", tint: .orange),
            Entry(id: "island", title: "Generation progress in Dynamic Island", description: "See the active AI phase and progress while a Live Activity is running.", symbol: "circle.dotted.circle", tint: .mint),
            Entry(id: "sharing", title: "Organized app actions", description: "App menus group everyday actions, sharing and developer tools. Raw code exports use HTML files.", symbol: "square.and.arrow.up", tint: .indigo)
        ] }
        if version == "1.6.22" { return [
            Entry(id: "audio", title: "More dependable generation audio", description: "Music URL prefetch and safer dictation teardown reduce interruptions. Background continuity remains best-effort and depends on iOS scheduling.", symbol: "waveform", tint: .purple),
            Entry(id: "gesture", title: "Flip and shake to close", description: "An optional face-down shake returns from a saved app to Library.", symbol: "iphone.radiowaves.left.and.right", tint: .blue),
            Entry(id: "tabs", title: "Up to seven native tabs", description: "Apps can request compact UIKit tabs with badges, JavaScript selection callbacks and animations.", symbol: "square.stack", tint: .mint),
            Entry(id: "permissions", title: "Quieter permissions", description: "Repeated requests are coalesced and abusive prompts are blocked, with permissions shown in a simpler list.", symbol: "hand.raised.fill", tint: .orange)
        ] }
        if version == "1.6.21" { return [
            Entry(id: "ai-privacy", title: "AI Generation Privacy", description: "Control whether Forge may use location, date, device, calendar, reminders or public HTTPS research. All permissions default off.", symbol: "hand.raised.shield.fill", tint: .blue),
            Entry(id: "widget-actions", title: "Actionable app widgets", description: "Generated widgets can open specific screens or deliver validated action context through signed links.", symbol: "square.grid.2x2.fill", tint: .purple),
            Entry(id: "battery-thermal", title: "Battery and thermal APIs", description: "HTML apps can read charging status, battery percentage and thermal state.", symbol: "battery.100percent.bolt", tint: .green),
            Entry(id: "clean-forge", title: "Simpler creation screen", description: "Quick mode controls appear only when Manual policy is selected; debug model and UI polish status labels are hidden.", symbol: "slider.horizontal.3", tint: .orange)
        ] }
        if version == "1.6.20" { return [
            Entry(id: "background-music", title: "Longer background playback", description: "Generation Music uses primary audio playback and safer background request handoffs when audio is interrupted.", symbol: "music.note", tint: .purple),
            Entry(id: "auto-fast", title: "Automatic Quick mode", description: "Choose Manual or Automatic AI speed selection, with the option to override the recommendation.", symbol: "bolt.fill", tint: .orange),
            Entry(id: "smarter-planner", title: "Faster planning and clearer intent", description: "Forge produces shorter planning briefs and suggests an editable purpose during style selection.", symbol: "brain", tint: .blue),
            Entry(id: "smoother-library", title: "Faster opening and setup", description: "App launching avoids a synchronous Library rewrite, and Home Screen installation now offers additional recovery options.", symbol: "apps.iphone", tint: .green),
            Entry(id: "shorter-tour", title: "A shorter welcome tour", description: "Five introduction cards plus optional permissions replace the long setup walkthrough.", symbol: "hand.tap.fill", tint: .mint)
        ] }
        if version == "1.6.19" { return [
            Entry(id: "variety", title: "More original AI looks", description: "Regenerated looks use genuinely different layout archetypes, not just different colors.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "runtime-js", title: "JavaScript error assistant", description: "A warning icon in Forge preview can show runtime errors and offer to ask AI for a fix.", symbol: "exclamationmark.triangle.fill", tint: .orange)
        ] }
        if version == "1.6.18" { return [
            Entry(id: "generation-music", title: "Generation Music", description: "Play your own linked audio during Forge creation and editing, with cached playback, volume and preview controls.", symbol: "music.note", tint: .purple),
            Entry(id: "quick-performance", title: "Faster QUICK! creation", description: "QUICK! avoids optional web research and extra specialist icon regeneration.", symbol: "bolt.fill", tint: .orange),
            Entry(id: "instant-style-choices", title: "Instant style choices", description: "Three looks are immediately available while a small AI request can refine their product labels.", symbol: "paintpalette.fill", tint: .blue)
        ] }
        if version == "1.6.17" { return [
            Entry(id: "complete-style-mockups", title: "Complete AI style previews", description: "Forge gives preview models enough output budget to finish their HTML and retries incomplete specialist results using the main app model.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "preview-debug", title: "Clearer provider diagnostics", description: "AI Debug now shows response finish reasons and token usage when the provider includes them, helping identify truncated mockups.", symbol: "waveform.path.ecg.rectangle", tint: .blue)
        ] }
        if version == "1.6.16" { return [
            Entry(id: "voice-widget-resume", title: "More reliable Lock Screen voice launch", description: "Cold-start widget links reopen Forge, begin recording, then switch to hold-to-talk after you tap Stop.", symbol: "mic.fill", tint: .blue),
            Entry(id: "style-sketches", title: "More relevant AI style previews", description: "Forge requests mockups for your exact idea and system light or dark appearance. Offline sketches now show realistic product content.", symbol: "paintpalette.fill", tint: .purple),
            Entry(id: "quick-run", title: "QUICK! generation and optional skips", description: "Configure a smaller model, switch QUICK! on when creating, and skip optional planning, icon or UI polish stages.", symbol: "bolt.fill", tint: .orange),
            Entry(id: "import-url", title: "Edit HTML from a link", description: "An htmlapp://import link can download a public HTTPS HTML file into an unsaved Forge AI editing session.", symbol: "link", tint: .green),
            Entry(id: "guided-practice", title: "Hands-on Forge tutorial", description: "Practice calculator testing, dragging the mic, typing changes, and saving without using AI credits.", symbol: "hand.tap.fill", tint: .mint)
        ] }
        if version == "1.6.15" { return [
            Entry(id: "lockscreen-forge", title: "Lock Screen voice goes straight to Forge", description: "The Lock Screen microphone opens the regular Generate with AI screen and starts listening. Tap the mic again to stop, or use Generate or Cancel.", symbol: "mic.fill", tint: .blue),
            Entry(id: "whisper-handoff", title: "Voice generation waits for transcription", description: "If Whisper is selected, Forge finishes transcribing before using your spoken idea.", symbol: "waveform", tint: .purple),
            Entry(id: "welcome-action", title: "A simpler What's New screen", description: "One clear Continue to HTMLApp button closes the update notes.", symbol: "arrow.right.circle.fill", tint: .green)
        ] }
        if version == "1.6.14" { return [
            Entry(id: "faithful-look", title: "More faithful generated apps", description: "Forge checks the chosen mockup's layout as well as its colors before presenting the final app.", symbol: "square.stack", tint: .purple),
            Entry(id: "fast-location", title: "Faster location responses", description: "Recently obtained accurate locations can be reused instead of waiting for GPS again.", symbol: "location.fill", tint: .blue),
            Entry(id: "whisper-ready", title: "Whisper preloading", description: "When selected, Whisper can load on opening HTMLApp instead of at the end of recording.", symbol: "waveform", tint: .orange),
            Entry(id: "forge-questions", title: "Optional Forge questions", description: "Forge can ask a quick design question and continue with its recommended answer after 20 seconds.", symbol: "questionmark.bubble", tint: .green),
            Entry(id: "voice-drafts", title: "Voice capture and draft fixes", description: "Lock Screen Generate Now uses the captured idea, while completed drafts no longer trigger recovery.", symbol: "mic", tint: .blue)
        ] }
        if version == "1.6.13" { return [
            Entry(id: "distinct-styles", title: "Three different looks", description: "Style previews now vary layout, structure and domain-specific content, not just colors.", symbol: "square.grid.3x1", tint: .purple),
            Entry(id: "functional", title: "Better working apps", description: "Forge now audits core workflows and asks the AI for real functionality instead of decorative placeholders.", symbol: "checkmark.shield", tint: .blue),
            Entry(id: "loading-states", title: "Useful loading states", description: "Generated apps include clear loading, error, retry and empty states for delayed tasks.", symbol: "hourglass", tint: .orange)
        ] }
        if version == "1.6.12" { return [
            Entry(id: "icloud-apps", title: "iCloud app syncing", description: "Opt in to mirroring your HTMLApp Library through iCloud Drive from Settings.", symbol: "icloud", tint: .blue),
            Entry(id: "icloud-data", title: "Optional HTMLApp data syncing", description: "When iCloud app syncing is enabled, choose whether each app's portable saved data also syncs.", symbol: "externaldrive", tint: .purple)
        ] }
        if version == "1.6.11" { return [
            Entry(id: "statusbar", title: "Choose the system status bar", description: "HTMLApps show the real status bar by default; immersive apps can request to hide it.", symbol: "iphone", tint: .blue),
            Entry(id: "default-prompt", title: "Simpler AI settings", description: "Forge always uses maintained built-in instructions instead of editable system prompts.", symbol: "wand.and.stars", tint: .purple),
            Entry(id: "widget-families", title: "Complete widget sizes", description: "AI generation and edits now request all three Home Screen or Lock Screen widget sizes when widgets are appropriate.", symbol: "square.grid.2x2", tint: .green)
        ] }
        if version == "1.6.10" { return [
            Entry(id: "native-tabs-mounted", title: "More reliable native tabs", description: "The iOS tab controller waits for its HTMLApp window before mounting, with native UIKit tab destinations.", symbol: "square.split.2x1", tint: .blue),
            Entry(id: "tips", title: "Helpful first-time tips", description: "Short, dismissible hints explain Library, AI generation, gestures, sharing and editing after onboarding.", symbol: "lightbulb", tint: .orange),
            Entry(id: "phone-sketches", title: "Phone-sized look previews", description: "Generated style mockups appear inside a larger rounded phone-style preview.", symbol: "iphone", tint: .purple),
            Entry(id: "simplified-menu", title: "Organized app actions", description: "Long-press actions are grouped into Everyday Usage, Sharing, Developer and Delete.", symbol: "square.grid.2x2", tint: .indigo),
            Entry(id: "faster-opening", title: "Faster first app opening", description: "HTMLApp primes its WebKit process while the Library is open.", symbol: "bolt", tint: .green),
            Entry(id: "creating-app", title: "Clearer activity labels", description: "The AI activity chart now says Creating App instead of App Tests.", symbol: "chart.bar", tint: .green)
        ] }
        if version == "1.6.9" { return [
            Entry(id: "mockup-fast", title: "Faster style previews", description: "Mockups generate in parallel using compact HTML instead of fragile JSON, with shorter first-pass requests.", symbol: "sparkles.rectangle.stack", tint: .purple),
            Entry(id: "mockup-recovery", title: "Reliable mockup choices", description: "Each style retries independently and shows a distinct local preview if the AI provider fails.", symbol: "square.grid.3x1", tint: .blue),
            Entry(id: "discard-close", title: "Discard and close", description: "Discarding an interrupted generation closes Create with AI instead of leaving the page open.", symbol: "xmark.circle", tint: .orange)
        ] }
        if version == "1.6.8" { return [
            Entry(id: "icon-renderer", title: "Reliable AI icon rendering", description: "The icon renderer supports the AI's FILL directives and inherited colors instead of repeatedly falling back to a generic icon.", symbol: "paintpalette", tint: .purple),
            Entry(id: "glass-tabs", title: "Host-owned iOS tabs", description: "Native tab navigation now uses a UITabBarController so eligible iOS 26 devices can receive Apple's system tab appearance.", symbol: "square.split.2x1", tint: .blue),
            Entry(id: "clean-ui", title: "No fake phone chrome", description: "AI generation and style mockups avoid drawing fake status bars, notches and Dynamic Islands.", symbol: "iphone", tint: .indigo),
            Entry(id: "install-guide", title: "Simpler Home Screen installation", description: "A dedicated instructions page replaces the Safari-or-export dialog.", symbol: "apps.iphone", tint: .green),
            Entry(id: "forge-warning", title: "Generation safety reminder", description: "The creation dashboard warns you to keep HTMLApp open, and Forge's Live Activity shows a return reminder.", symbol: "exclamationmark.triangle", tint: .red),
            Entry(id: "forge-arcade", title: "Easier generation mini-game", description: "Larger hit targets, streak bonuses, haptics and restart controls make the arcade easier to play.", symbol: "gamecontroller", tint: .orange)
        ] }
        if version == "1.6.7" { return [
            Entry(id: "floating-whisper", title: "Whisper for floating microphones", description: "Mockup feedback and AI edits wait for offline speech transcription before applying changes.", symbol: "waveform", tint: .blue),
            Entry(id: "picker-buttons", title: "Visible mockup choices", description: "Three larger vertical design selectors stay visible on iPhone and iPad.", symbol: "square.grid.3x1.fill", tint: .purple),
            Entry(id: "voice-prompt", title: "Reliable voice creation", description: "Lock Screen voice prompts survive dismissal and avoid duplicate creation jobs.", symbol: "mic.fill", tint: .blue),
            Entry(id: "widgets", title: "More dependable widgets", description: "Widgets show cached shared data without waiting on network, and the Lock Screen voice icon stays visible.", symbol: "square.grid.2x2", tint: .orange),
            Entry(id: "native-tabs", title: "Native iOS tabs and gestures", description: "Generated HTMLApps can request host-rendered UIKit tabs with JavaScript navigation events.", symbol: "square.split.2x1", tint: .indigo),
            Entry(id: "nearby-bluetooth", title: "Bluetooth discovery", description: "Saved apps can request time-limited nearby BLE scans with permissions; sharing screens explain Wi-Fi and Bluetooth setup.", symbol: "antenna.radiowaves.left.and.right", tint: .blue),
            Entry(id: "practice-forge", title: "Practice with real Forge screens", description: "The onboarding calculator uses the real creation and editing interface without making AI requests or saving changes.", symbol: "plus.forwardslash.minus", tint: .green),
            Entry(id: "specialists", title: "Simpler AI settings", description: "Specialist AI choices replace the advanced model-names section; enabled specialists show green status dots.", symbol: "brain", tint: .green)
        ] }
        if version == "1.6.6" { return [
            Entry(id: "voice-looks", title: "Lock Screen voice mockups", description: "Voice-created apps respect mockup selection; three looks now generate concurrently.", symbol: "paintpalette", tint: .purple),
            Entry(id: "match-style", title: "Keep the chosen look", description: "Forge uses selected mockup HTML and CSS tokens as its visual reference, even during later AI edits.", symbol: "checkmark.seal", tint: .blue),
            Entry(id: "forge-activity", title: "Forge progress on Lock Screen", description: "A red Live Activity warns about background limitations and displays the active AI stage.", symbol: "exclamationmark.triangle.fill", tint: .red),
            Entry(id: "widget-reloads", title: "Prompt widget refresh requests", description: "Widget publication and app-data changes request targeted WidgetKit reloads.", symbol: "arrow.clockwise", tint: .orange),
            Entry(id: "stable-dictation", title: "Steadier microphone recording", description: "The create microphone stays in a fixed location during long presses and changing transcription.", symbol: "mic.fill", tint: .green),
            Entry(id: "device-tools", title: "Discover more native tools", description: "Generated apps can query supported native APIs and request flashlight, brightness, or walking-step data with consent.", symbol: "iphone", tint: .blue)
        ] }
        if version == "1.6.5" { return [
            Entry(id: "sketch-progress", title: "Live style sketch previews", description: "See each sketch appear blurred while the remaining directions generate.", symbol: "paintpalette", tint: .purple),
            Entry(id: "fix-reopen", title: "Library starts in the Library", description: "Stale AI edit checkpoints no longer auto-open an existing saved app.", symbol: "books.vertical", tint: .blue),
            Entry(id: "forge-done", title: "Generation completion feedback", description: "Get a notification away from HTMLApp or three haptics while the app is active.", symbol: "bell.badge", tint: .green)
        ] }
        if version == "1.6.4" { return [
            Entry(id: "generation-recovery", title: "Recover interrupted AI work", description: "Review an unsaved generation checkpoint after reopening HTMLApp, including elapsed work time.", symbol: "arrow.clockwise.circle", tint: .blue),
            Entry(id: "background-grace", title: "Continue when switching apps", description: "Forge requests limited background execution time and preserves work if iOS suspends it.", symbol: "moon.stars", tint: .purple)
        ] }
        if version == "1.6.3" { return [
            Entry(id: "timers", title: "Self-updating Live Activity timers", description: "Countdown Live Activities can now use native deadline-based timer labels even when HTMLApp is asleep.", symbol: "timer", tint: .orange),
            Entry(id: "voice-lock", title: "Voice create from Lock Screen", description: "A dedicated Lock Screen widget opens a voice-first AI creation screen.", symbol: "mic.fill", tint: .blue)
        ] }
        if version == "1.6.2" { return [
            Entry(id: "offline-whisper", title: "Whisper offline dictation", description: "Switch between Apple Speech and local Whisper speech recognition in Settings.", symbol: "waveform", tint: .blue),
            Entry(id: "dictation-guide", title: "Test your microphone", description: "Try Apple dictation during onboarding and choose Whisper if your words do not appear.", symbol: "mic.circle", tint: .purple)
        ] }
        if version == "1.6.1" { return [
            Entry(id: "edit-history", title: "Restore AI edits", description: "Revisit saved AI edit versions from the Library and restore the HTML you want.", symbol: "clock.arrow.circlepath", tint: .blue),
            Entry(id: "regenerate-draft", title: "Start a fresh draft", description: "Regenerate an unsaved app from its original prompt.", symbol: "arrow.clockwise", tint: .purple),
            Entry(id: "edit-summary", title: "Explain each AI edit", description: "Forge records a short description of AI changes.", symbol: "text.bubble", tint: .green),
            Entry(id: "symbols", title: "SF Symbols in HTML", description: "Generated apps can search a curated native SF Symbols catalog and render supported symbols.", symbol: "star.square", tint: .orange),
            Entry(id: "onboarding-demo", title: "Calculator tutorial", description: "Practice a simulated AI build, calculator controls, and spoken edit ideas during onboarding.", symbol: "plus.forwardslash.minus", tint: .purple)
        ] }
        if version == "1.6" || version.hasPrefix("1.6.") {
            return [
                Entry(id: "safe-library", title: "Safer saved apps",
                      description: "HTMLApp protects your Library if stored data cannot be read, preserves a damaged copy, and keeps a rolling recovery backup.",
                      symbol: "externaldrive.badge.checkmark", tint: .blue),
                Entry(id: "quick-tests", title: "Faster AI app testing",
                      description: "Forge distinguishes blocking failures from advice, fixes simple document problems locally, and limits expensive AI repair retries.",
                      symbol: "bolt.fill", tint: .orange),
                Entry(id: "qa-timeline", title: "More accurate AI work history",
                      description: "A separate AI repair segment shows where time went without counting the same HTML bytes as tests or icons.",
                      symbol: "chart.pie.fill", tint: .purple),
                Entry(id: "package-version", title: "Verified IPA versions",
                      description: "Build metadata now includes the app and widget versions, with validation of the final packaged IPA.",
                      symbol: "checkmark.shield", tint: .green)
            ]
        }

        if version == "1.5" || version.hasPrefix("1.5.") {
            return [Entry(id: "version", title: "Reliable version tracking", description: "The app and packaged IPA display the same release and build numbers, checked before packaging.", symbol: "checkmark.seal", tint: .blue)]
        }
        if version == "1.4" || version.hasPrefix("1.4.") {
            return [
                Entry(id: "verified-build", title: "Check exactly which build you're running",
                      description: "Settings now shows a hardcoded app release and the actual IPA Info.plist version side by side, including warnings if they don't match.",
                      symbol: "checkmark.shield.fill", tint: .blue),
                Entry(id: "fast-qa", title: "Faster generation and dependable testing",
                      description: "Forge runs its local app checks first and asks a separate reviewer only when concrete errors need repairing.",
                      symbol: "bolt.fill", tint: .orange),
                Entry(id: "icon-check", title: "Stop blank app icons",
                      description: "Icon rendering checks for genuinely visible artwork instead of accepting a background-only image.",
                      symbol: "app.badge.fill", tint: .purple),
                Entry(id: "style-feedback", title: "Tell Forge what to change about every mockup",
                      description: "Drag the floating microphone onto the screen to dictate feedback and regenerate all mockups around it.",
                      symbol: "mic.fill", tint: .pink)
            ]
        }
        if version == "1.3" || version.hasPrefix("1.3.") {
            return [
                Entry(id: "guided-start", title: "A guided welcome",
                      description: "A clearer, six-step tour teaches you to create, open, edit, organize, and share HTML apps. Skip any step whenever you like.",
                      symbol: "hand.wave.fill", tint: .indigo),
                Entry(id: "easy-setup", title: "Set things up as you go",
                      description: "Choose your Library layout and optionally connect your AI provider during setup. Permission requests remain your choice.",
                      symbol: "slider.horizontal.3", tint: .blue),
                Entry(id: "try-menu", title: "Learn app shortcuts",
                      description: "Try the long-press menu on a safe example so you know how to favorite, edit, move, and share apps.",
                      symbol: "hand.tap.fill", tint: .orange),
                Entry(id: "release-notes", title: "Never miss an update",
                      description: "HTMLApp remembers the last installed version and displays this What's New page when a newer version opens.",
                      symbol: "sparkles.rectangle.stack", tint: .pink),
                Entry(id: "replay", title: "Help whenever you need it",
                      description: "Replay the tutorial or reopen this changelog from Settings → Help & Updates.",
                      symbol: "questionmark.circle.fill", tint: .mint)
            ]
        }
        guard version == "1.2" || version.hasPrefix("1.2.") else { return [] }
        return [
            Entry(id: "forge", title: "A smarter AI creator",
                  description: "Make an app from an idea, explore different designs, and watch its progress while Forge works.",
                  symbol: "sparkles.rectangle.stack", tint: .purple),
            Entry(id: "edit", title: "Safer AI edits",
                  description: "Forge checks the code, tries to repair mistakes, and can restore the previous app if an edit fails.",
                  symbol: "wrench.and.screwdriver.fill", tint: .blue),
            Entry(id: "share", title: "Share apps more easily",
                  description: "Nearby sending and receiving have simpler screens and automatic transfer after devices connect.",
                  symbol: "iphone.gen3.radiowaves.left.and.right", tint: .mint),
            Entry(id: "icons", title: "Fresh icons and quick actions",
                  description: "Regenerate an icon with a preview, use simpler app menus, and open saved apps using Shortcuts.",
                  symbol: "app.badge", tint: .orange),
            Entry(id: "widgets", title: "More native iOS features",
                  description: "Supported apps can show Home Screen and Lock Screen widgets, Live Activities, and Dynamic Island progress.",
                  symbol: "rectangle.on.rectangle", tint: .pink),
            Entry(id: "debug", title: "Better troubleshooting",
                  description: "Developer Mode now keeps recent AI edit logs, run timings, and app diagnostics.",
                  symbol: "ladybug.fill", tint: .indigo)
        ]
    }
}

/// Presented for a newly detected installed version, or manually from Settings.
struct HTMLAppWhatsNewView: View {
    let previousVersion: String?
    let onDone: () -> Void
    private var version: String { HTMLAppReleaseNotes.installedVersion }
    private var updates: [HTMLAppReleaseNotes.Entry] { HTMLAppReleaseNotes.entries(for: version) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 86, height: 86)
                            .background(
                                LinearGradient(colors: [.indigo, .purple, .pink],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 25)
                            )
                            .padding(.bottom, 8)

                        Text(previousVersion == nil ? "What's New in HTMLApp" : "HTMLApp was updated!")
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.8)
                        Text(previousVersion.map { "You went from version \($0) to \(version)." }
                             ?? "Discover the latest features in your installed version.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("VERSION \(version) · BUILD \(HTMLAppReleaseNotes.installedBuild)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !HTMLAppReleaseNotes.packagingMatchesCode {
                            Label("This IPA's packaged version does not match the app code. Please update your build process.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if updates.isEmpty {
                        whatsNewRow(title: "You're on version \(version)",
                                    detail: "Detailed release notes have not been published for this version.",
                                    symbol: "checkmark.seal.fill", tint: .blue)
                    } else {
                        Text("Highlights in this version")
                            .font(.headline)
                        ForEach(updates) { item in
                            whatsNewRow(title: item.title, detail: item.description,
                                        symbol: item.symbol, tint: item.tint)
                        }
                    }
                    Text("You can find this page again in Settings → What's New.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Continue to HTMLApp")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func whatsNewRow(title: String, detail: String,
                             symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

