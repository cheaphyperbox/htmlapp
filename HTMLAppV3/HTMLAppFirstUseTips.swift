import SwiftUI

/// Small, nonblocking contextual teaching hints; only displayed after onboarding.
enum HTMLAppFirstUseTips {
    static let notification = Notification.Name("HTMLAppFirstUseTip")
    static func show(_ key: String, appName: String? = nil) {
        guard UserDefaults.standard.bool(forKey: "onboardingComplete") else { return }
        let storage = "htmlapp.firstUseTip.\(key)"
        guard !UserDefaults.standard.bool(forKey: storage) else { return }
        UserDefaults.standard.set(true, forKey: storage)
        NotificationCenter.default.post(name: notification, object: nil,
            userInfo: ["key": key, "appName": appName ?? "this app"])
    }

    static func message(_ key: String, appName: String) -> String? {
        switch key {
        case "open": return "To return to your Library, restart HTMLApp."
        case "context": return "The app menu is organized as Everyday Usage, Sharing, Developer, and Delete."
        case "icon": return "Your new app icon is being generated. Keep HTMLApp open while it works."
        case "restore": return "Choose the version to restore. Entries lower in the list are older."
        case "nearby": return "On the other device, tap +, choose Receive from Nearby Device, then accept the connection."
        case "firstAI": return "Forge first creates three styles. Choose your favorite, then AI builds the working app in that style."
        case "mockups": return "Try the three looks using the buttons on the right. Tap Use this look, or regenerate all three with ↻. Drag the microphone onto the preview, speak, and release to request changes."
        case "dragMic": return "Release the red microphone to start the edit, or drag it back until gray and release to cancel."
        case "generation": return "The activity circle shows time spent on each AI stage and how much text each stage produced."
        case "polish": return "UI polishing is underway. Your app is in its final stages."
        case "aiSettings": return "Set your AI API here, customize LOOK & FEEL, and select models for individual jobs in AI Specialists."
        case "switch": return "Only one HTMLApp can run at once. Choose whether to switch or keep your current app."
        case "copyLink": return "This link opens \(appName) from Shortcuts, Messages, or any app that can open a link."
        default: return nil
        }
    }
}

private struct FirstUseToastModifier: ViewModifier {
    @State private var current: String?
    @State private var nonce = UUID()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                        Text(current).font(.subheadline.weight(.medium))
                        Spacer(minLength: 0)
                        Button { self.current = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                        }.accessibilityLabel("Dismiss tip")
                    }
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .zIndex(999)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: HTMLAppFirstUseTips.notification)) { note in
                let key = note.userInfo?["key"] as? String ?? ""
                let appName = note.userInfo?["appName"] as? String ?? "this app"
                guard let message = HTMLAppFirstUseTips.message(key, appName: appName) else { return }
                let token = UUID()
                nonce = token
                withAnimation(.easeInOut(duration: 0.25)) { current = message }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    if nonce == token { withAnimation { current = nil } }
                }
            }
    }
}

extension View {
    func htmlAppFirstUseToasts() -> some View { modifier(FirstUseToastModifier()) }
}
