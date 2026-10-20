import Foundation
import SwiftUI
import UIKit

@MainActor
final class AIDebugTraceStore: ObservableObject {
    static let shared = AIDebugTraceStore()

    @Published private(set) var text = ""
    @Published private(set) var isActive = false

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "com.mekabrine.htmlapp.ai-debug-trace", qos: .utility)
    private let maxBytes = 1_000_000
    private var secretValues: [String] = []
    private var didReachCap = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("ai-generation-debug.txt")
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8), !existing.isEmpty {
            text = String(existing.prefix(maxBytes))
            isActive = true
            didReachCap = existing.utf8.count >= maxBytes
        }
    }

    func begin(originalPrompt: String, config: AIProviderConfiguration) {
        secretValues = config.apiKey.isEmpty ? [] : [config.apiKey]
        didReachCap = false
        let stamp = ISO8601DateFormatter().string(from: Date())
        let initial = redact("""
HTMLApp AI Generation Debug Trace
Started: \(stamp)
API URL: \(config.apiURL)
Resolved endpoint: \(config.endpointURL()?.absoluteString ?? "invalid")
Model: \(config.model)
Compatibility: \(config.compatibility.rawValue)
Minimum request spacing: \(AISettingsStore.requestDelaySeconds) seconds

[ORIGINAL USER PROMPT]
\(originalPrompt)

""")
        text = String(initial.prefix(maxBytes))
        isActive = true
        let snapshot = text
        let url = fileURL
        ioQueue.async {
            try? snapshot.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func append(_ section: String, _ value: String) {
        guard isActive, !didReachCap else { return }
        let chunk = redact("\n[\(section)]\n\(value)\n")
        let currentBytes = text.utf8.count
        let remaining = max(0, maxBytes - currentBytes)
        guard remaining > 0 else {
            didReachCap = true
            return
        }

        let limitedChunk = prefixByUTF8Bytes(chunk, limit: remaining)
        text += limitedChunk
        if limitedChunk.utf8.count < chunk.utf8.count {
            didReachCap = true
        }

        let url = fileURL
        let data = Data(limitedChunk.utf8)
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

    func clear() {
        text = ""
        isActive = false
        secretValues = []
        didReachCap = false
        let url = fileURL
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
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
            let range = NSRange(value.startIndex..., in: value)
            value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "$1[REDACTED]")
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
