import Foundation

/// Deterministic, bounded capability inference for terse Forge instructions.
/// These are *research candidates*, not authorization or fabricated support.
struct ForgeCapabilityPlan {
    let nativeMethods: [String]
    let browserCapabilities: [String]
    let permissions: [String]
    let constraints: [String]

    var researchQueries: [String] { nativeMethods }

    var implementationBrief: String {
        """
        NATIVE API CANDIDATES (verify against the installed bridge registry):
        \(nativeMethods.joined(separator: ", "))
        BROWSER CAPABILITIES:
        \(browserCapabilities.joined(separator: ", "))
        POSSIBLE SAVED-APP PERMISSIONS (request only after user gesture):
        \(permissions.joined(separator: ", "))
        KNOWN IMPLEMENTATION CONSTRAINTS:
        \(constraints.joined(separator: " | "))
        """
    }

    static func infer(_ request: String) -> ForgeCapabilityPlan {
        let lower = request.lowercased()
        // Remove harmless articles so short prompts like "scan a receipt"
        // and "scan receipt" resolve to the same capability plan.
        let normalized = lower.replacingOccurrences(
            of: #"\b(a|an|the|my|some)\s+"#,
            with: "",
            options: .regularExpression
        )
        func mentions(_ words: [String]) -> Bool {
            words.contains { lower.contains($0) || normalized.contains($0) }
        }
        var methods = [String]()
        var browsers = [String]()
        var constraints = [String]()

        if mentions(["camera", "take photo", "photo capture", "snap picture"]) &&
            !mentions(["video record", "record video"]) {
            methods.append("camera.capturePhoto")
        }
        if mentions(["record video", "video recording", "film a video", "video capture",
                     "capture video", "shoot video"]) {
            methods.append("video.capture")
            constraints.append("Video capture needs Camera and Microphone consent and remains foreground-only")
        }
        if mentions(["voice memo", "voice note", "record audio", "audio recorder",
                     "record sound", "microphone recording", "audio clip"]) {
            methods += ["audio.record", "audio.stopRecording", "audio.play", "audio.levels"]
            constraints.append("Audio recording and playback use app-scoped M4A files; background recording is not guaranteed")
        }
        if mentions(["color picker", "choose color", "pick a color", "select a colour"]) {
            methods.append("ui.colorPicker")
        }
        if mentions(["scan document", "scan receipt", "document scan", "receipt scanner"]) {
            methods += ["documents.scan", "vision.recognizeText"]
            constraints.append("Document scanning is user-triggered and uses the camera")
        }
        if mentions(["scan qr", "qr code", "barcode"]) {
            methods += ["vision.scanCodes"]
        }
        if mentions(["recognize text", "ocr", "text from image"]) {
            methods += ["vision.recognizeText"]
        }
        if mentions(["bluetooth", "ble ", "gatt", "nearby sensor"]) {
            methods.append("bluetooth.scan")
            if mentions(["read characteristic", "gatt", "ble data", "sensor reading",
                         "notify", "subscribe", "peripheral"]) {
                methods += ["bluetooth.gattRead", "bluetooth.gattSubscribe", "bluetooth.gattStop"]
            }
            constraints.append("Bluetooth requires scanned BLE devices; no arbitrary Classic Bluetooth or background scanning")
        }
        if mentions(["location", "gps", "track route", "speedometer", "where am i",
                     "how far", "nearby", "geofence"]) {
            browsers.append("navigator.geolocation (foreground, permission-gated)")
            constraints.append("Only foreground GPS is generally available; no unrestricted background tracking")
            if mentions(["street", "address", "reverse geocod", "geocod"]) {
                methods.append("location.reverseGeocode")
            }
            if mentions(["speed limit", "posted speed"]) {
                methods.append("location.roadSpeedLimit")
                constraints.append("Mapped road limits can be unknown or inaccurate; never infer posted limits")
            }
        }
        if mentions(["map", "directions", "open in maps", "navigate to"]) {
            methods.append("externalApps.maps")
        }
        if mentions(["apple reminders", "ios reminders", "reminders list",
                     "reminder tasks", "reminders app"]) {
            methods += ["reminders.list", "reminders.create", "reminders.update"]
        } else if mentions(["remind me", "reminder", "notification", "alert me later",
                            "notify me"]) {
            methods += ["notifications.schedule", "notifications.cancel"]
            constraints.append("Schedule a native notification; do not depend on JS timers while backgrounded")
        }
        if mentions(["calendar", "schedule event", "appointment"]) {
            methods += ["calendar.events", "calendar.createEvent"]
        }
        if mentions(["healthkit", "apple health", "step count", "heart health",
                     "health data"]) {
            methods += ["health.available", "health.today"]
            constraints.append("HealthKit access is read-only and data-type-specific")
        }
        if mentions(["nfc", "ndef", "scan tag"]) {
            methods += ["nfc.available", "nfc.readNDEF"]
            if mentions(["write tag", "write nfc", "encode tag"]) { methods.append("nfc.writeText") }
        }
        if mentions(["contact picker", "choose contact", "pick contact"]) {
            methods.append("contacts.pick")
        } else if mentions(["contact list", "address book", "all contacts"]) {
            methods.append("contacts.list")
        }
        if mentions(["home screen widget", "widget", "lock screen widget"]) {
            methods += ["widgets.configure", "widgets.reload"]
            constraints.append("WidgetKit definitions require provisioned extension; widgets do not run HTML")
        }
        if mentions(["live activity", "dynamic island"]) {
            methods += ["liveActivities.start", "liveActivities.update", "liveActivities.end"]
            constraints.append("Live Activities require iOS 16.2+ and enabled system authorization")
        }
        if mentions(["shortcut", "siri", "action button"]) {
            methods.append("shortcuts.consumeAction")
            constraints.append("Generated apps can handle host-routed actions; they cannot install arbitrary App Intents")
        }
        if mentions(["spotlight", "system search"]) {
            methods += ["spotlight.enable", "spotlight.index"]
        }
        if mentions(["native api", "rest api", "http api", "api endpoint",
                     "fetch json", "connect to server"]) {
            methods.append("network.request")
            constraints.append("Native networking needs per-app consent and approval of each public HTTPS domain")
        }
        if mentions(["transcrib", "speech to text", "dictation", "voice recognition"]) {
            methods += ["speech.recognize", "speech.stopRecognizing"]
        }
        if mentions(["text to speech", "read aloud", "speak text"]) {
            methods += ["speech.speak", "speech.stop"]
        }
        if mentions(["local ai", "on-device ai", "apple intelligence"]) {
            methods += ["ai.localAvailable", "ai.localComplete"]
            constraints.append("On-device AI is hardware/iOS-dependent and may not be available")
        } else if mentions(["ai chat", "ai assistant", "generate with ai", "chatbot"]) {
            methods += ["ai.available", "ai.complete"]
            constraints.append("Cloud AI uses the user's configured provider and may transmit content")
        }
        if mentions(["background refresh", "scheduled background fetch"]) {
            methods.append("background.configure")
            constraints.append("iOS schedules BGAppRefresh opportunistically; no continuous JS execution")
        }
        if mentions(["save data", "persistent", "database", "history", "track entries",
                     "notes", "journal"]) {
            methods += ["db.put", "db.query", "db.get"]
            browsers.append("HTMLAppData.collection (when supported)")
            constraints.append("Preserve collection IDs and use idempotent migrations for schema changes")
        }
        if mentions(["export", "share file", "share recording", "backup"]) {
            methods.append("share.present")
        }

        methods = Array(Set(methods)).sorted()
        browsers = Array(Set(browsers)).sorted()
        constraints = Array(Set(constraints)).sorted()
        let permissions = Array(Set(methods.compactMap {
            ForgeAppManifest.permissionName($0)
        } + (methods.contains("video.capture") ? ["microphone"] : []))).sorted()
        return ForgeCapabilityPlan(nativeMethods: methods,
                                   browserCapabilities: browsers,
                                   permissions: permissions, constraints: constraints)
    }
}
