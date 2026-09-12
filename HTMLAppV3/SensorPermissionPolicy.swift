import Foundation

enum HTMLSensorPermissionPolicy {
    static func choice(appID: String) -> HTMLPermissionChoice {
        HTMLPermissionChoice(rawValue: UserDefaults.standard.string(forKey: key(appID)) ?? "ask") ?? .ask
    }

    static func set(_ choice: HTMLPermissionChoice, appID: String) {
        UserDefaults.standard.set(choice.rawValue, forKey: key(appID))
    }

    static func reset(appID: String) {
        UserDefaults.standard.removeObject(forKey: key(appID))
    }

    private static func key(_ appID: String) -> String { "htmlPermission.\(appID).sensors" }
}
