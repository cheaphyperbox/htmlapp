import Foundation
import SwiftUI
import UIKit

@MainActor
final class AIDebugTraceStore: ObservableObject {
    static let shared = AIDebugTraceStore()

    @Published private(set) var text = ""
    @Published private(set) var isActive = false

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("ai-generation-debug.txt")
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8), !existing.isEmpty {
            text = existing
            isActive = true
        }
    }

    func begin(originalPrompt: String, config: AIProviderConfiguration) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        text = """
HTMLApp AI Generation Debug Trace
Started: \(stamp)
API URL: \(config.apiURL)
Resolved endpoint: \(config.endpointURL()?.absoluteString ?? "invalid")
Model: \(config.model)
Compatibility: \(config.compatibility.rawValue)
Minimum request spacing: \(AISettingsStore.requestDelaySeconds) seconds

[ORIGINAL USER PROMPT]
\(originalPrompt)

"""
        isActive = true
        persist()
    }

    func append(_ section: String, _ value: String) {
        guard isActive else { return }
        text += "\n[\(section)]\n\(value)\n"
        persist()
    }

    func clear() {
        text = ""
        isActive = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

struct AIDebugTraceView: View {
    @ObservedObject var trace = AIDebugTraceStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(trace.text.isEmpty ? "No active AI generation trace." : trace.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("AI Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = trace.text
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy debug trace")

                    ShareLink(item: trace.text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share debug trace")
                }
            }
        }
    }
}
