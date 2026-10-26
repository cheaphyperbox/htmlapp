import Foundation

@MainActor
enum PermissionRequestGate {
    enum Verdict { case proceed, ignore, autoDenied }
    private static var recent: [String: [TimeInterval]] = [:]
    static func check(appID: String, permission: String) -> Verdict {
        let key = appID + ":" + permission
        let now = ProcessInfo.processInfo.systemUptime
        var times = (recent[key] ?? []).filter { now - $0 < 15 }
        let repeated = times.last.map { now - $0 < 1 } ?? false
        times.append(now)
        recent[key] = times
        if times.count > 10 { return .autoDenied }
        return repeated ? .ignore : .proceed
    }
}
