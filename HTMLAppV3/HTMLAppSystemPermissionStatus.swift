import Foundation
import AVFoundation
import CoreLocation
import Contacts
import Photos
import UserNotifications
import CoreBluetooth
import EventKit
import LocalAuthentication
import ActivityKit

/// Non-prompting iOS authorization introspection. HTMLApp's per-app host
/// policy remains a separate decision. An "available" framework is not the
/// same as a user grant, especially for HealthKit read-only authorization.
@MainActor
enum HTMLAppSystemPermissionStatus {
    static func read(for permission: HTMLPermission) async -> String {
        switch permission {
        case .camera:
            return av(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return av(AVCaptureDevice.authorizationStatus(for: .audio))
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .notDetermined: return "not_determined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .authorizedWhenInUse: return "authorized_when_in_use"
            case .authorizedAlways: return "authorized_always"
            @unknown default: return "unknown"
            }
        case .photoLibrary:
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .notDetermined: return "not_determined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .limited: return "limited"
            case .authorized: return "authorized"
            @unknown default: return "unknown"
            }
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .notDetermined: return "not_determined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .authorized: return "authorized"
            @unknown default: return "unknown"
            }
        case .bluetooth:
            switch CBManager.authorization {
            case .notDetermined: return "not_determined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .allowedAlways: return "authorized"
            @unknown default: return "unknown"
            }
        case .notifications:
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            switch status {
            case .notDetermined: return "not_determined"
            case .denied: return "denied"
            case .authorized: return "authorized"
            case .provisional: return "provisional"
            case .ephemeral: return "ephemeral"
            @unknown default: return "unknown"
            }
        case .calendar:
            return event(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return event(EKEventStore.authorizationStatus(for: .reminder))
        case .roadData, .network, .files, .externalApps, .clipboard, .spotlight, .ai, .displayControl:
            // These host permissions have no global persistent iOS system
            // authorization state; individual interactions may still prompt.
            return "not_applicable"
        case .nfc:
            return HTMLAppNFCReader.available ? "available" : "unavailable"
        case .health:
            return HTMLAppHealthReader.available ? "per_data_type" : "unavailable"
        case .liveActivities:
            if #available(iOS 16.2, *) {
                return ActivityAuthorizationInfo().areActivitiesEnabled ? "available" : "denied"
            }
            return "unavailable"
        case .biometrics:
            var error: NSError?
            let supported = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            return supported ? "available" : "unavailable"
        default:
            // Not every framework exposes meaningful non-prompting status.
            // Never claim "authorized" merely because the host policy allows it.
            return "unknown"
        }
    }

    private static func av(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private static func event(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default:
            if #available(iOS 17.0, *) {
                if status == .fullAccess { return "authorized" }
                if status == .writeOnly { return "write_only" }
            }
            return "unknown"
        }
    }
}
