import Foundation

// Lightweight Foundation-only stand-ins so the generated Swift bridge
// contracts can be tested on Linux without iOS UI frameworks.
enum HTMLPermission: String {
    case ai, spotlight, health, nfc, camera, microphone, location, roadData
    case motion, bluetooth, notifications, liveActivities, contacts, photoLibrary
    case calendar, reminders, biometrics, localNetwork, network, clipboard
    case files, externalApps, displayControl
}
struct HTMLAppDeviceAPICatalogEntry {
    let id: String
    let title: String
    let purpose: String
    let api: String
    let constraints: String
}
enum HTMLAppDeviceAPIResearch {
    static let entries: [HTMLAppDeviceAPICatalogEntry] = []
}

@main
struct NativeRegistryContractTests {
    static func main() {
        precondition(HTMLAppBridgeRegistry.protocolVersion == 2)
        precondition(HTMLAppBridgeRegistry.descriptorVersion >= 2)
        precondition(HTMLAppBridgeRegistry.methods.count >= 140)
        precondition(HTMLAppBridgeRegistry.methodSet.count ==
                     HTMLAppBridgeRegistry.methods.count)
        precondition(HTMLAppBridgeRegistry.permission(for: "audio.record") == .microphone)
        precondition(HTMLAppBridgeRegistry.permission(for: "video.capture") == .camera)
        precondition(HTMLAppBridgeRegistry.permission(for: "network.request") == .network)
        precondition(HTMLAppBridgeRegistry.permission(for: "audio.play") == nil)

        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "network.request", arguments: [:]) != nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "network.request", arguments: ["url": "https://api.example.org"]) == nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "audio.record", arguments: ["maxDuration": "five"]) != nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "audio.record", arguments: ["maxDuration": 5]) == nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "audio.play", arguments: ["url": 123]) != nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "db.put", arguments: ["collection":"notes","id":"a","document":[:]]) == nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "db.put", arguments: ["collection":"notes"]) != nil)
        precondition(HTMLAppBridgeRegistry.argumentIssue(
            method: "nonexistent.method", arguments: [:]) == nil)

        let descriptor = HTMLAppBridgeRegistry.describe("video.capture")
        precondition(descriptor?["permission"] as? String == "camera")
        precondition(descriptor?["userInitiationRecommended"] as? Bool == true)
        precondition(descriptor?["minimumIOS"] as? String == "16.0")
        let activity = HTMLAppBridgeRegistry.describe("liveActivities.start")
        precondition(activity?["minimumIOS"] as? String == "16.2")
        let network = HTMLAppBridgeRegistry.describe("network.request")
        precondition((network?["requiredArguments"] as? [String])?.contains("url") == true)
        print("Native schema-generated registry and argument tests passed.")
    }
}
