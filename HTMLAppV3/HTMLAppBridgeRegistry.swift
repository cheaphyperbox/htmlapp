import Foundation

/// Enumerated native RPC surface. The consistency test checks this registry
/// against NativeAPIBridge's dispatch cases on every CI run. No inferred
/// framework capability is reported as usable merely because iOS supports it.
enum HTMLAppBridgeRegistry {
    static let protocolVersion = 2
    static let descriptorVersion = 1
    static let methods: [String] = [
        "ai.available",
        "ai.cancel",
        "ai.classify",
        "ai.complete",
        "ai.localAvailable",
        "ai.localComplete",
        "appStorage.all",
        "appStorage.clear",
        "appStorage.get",
        "appStorage.remove",
        "appStorage.set",
        "background.configure",
        "background.list",
        "background.refreshNow",
        "background.remove",
        "biometrics.authenticate",
        "bluetooth.battery",
        "bluetooth.gattRead",
        "bluetooth.gattStop",
        "bluetooth.gattSubscribe",
        "bluetooth.gattWrite",
        "bluetooth.scan",
        "bridge.cancel",
        "calendar.createEvent",
        "calendar.deleteEvent",
        "calendar.events",
        "calendar.updateEvent",
        "camera.capturePhoto",
        "capabilities.describe",
        "capabilities.list",
        "clipboard.readText",
        "clipboard.writeText",
        "contacts.create",
        "contacts.list",
        "contacts.pick",
        "db.count",
        "db.delete",
        "db.export",
        "db.get",
        "db.import",
        "db.put",
        "db.query",
        "db.search",
        "device.battery",
        "device.brightness",
        "device.info",
        "device.keepAwake",
        "device.torch",
        "documents.scan",
        "drawing.open",
        "externalApps.maps",
        "externalApps.shortcuts",
        "files.pick",
        "gamepad.list",
        "gamepad.start",
        "gamepad.stop",
        "haptics.pattern",
        "haptics.play",
        "health.available",
        "health.range",
        "health.today",
        "image.filter",
        "language.detect",
        "language.entities",
        "language.sentiment",
        "language.tokenize",
        "liveActivities.end",
        "liveActivities.list",
        "liveActivities.start",
        "liveActivities.update",
        "location.reverseGeocode",
        "location.roadSpeedLimit",
        "map.show",
        "motion.altitude",
        "motion.pedometer",
        "network.allowedDomains",
        "network.request",
        "network.revokeDomain",
        "nfc.available",
        "nfc.readNDEF",
        "nfc.writeText",
        "notifications.cancel",
        "notifications.installSound",
        "notifications.schedule",
        "pdf.inspect",
        "permissions.openSettings",
        "permissions.request",
        "permissions.status",
        "photos.pick",
        "photos.read",
        "photos.save",
        "push.register",
        "reminders.create",
        "reminders.delete",
        "reminders.list",
        "reminders.update",
        "secureStorage.get",
        "secureStorage.remove",
        "secureStorage.set",
        "share.present",
        "shortcuts.consumeAction",
        "speech.listen",
        "speech.listenStop",
        "speech.recognize",
        "speech.speak",
        "speech.stop",
        "speech.stopRecognizing",
        "spotlight.clear",
        "spotlight.enable",
        "spotlight.index",
        "spotlight.remove",
        "symbols.render",
        "symbols.search",
        "system.open",
        "ui.alert",
        "ui.datePicker",
        "ui.menu",
        "tabs.configure",
        "tabs.pulse",
        "tabs.remove",
        "tabs.select",
        "tabs.setHidden",
        "tabs.update",
        "vision.classifyImage",
        "vision.detectFaces",
        "vision.recognizeText",
        "vision.scanCodes",
        "widgets.configure",
        "widgets.list",
        "widgets.reload",
        "widgets.remove"
    ]
    static let methodSet = Set(methods)

    static func permission(for method: String) -> HTMLPermission? {
        let namespace = method.split(separator: ".").first.map(String.init) ?? ""
        switch namespace {
        case "health": return .health
        case "nfc": return .nfc
        case "camera": return .camera
        case "contacts": return .contacts
        case "photos": return .photoLibrary
        case "calendar": return .calendar
        case "reminders": return .reminders
        case "bluetooth": return .bluetooth
        case "motion": return .motion
        case "notifications", "push": return .notifications
        case "liveActivities": return .liveActivities
        case "ai": return .ai
        case "spotlight": return .spotlight
        case "clipboard": return .clipboard
        case "externalApps", "system": return .externalApps
        case "files", "documents": return .files
        case "biometrics": return .biometrics
        case "location": return method == "location.roadSpeedLimit" ? .roadData : .location
        case "background": return nil
        case "network": return .network
        default: return nil
        }
    }

    static func describe(_ method: String) -> [String: Any]? {
        guard methodSet.contains(method) else { return nil }
        let doc = HTMLAppDeviceAPIResearch.entries.first { $0.id == method }
        return [
            "method": method,
            "protocolVersion": protocolVersion,
            "available": true,
            "permission": permission(for: method)?.rawValue ?? "none",
            "title": doc?.title ?? method,
            "description": doc?.purpose ?? "Native HTMLApp operation; check runtime authorization and the current API catalog.",
            "usage": doc?.api ?? "",
            "constraints": doc?.constraints ?? "",
            "minimumIOS": "16.0",
            "cancellable": method.hasPrefix("ai.")
        ]
    }
}
