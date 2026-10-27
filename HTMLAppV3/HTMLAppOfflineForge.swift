import Foundation
import Network
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Online reachability is advisory; a satisfied network path does not prove a
/// particular AI provider is reachable. Never use it to authorize cloud calls.
@MainActor
final class HTMLAppForgeConnectivity: ObservableObject {
    @Published private(set) var isOffline = false
    @Published private(set) var hasChecked = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mekabrine.htmlapp.forge-connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOffline = path.status != .satisfied
                self?.hasChecked = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

enum HTMLAppOfflineEffort: String, CaseIterable, Identifiable {
    case quick, balanced, thorough
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quick: return "Quick"
        case .balanced: return "Balanced"
        case .thorough: return "Thorough"
        }
    }
    var detail: String {
        switch self {
        case .quick: return "One attempt and a local validation pass; lower battery use."
        case .balanced: return "Compact planning and up to three targeted repairs."
        case .thorough: return "More detailed planning and up to six repairs; highest battery use."
        }
    }
    var repairLimit: Int {
        switch self {
        case .quick: return 0
        case .balanced: return 3
        case .thorough: return 6
        }
    }
}

enum HTMLAppOfflineForge {
    static var availabilityMessage: String? {
        guard #available(iOS 26.0, *) else { return "Offline Forge requires iOS 26 or later." }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible):
            return "This device does not support the Apple Intelligence language model."
        case .unavailable(.modelNotReady):
            return "The on-device Apple Intelligence language model is not ready. Check Apple Intelligence settings when online."
        case .unavailable:
            return "Apple Intelligence is unavailable. Check that it is enabled on this device."
        }
        #else
        return "This build does not include Apple's Foundation Models framework."
        #endif
    }

    enum Error: LocalizedError {
        case unavailable(String)
        case invalidResult
        case largeEdit
        case thermal
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .invalidResult: return "On-device generation could not produce a working self-contained HTML app within the selected effort limit."
            case .largeEdit: return "This existing app is too large for the on-device model's context. The original app is unchanged."
            case .thermal: return "The device is too hot for sustained on-device generation."
            }
        }
    }

    /// Runs entirely on device; does not call configured AI providers.
    @MainActor
    static func generate(
        request: String, existingHTML: String?, effort: HTMLAppOfflineEffort,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if let reason = availabilityMessage { throw Error.unavailable(reason) }
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.thermalState != .critical else { throw Error.thermal }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await generateUsingFoundationModels(
                request: request, existingHTML: existingHTML, effort: effort, progress: progress)
        }
        #endif
        throw Error.unavailable("Foundation Models is unavailable.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @MainActor
    private static func generateUsingFoundationModels(
        request: String, existingHTML: String?, effort: HTMLAppOfflineEffort,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = existingHTML ?? ""
        guard original.utf8.count <= 15_000 else { throw Error.largeEdit }
        let planning: String
        if effort == .quick {
            planning = "Use a small single-screen offline layout."
        } else {
            progress("Planning offline")
            let planner = LanguageModelSession(instructions:
                "You plan small, self-contained offline HTML apps. Give concise, practical feature and UI guidance without external resources.")
            let response = try await planner.respond(to: "Plan a tiny, working HTML/CSS/JS app in at most 160 words: " + String(trimmed.prefix(1800)))
            planning = String(response.content.prefix(1000))
        }
        try Task.checkCancellation()
        progress(existingHTML == nil ? "Generating offline" : "Editing offline")
        let coder = LanguageModelSession(instructions: """
        Return exactly one complete, self-contained HTML5 document, beginning with <!doctype html> and ending with </html>.
        Use inline CSS and JavaScript only; no CDNs, external images, fetch, external fonts or cloud APIs.
        Implement actual buttons and persistence via localStorage when appropriate.
        Make a touch-friendly, responsive mobile app. Never include Markdown fences or explanations.
        """)
        let input: String
        if original.isEmpty {
            input = "Make a useful compact app for: " + String(trimmed.prefix(1800)) + "\nPlan: " + planning
        } else {
            input = "Modify the existing HTML app and return a complete revised HTML document. Preserve all existing functionality and storage keys.\nRequested change: "
                + String(trimmed.prefix(1000)) + "\nCurrent HTML:\n" + original
        }
        var result = Self.extractHTML((try await coder.respond(to: input)).content)
        for attempt in 0...effort.repairLimit {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.thermalState != .critical else { throw Error.thermal }
            progress(attempt == 0 ? "Checking offline output" : "Repairing offline output")
            let issues = await HTMLRuntimeVerifier.verify(html: result, timeout: 5)
            if Self.isCompleteDocument(result), issues.isEmpty { return result }
            guard attempt < effort.repairLimit else { break }
            // Limit context to protect the on-device model from huge repair requests.
            let repair = LanguageModelSession(instructions:
                "Return only a corrected self-contained HTML5 document. Preserve existing app behavior, local data keys, layout and working controls. Do not use remote resources.")
            let errors = issues.prefix(4).joined(separator: "\n")
            let repairInput = "Fix this standalone HTML app. Issues: " + errors
                + "\nHTML:\n" + String(result.prefix(12_000))
            result = Self.extractHTML((try await repair.respond(to: repairInput)).content)
        }
        throw Error.invalidResult
    }
    #endif

    static func extractHTML(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.range(of: "<!doctype html", options: .caseInsensitive)
            ?? text.range(of: "<html", options: .caseInsensitive),
              let end = text.range(of: "</html>", options: [.caseInsensitive, .backwards]) else {
            return text
        }
        return String(text[start.lowerBound..<end.upperBound])
    }

    static func isCompleteDocument(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("<html") && lower.contains("<body") &&
            lower.contains("</body>") && lower.contains("</html>") &&
            lower.contains("<script") && lower.contains("</script>")
    }
}

struct HTMLAppOfflineForgeConsentView: View {
    let isEdit: Bool
    let onConfirm: (HTMLAppOfflineEffort) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("htmlapp.offlineForge.effort") private var effortRaw = HTMLAppOfflineEffort.balanced.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("You're offline", systemImage: "wifi.slash")
                        .font(.title3.bold())
                    Text("HTMLApp can try to \(isEdit ? "edit" : "generate") this app using Apple Intelligence on your device. Offline results may be worse, slower, and use more battery than cloud AI. Complex apps may not work correctly.")
                }
                Section("Generation effort") {
                    ForEach(HTMLAppOfflineEffort.allCases) { effort in
                        Button {
                            effortRaw = effort.rawValue
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(effort.title).font(.headline)
                                    Text(effort.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if effortRaw == effort.rawValue {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section {
                    Text("No prompt or app code is sent to your cloud provider in this mode. A downloaded Apple Intelligence model and an eligible device are required.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Offline Forge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not Now") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Edit Offline" : "Generate Offline") {
                        let effort = HTMLAppOfflineEffort(rawValue: effortRaw) ?? .balanced
                        dismiss()
                        onConfirm(effort)
                    }
                }
            }
        }
    }
}
