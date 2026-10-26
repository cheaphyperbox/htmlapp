import UIKit
import UserNotifications
import Foundation

/// APNs registration is available only when the signed app has the
/// Push Notifications capability and a server can deliver messages.
@MainActor
final class HTMLAppRemotePushService {
    static let shared = HTMLAppRemotePushService()
    private var callbacks: [(Result<String, Error>) -> Void] = []
    private var requestID = UUID()

    func register(completion: @escaping (Result<String, Error>) -> Void) {
        callbacks.append(completion)
        guard callbacks.count == 1 else { return }
        let identifier = UUID()
        requestID = identifier
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            Task { @MainActor in
                guard self.requestID == identifier else { return }
                if let error {
                    self.finish(.failure(error))
                } else if !granted {
                    self.finish(.failure(NSError(domain: "HTMLAppPush", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Notifications are disabled in iOS Settings."])))
                } else {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard self.requestID == identifier, !self.callbacks.isEmpty else { return }
            self.finish(.failure(NSError(domain: "HTMLAppPush", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "APNs registration timed out. Check signing capabilities."])))
        }
    }

    func didRegister(token: Data) {
        let value = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(value, forKey: "htmlapp.apnsToken")
        finish(.success(value))
    }

    func didFail(_ error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<String, Error>) {
        requestID = UUID()
        let pending = callbacks
        callbacks.removeAll()
        pending.forEach { $0(result) }
    }
}
