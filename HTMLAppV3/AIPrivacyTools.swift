import Foundation
import UIKit
import CoreLocation
import EventKit

/// Explicit opt-in only. Every invocation checks permissions again; no
/// personal context is silently included in a Forge provider request.
enum AIPrivacyOptions {
    static func allowed(_ name: String) -> Bool {
        UserDefaults.standard.bool(forKey: "aiPrivacy." + name)
    }
    static var location: String {
        UserDefaults.standard.string(forKey: "aiPrivacy.location") ?? "off"
    }
    static var anyEnabled: Bool {
        location != "off" || ["dateTime", "device", "calendar", "reminders", "http"].contains(where: allowed)
    }
}

private final class AIHTTPRedirectDeny: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class AIPrivacyToolRunner: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationWaiter: CheckedContinuation<String, Never>?
    private var countHTTP = 0
    private let eventStore = EKEventStore()

    override init() {
        super.init()
        manager.delegate = self
    }

    private func locationResult(_ result: String) {
        guard let waiter = locationWaiter else { return }
        locationWaiter = nil
        waiter.resume(returning: result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard locationWaiter != nil else { return }
        if manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied ||
                  manager.authorizationStatus == .restricted {
            locationResult("{\"error\":\"location_permission_denied\"}")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard AIPrivacyOptions.location != "off" else {
            locationResult("{\"error\":\"disabled_by_user\"}")
            return
        }
        guard let latest = locations.last else { return }
        let precise = AIPrivacyOptions.location == "precise" && manager.accuracyAuthorization == .fullAccuracy
        let precision = precise ? 100_000.0 : 100.0
        let latitude = (latest.coordinate.latitude * precision).rounded() / precision
        let longitude = (latest.coordinate.longitude * precision).rounded() / precision
        locationResult(json([
            "latitude": latitude,
            "longitude": longitude,
            "accuracy": precise ? "precise" : "approximate"
        ]))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationResult("{\"error\":\"location_unavailable\"}")
    }

    private func readLocation() async -> String {
        guard AIPrivacyOptions.location != "off" else { return "{\"error\":\"disabled_by_user\"}" }
        guard UIApplication.shared.applicationState == .active else {
            return "{\"error\":\"unavailable_in_background\"}"
        }
        return await withCheckedContinuation { continuation in
            locationWaiter = continuation
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .notDetermined: manager.requestWhenInUseAuthorization()
            default: locationResult("{\"error\":\"location_permission_denied\"}")
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                self?.locationResult("{\"error\":\"location_timeout\"}")
            }
        }
    }

    private func readCalendar(reminders: Bool) async -> String {
        let key = reminders ? "reminders" : "calendar"
        guard AIPrivacyOptions.allowed(key) else { return "{\"error\":\"disabled_by_user\"}" }
        guard UIApplication.shared.applicationState == .active else {
            return "{\"error\":\"unavailable_in_background\"}"
        }
        let kind: EKEntityType = reminders ? .reminder : .event
        let permission: Bool
        if #available(iOS 17.0, *) {
            if reminders {
                permission = (try? await eventStore.requestFullAccessToReminders()) ?? false
            } else {
                permission = (try? await eventStore.requestFullAccessToEvents()) ?? false
            }
        } else {
            permission = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: kind) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard AIPrivacyOptions.allowed(key) else { return "{\"error\":\"disabled_by_user\"}" }
        guard AIPrivacyOptions.allowed(key) else { return "{\"error\":\"disabled_by_user\"}" }
        guard permission else { return "{\"error\":\"permission_denied\"}" }
        if reminders {
            let values: [EKReminder] = await withCheckedContinuation { continuation in
                let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: Date(),
                    ending: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                    calendars: nil)
                eventStore.fetchReminders(matching: predicate) { values in
                    continuation.resume(returning: values ?? [])
                }
            }
            return json(values.prefix(10).map { [
                "title": String($0.title.prefix(150)),
                "due": $0.dueDateComponents?.date?.description ?? ""
            ] })
        }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start,
            end: end, calendars: nil))
        return json(events.prefix(10).map { [
            "title": String(($0.title ?? "").prefix(150)),
            "start": $0.startDate.description
        ] })
    }

    private func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) else {
            return "{\"error\":\"serialization_failed\"}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func httpGet(_ raw: String) async -> String {
        guard AIPrivacyOptions.allowed("http") else { return "{\"error\":\"disabled_by_user\"}" }
        guard countHTTP < 8 else { return "{\"error\":\"http_limit\"}" }
        countHTTP += 1
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
              PublicWebBrowser.isAllowed(url) else { return "{\"error\":\"blocked_url\"}" }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 8)
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders = [:]
        let session = URLSession(configuration: configuration, delegate: AIHTTPRedirectDeny(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let finalURL = response.url, finalURL == url,
                  PublicWebBrowser.isAllowed(finalURL) else { return "{\"error\":\"http_rejected\"}" }
            var result = Data()
            for try await byte in bytes {
                if result.count >= 200_000 { return "{\"error\":\"response_too_large\"}" }
                result.append(byte)
            }
            return String(decoding: result, as: UTF8.self)
        } catch { return "{\"error\":\"request_failed\"}" }
    }

    func execute(_ name: String, args: [String: Any]) async -> String {
        let output: String
        switch name {
        case "get_location":
            output = await readLocation()
        case "get_datetime":
            guard AIPrivacyOptions.allowed("dateTime") else { return "{\"error\":\"disabled_by_user\"}" }
            output = json(["date": ISO8601DateFormatter().string(from: Date()),
                           "locale": Locale.current.identifier,
                           "timezone": TimeZone.current.identifier])
        case "get_device":
            guard AIPrivacyOptions.allowed("device") else { return "{\"error\":\"disabled_by_user\"}" }
            output = json(["model": UIDevice.current.model,
                           "system": UIDevice.current.systemVersion,
                           "appearance": UIScreen.main.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"])
        case "get_calendar":
            output = await readCalendar(reminders: false)
        case "get_reminders":
            output = await readCalendar(reminders: true)
        case "http_get":
            output = await httpGet(args["url"] as? String ?? "")
        default:
            return "{\"error\":\"unknown_tool\"}"
        }
        AIDebugTraceStore.shared.append("AI PRIVACY TOOL",
            "\(name): " + (name == "http_get" ? String((args["url"] as? String ?? "").prefix(180)) :
                (output.contains("disabled_by_user") ? "Denied by settings" : "Used with user settings")))
        return String(output.prefix(200_000))
    }

    /// Independent provider-compatible JSON tool loop. It runs before Forge
    /// coding/editing, with six steps and a strict twenty-second overall budget.
    static func research(_ prompt: String, config: AIProviderConfiguration) async -> String {
        guard AIPrivacyOptions.anyEnabled else { return "" }
        let tool = AIPrivacyToolRunner()
        let deadline = Date().addingTimeInterval(20)
        let instructions = """
        Research this HTMLApp request using tools only when actually necessary.
        Emit exactly one <tool_call>{"name":"get_datetime","args":{}}</tool_call>
        replacing the tool name and arguments for your needed tool, OR a final
        <tool_report>concise factual research report</tool_report>.
        Available tools: get_location, get_datetime, get_device, get_calendar,
        get_reminders, http_get (args: {"url":"https://public.example/path"}).
        Never ask for clipboard. No hidden tools. No hard-coded private coordinates
        in the final HTML app; the generated app must request its own runtime access.
        After any tool result, reconsider what is actually needed and finish soon.
        """
        var messages: [(String, String)] = [("user", String(prompt.prefix(1800)))]
        for _ in 0..<6 {
            if Task.isCancelled || Date() >= deadline { break }
            let raw: String
            do {
                raw = try await AIProviderClient.complete(config: config,
                    system: instructions, messages: messages,
                    timeout: min(7, max(1, deadline.timeIntervalSinceNow)),
                    maxTokens: 750, retryOnTransient: false)
            } catch { break }
            if let start = raw.range(of: "<tool_report>"),
               let end = raw.range(of: "</tool_report>") {
                return String(raw[start.upperBound..<end.lowerBound].prefix(3500))
            }
            guard let first = raw.range(of: "<tool_call>"),
                  let last = raw.range(of: "</tool_call>"),
                  let data = String(raw[first.upperBound..<last.lowerBound]).data(using: .utf8),
                  let call = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = call["name"] as? String else { break }
            let answer = await tool.execute(name, args: call["args"] as? [String: Any] ?? [:])
            messages.append(("assistant", raw))
            messages.append(("user", "<tool_result name=\"\(name)\">\(answer)</tool_result>"))
        }
        return ""
    }
}
