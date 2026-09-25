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

                Section("Optional Direction") {
                    TextField("e.g. simpler, blue, emphasize calculator keys", text: $guidance, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("The AI always receives this app's complete HTML so the icon can match the app even when this field is empty.")
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Icon") {
                        guard let rendered else { return }
                        store.setGeneratedIcon(rendered, for: app)
                        dismiss()
                    }
                    .disabled(rendered == nil || working)
                }
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
        Task {
            let config = AISettingsStore.configuration
            var candidate = script
            let direction = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
            let purpose = """
Generate a new icon for the existing HTMLApp named \(app.name).
\(app.summary.isEmpty ? "" : "App summary: " + app.summary)
\(direction.isEmpty ? "" : "User direction: " + direction)
"""
            do {
                for attempt in 0..<3 {
                    status = attempt == 0 ? "Designing icon…" : "Repairing icon script…"
                    candidate = try await AIHTMLAgent.generateIconScript(
                        html: app.html,
                        originalPrompt: purpose,
                        previousScript: candidate,
                        config: config
                    )
                    if let image = await AIIconRenderer.render(script: candidate) {
                        script = candidate
                        rendered = image
                        status = "Icon ready"
                        working = false
                        return
                    }
                }
                throw AIGenerationError.missingIcon
            } catch {
                status = "Icon generation stopped"
                errorMessage = error.localizedDescription
                working = false
            }
        }
    }
}
