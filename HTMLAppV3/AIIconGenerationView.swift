import SwiftUI
import UIKit

struct AIIconGenerationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let app: SavedHTMLApp
    @State private var guidance = ""
    @State private var script = ""
    @State private var rendered: Data?
    @State private var working = false
    @State private var status = "Ready"
    @State private var errorMessage: String?
    @ObservedObject private var debugTrace = AIDebugTraceStore.shared
    @State private var showDebug = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 22) {
                        VStack(spacing: 8) {
                            AppIconView(app: app, size: 84)
                            Text("Current").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 8) {
                            if let rendered, let image = UIImage(data: rendered) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.secondary.opacity(0.12))
                                    .frame(width: 84, height: 84)
                                    .overlay {
                                        Image(systemName: working ? "sparkles" : "app.dashed")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            Text("AI Preview").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    TextField("e.g. simpler, blue, emphasize calculator keys", text: $guidance, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Optional Direction")
                } footer: {
                    Text("Optional. HTMLApp now infers the app's purpose, visual identity, palette, and icon concept automatically when this field is empty.")
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Label(rendered == nil ? "Generate Icon" : "Generate Another", systemImage: "sparkles")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || !AISettingsStore.configuration.isConfigured)

                    if working || status != "Ready" {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !script.isEmpty {
                    Section("Icon Script") {
                        Text(script)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Generate App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AIDebugTraceStore.shared.clear()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if debugTrace.isActive {
                        Button { showDebug = true } label: { Image(systemName: "ladybug") }
                            .accessibilityLabel("View AI debug trace")
                    }
                    Button("Use Icon") {
                        guard let rendered else { return }
                        store.setGeneratedIcon(rendered, for: app)
                        AIDebugTraceStore.shared.clear()
                        dismiss()
                    }
                    .disabled(rendered == nil || working)
                }
            }
            .sheet(isPresented: $showDebug) {
                AIDebugTraceView()
            }
            .alert("Icon Generation Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func generate() {
        working = true
        rendered = nil
        errorMessage = nil
        status = "Designing icon…"

        let config = AISettingsStore.configuration(for: .icon)
        let direction = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        let purpose = """
Generate a new icon for the existing HTMLApp named \(app.name).
\(app.summary.isEmpty ? "" : "App summary: " + app.summary)
\(direction.isEmpty ? "" : "User direction: " + direction)
"""
        AIDebugTraceStore.shared.begin(originalPrompt: purpose, config: config)
        AIDebugTraceStore.shared.append("ICON SOURCE", "App: \(app.name)\nHTML characters: \(app.html.count)")

        Task {
            var candidate = script.trimmingCharacters(in: .whitespacesAndNewlines)
            var repairReason: String?
            var lastError: Error?

            for attempt in 0..<3 {
                status = attempt == 0 ? "Designing icon…" : "Repairing icon script…"
                do {
                    candidate = try await AIHTMLAgent.generateIconScript(
                        html: app.html,
                        originalPrompt: purpose,
                        previousScript: candidate,
                        repairReason: repairReason,
                        config: config
                    ).trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !candidate.isEmpty else {
                        repairReason = "The previous response omitted the mandatory icon script. Return a complete replacement."
                        AIDebugTraceStore.shared.append("ICON ATTEMPT", "Attempt \(attempt + 1) returned an empty icon script.")
                        continue
                    }

                    if let image = await AIIconRenderer.render(script: candidate) {
                        if let qualityIssue = AIHTMLAgent.iconQualityIssue(candidate) {
                            repairReason = qualityIssue
                            AIDebugTraceStore.shared.append("ICON QUALITY", "Attempt \(attempt + 1) rendered, but was rejected: \(qualityIssue)")
                            continue
                        }
                        script = candidate
                        rendered = image
                        status = "Icon ready"
                        AIDebugTraceStore.shared.append("ICON RENDER", "Rendered and passed icon-quality checks on attempt \(attempt + 1).")
                        working = false
                        return
                    }

                    repairReason = "The previous icon script failed HTMLApp's local renderer. Repair or replace it using only supported commands."
                    AIDebugTraceStore.shared.append("ICON ATTEMPT", "Attempt \(attempt + 1) produced a script that did not render locally.")
                } catch {
                    lastError = error
                    repairReason = "The previous icon-generation request failed: \(error.localizedDescription). Return only a compact valid icon script."
                    AIDebugTraceStore.shared.append("ICON ATTEMPT", "Attempt \(attempt + 1) request failed: \(error.localizedDescription)")
                }
            }

            let fallback = AIHTMLAgent.fallbackIconScript(html: app.html, originalPrompt: purpose)
            if let image = await AIIconRenderer.render(script: fallback) {
                script = fallback
                rendered = image
                status = "Icon ready"
                AIDebugTraceStore.shared.append(
                    "ICON FALLBACK",
                    "The provider did not return a usable icon, so HTMLApp created a local purpose-aware fallback instead of failing."
                )
                working = false
                return
            }

            status = "Icon generation stopped"
            errorMessage = (lastError ?? AIGenerationError.missingIcon).localizedDescription
            working = false
        }
    }
}
