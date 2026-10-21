import AppIntents
import Foundation

/// These intents deliberately hand work to the visible app. Siri/Shortcuts
/// cannot silently execute untrusted generated HTML or run a paid AI request.
@available(iOS 16.2, *)
struct OpenSavedHTMLAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Saved HTML App"
    static var description = IntentDescription("Open an app you've saved in HTMLApp.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App Name", description: "The name of a saved HTML app")
    var appName: String

    func perform() async throws -> some IntentResult {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw $appName.needsValueError("Which saved app do you want to open?") }
        UserDefaults.standard.set(String(name.prefix(120)), forKey: "htmlapp.shortcut.openName")
        NotificationCenter.default.post(name: Notification.Name("HTMLAppShortcutRequested"), object: nil)
        return .result()
    }
}

@available(iOS 16.2, *)
struct CreateHTMLAppFromPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Create HTML App with AI"
    static var description = IntentDescription("Open Forge with your idea ready to review and generate.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App Idea", description: "Describe the app you'd like to create")
    var prompt: String

    func perform() async throws -> some IntentResult {
        let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { throw $prompt.needsValueError("What should the app do?") }
        UserDefaults.standard.set(String(idea.prefix(4000)), forKey: "htmlapp.shortcut.createPrompt")
        NotificationCenter.default.post(name: Notification.Name("HTMLAppShortcutRequested"), object: nil)
        return .result()
    }
}

@available(iOS 16.2, *)
struct HTMLAppSiriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSavedHTMLAppIntent(),
            phrases: [
                "Open a saved app in \(.applicationName)",
                "Launch my HTML app with \(.applicationName)"
            ],
            shortTitle: "Open HTML App",
            systemImageName: "apps.iphone"
        )
        AppShortcut(
            intent: CreateHTMLAppFromPromptIntent(),
            phrases: [
                "Create an app with \(.applicationName)",
                "Make an HTML app in \(.applicationName)"
            ],
            shortTitle: "Create with AI",
            systemImageName: "sparkles"
        )
    }
}
