import SwiftUI
import AVFoundation
import Speech
import UserNotifications
import CoreLocation
import Contacts
import Photos
import EventKit

/// The user's explicit opt-in starts an OS-controlled series of prompts.
/// Choosing to begin never assumes success and does not bypass app-specific
/// HTML permissions, photo pickers, Live Activity settings, or signing.
@MainActor
final class HTMLAppFirstRunPermissionTour: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var running = false
    @Published var finished = false
    @Published var progress = "Choose whether to review iOS permissions."
    private var location: CLLocationManager?
    private var locationContinuation: CheckedContinuation<Void, Never>?

    func run() {
        guard !running else { return }
        running = true
        Task {
            progress = "1 of 8 · Notifications"
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])

            progress = "2 of 8 · Camera"
            _ = await AVCaptureDevice.requestAccess(for: .video)

            progress = "3 of 8 · Microphone"
            _ = await AVCaptureDevice.requestAccess(for: .audio)

            progress = "4 of 8 · Dictation"
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }

            progress = "5 of 8 · Location"
            await requestLocation()

            progress = "6 of 8 · Contacts and Photos"
            let contacts = CNContactStore()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                contacts.requestAccess(for: .contacts) { _, _ in continuation.resume() }
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in continuation.resume() }
            }

            progress = "7 of 8 · Calendar"
            let calendar = EKEventStore()
            if #available(iOS 17.0, *) {
                _ = try? await calendar.requestFullAccessToEvents()
            } else {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    calendar.requestAccess(to: .event) { _, _ in continuation.resume() }
                }
            }

            progress = "8 of 8 · Reminders"
            let reminders = EKEventStore()
            if #available(iOS 17.0, *) {
                _ = try? await reminders.requestFullAccessToReminders()
            } else {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    reminders.requestAccess(to: .reminder) { _, _ in continuation.resume() }
                }
            }

            progress = "Finished. iOS remembers the choices you made."
            finished = true
            running = false
        }
    }

    private func requestLocation() async {
        guard CLLocationManager.locationServicesEnabled() else { return }
        let manager = CLLocationManager()
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return }
        location = manager
        manager.delegate = self
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            locationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        locationContinuation?.resume()
        locationContinuation = nil
        manager.delegate = nil
        location = nil
    }
}

struct HTMLAppFirstRunPermissionsView: View {
    let onFinished: () -> Void
    @StateObject private var tour = HTMLAppFirstRunPermissionTour()

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "hand.raised.square.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Set up permissions?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Optional: iOS can ask now about notifications, camera, microphone, dictation, location, contacts, photos, calendar, and reminders. Choose Allow or Don't Allow for each. You can also wait until you use a feature.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if tour.running {
                ProgressView()
                Text(tour.progress)
                    .font(.subheadline.weight(.medium))
            }
            if tour.finished {
                Label("Permission review complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            if tour.finished {
                Button("Start using HTMLApp", action: onFinished)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else if !tour.running {
                Button("Ask iOS about permissions now") { tour.run() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Ask me when needed", action: onFinished)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            } else {
                Text("Respond to each iOS prompt to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("No option grants a permission automatically. Biometrics, nearby-network access, and generated-app permissions are requested only when their features are used.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
