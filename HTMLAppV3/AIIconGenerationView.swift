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
    @State private var hasStarted = false
    @State private var streamedCommands = 0
    @State private var partialIcon: Data?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 10)
                Group {
                    if working {
                        RoundedRectangle(cornerRadius: 35, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(width: 210, height: 210)
                            .overlay {
                                if let partialIcon, let preview = UIImage(data: partialIcon) {
                                    Image(uiImage: preview)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 210, height: 210)
                                        .clipShape(RoundedRectangle(cornerRadius: 35))
                                        .transition(.opacity)
                                } else {
                                    VStack(spacing: 16) {
                                        ProgressView().controlSize(.large)
                                        Image(systemName: "paintbrush.pointed.fill")
                                            .font(.system(size: 42))
                                                .foregroundStyle(.secondary)
                                    }
                                }
                            }
                    } else if let rendered, let image = UIImage(data: rendered) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 210, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                            .shadow(radius: 14, y: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 35)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 210, height: 210)
                            .overlay { Image(systemName: "app.dashed").font(.largeTitle) }
                    }
                }
                Text(working ? "Creating a new icon…" : rendered == nil ? "Preparing an icon" : "Your new icon")
                    .font(.title2.weight(.bold))
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if working {
                    ProgressView()
                    Text("The original icon remains saved until you approve this one.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if rendered != nil {
                    HStack(spacing: 10) {
                        Button("Undo") {
                            AIDebugTraceStore.shared.finish(outcome: "Icon preview discarded")
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        Button("Regenerate") { generate() }
                            .buttonStyle(.bordered)
                        Button("This Looks Good") {
                            guard let rendered else { return }
                            store.setGeneratedIcon(rendered, for: app)
                            AIDebugTraceStore.shared.finish(outcome: "Icon accepted")
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                } else if !working {
                    Button("Try Again") { generate() }
                        .buttonStyle(.borderedProminent)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .navigationTitle("Regenerate Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if debugTrace.isActive {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { showDebug = true } label: { Image(systemName: "ladybug") }
                    }
                }
            }
            .sheet(isPresented: $showDebug) { AIDebugTraceView() }
            .task {
                guard !hasStarted else { return }
                hasStarted = true
                generate()
            }
        }
    }

    private func generate() {
        working = true
        rendered = nil
        script = ""
        partialIcon = nil
        streamedCommands = 0
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
                        config: config,
                        onPartialScript: { partial in
                            guard self.working, !partial.isEmpty else { return }
                            let commands = partial.split(separator: "\n").count
                            guard commands > self.streamedCommands else { return }
                            self.streamedCommands = commands
                            self.status = "Drawing icon… \(commands) commands received"
                            if let image = await AIIconRenderer.render(script: partial) {
                                self.partialIcon = image
                            }
                        }
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
