import Foundation
import SwiftUI
import UIKit

struct AITraceRecord: Identifiable {
    let id: String
    let createdAt: Date
    let bytes: Int
}

@MainActor
final class AIDebugTraceStore: ObservableObject {
    static let shared = AIDebugTraceStore()

    @Published private(set) var text = ""
    @Published private(set) var isActive = false
    @Published private(set) var history: [AITraceRecord] = []

    private let directory: URL
    private var fileURL: URL
    private let ioQueue = DispatchQueue(label: "com.mekabrine.htmlapp.ai-debug-trace", qos: .utility)
    private let maxBytes = 1_000_000
    private var secretValues: [String] = []
    private var didReachCap = false
    private var startedAt = Date()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base
        fileURL = base.appendingPathComponent("ai-generation-debug.txt")
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8), !existing.isEmpty {
            text = prefixByUTF8Bytes(existing, limit: maxBytes)
        }
        refreshHistory()
    }

    func begin(originalPrompt: String, config: AIProviderConfiguration) {
        if isActive { finish(outcome: "Interrupted by a new request") }
        var values = [config.apiKey, AISettingsStore.apiKey]
        for role in AIModelRole.allCases {
            values.append(AISettingsStore.specialistConfiguration(for: role).apiKey)
        }
        secretValues = Array(Set(values.filter { !$0.isEmpty }))
        didReachCap = false
        startedAt = Date()
        let name = "ai-run-\(Int(startedAt.timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).txt"
        fileURL = directory.appendingPathComponent(name)
        let stamp = ISO8601DateFormatter().string(from: startedAt)
        let initial = redact("""
HTMLApp AI Debug
Start: \(stamp)
HTMLApp version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))
iOS: \(UIDevice.current.systemVersion)
Device class: \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
API URL: \(config.apiURL)
Model: \(config.model)
API format: \(config.compatibility.rawValue)
Request spacing: \(AISettingsStore.requestDelaySeconds) seconds

[USER REQUEST]
\(originalPrompt)

""")
        text = prefixByUTF8Bytes(initial, limit: maxBytes)
        isActive = true
        let snapshot = text
        let url = fileURL
        ioQueue.async {
            try? snapshot.write(to: url, atomically: true, encoding: .utf8)
        }
        refreshHistory()
    }

    func append(_ section: String, _ value: String) {
        guard isActive, !didReachCap else { return }
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(startedAt))
        let chunk = redact("\n[\(section) +\(elapsed)]\n\(value)\n")
        let remaining = max(0, maxBytes - text.utf8.count)
        guard remaining > 0 else { didReachCap = true; return }
        let limited = prefixByUTF8Bytes(chunk, limit: remaining)
        text += limited
        if limited.utf8.count < chunk.utf8.count { didReachCap = true }

        let url = fileURL
        let data = Data(limited.utf8)
        ioQueue.async {
            guard !data.isEmpty else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func finish(outcome: String) {
        guard isActive else { return }
        append("RUN FINISHED", "\(outcome)\nElapsed: \(String(format: "%.1fs", Date().timeIntervalSince(startedAt)))")
        isActive = false
        refreshHistory()
    }

    func read(id: String) -> String {
        if fileURL.lastPathComponent == id { return text }
        guard !id.contains("/") && !id.contains("..") &&
              (id.hasPrefix("ai-run-") || id == "ai-generation-debug.txt") else { return "" }
        let url = directory.appendingPathComponent(id)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Debug log not available."
    }

    func deleteAll() {
        finish(outcome: "Log history cleared by user")
        let files = history.map { directory.appendingPathComponent($0.id) }
        ioQueue.async {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        text = ""
        secretValues = []
        history = []
        isActive = false
    }

    func clear() { finish(outcome: "Closed") }

    private func refreshHistory() {
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("ai-run-") ||
                        $0.lastPathComponent == "ai-generation-debug.txt" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return a > b
            }
        let keep = Array(urls.prefix(12))
        history = keep.map { url in
            let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return AITraceRecord(id: url.lastPathComponent,
                                 createdAt: attributes?.contentModificationDate ?? Date(),
                                 bytes: attributes?.fileSize ?? 0)
        }
        let remove = Array(urls.dropFirst(12))
        ioQueue.async { remove.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    private func redact(_ raw: String) -> String {
        var value = raw
        for secret in secretValues where !secret.isEmpty {
            value = value.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        let patterns = [
            #"(?i)(authorization\s*:\s*bearer\s+)[^\s]+"#,
            #"(?i)(x-api-key\s*:\s*)[^\s]+"#,
            #"(?i)(api[_ -]?key\s*[:=]\s*)[^\s]+"#,
            #"(?i)([?&](?:api[_-]?key|key|token|secret)=)[^&\s]+"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            value = regex.stringByReplacingMatches(
                in: value, range: NSRange(value.startIndex..., in: value),
                withTemplate: "$1[REDACTED]")
        }
        return value
    }

    private func prefixByUTF8Bytes(_ value: String, limit: Int) -> String {
        guard value.utf8.count > limit else { return value }
        var bytes = 0
        var end = value.startIndex
        for index in value.indices {
            let next = value.index(after: index)
            let count = value[index..<next].utf8.count
            if bytes + count > limit { break }
            bytes += count
            end = next
        }
        return String(value[..<end])
    }
}

struct AIDebugTraceView: View {
    @ObservedObject var trace = AIDebugTraceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = ""
    @State private var confirmDelete = false

    private var displayed: String {
        selectedID.isEmpty ? trace.text : trace.read(id: selectedID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !trace.history.isEmpty {
                    Picker("Saved run", selection: $selectedID) {
                        Text("Most recent run").tag("")
                        ForEach(trace.history) { record in
                            Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.bytes / 1024) KB")
                                .tag(record.id)
                        }
                    }
                    .padding(.horizontal)
                }
                HStack {
                    Text("Logs persist after failed edits and successful saves. Sensitive prompts may appear; review before sharing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Erase Logs", role: .destructive) { confirmDelete = true }
                        .font(.caption)
                }
                .padding(.horizontal)
                ScrollView {
                    Text(displayed.isEmpty ? "No AI debug trace yet." : displayed)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .navigationTitle("AI Debug History")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Erase all saved AI logs?", isPresented: $confirmDelete) {
                Button("Erase Saved Logs", role: .destructive) {
                    trace.deleteAll()
                    selectedID = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Logs can contain app ideas, HTML and other private data.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = displayed
                    } label: { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("Copy selected AI log")

                    ShareLink(item: displayed) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share selected AI log")
                }
            }
        }
    }
}
