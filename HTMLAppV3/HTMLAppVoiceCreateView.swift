import SwiftUI

/// Lock Screen quick capture opens only after an explicit widget tap.
/// The OS may require unlocking before app microphone access is available.
struct HTMLAppVoiceCreateView: View {
    let cancel: () -> Void
    let generate: (String) -> Void
    @StateObject private var dictation = ForgeDictation()
    @State private var spokenText = ""
    @State private var started = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: dictation.recording ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.system(size: 92, weight: .ultraLight))
                .foregroundStyle(dictation.recording ? Color.red : Color.accentColor)
                .symbolEffect(.pulse, options: .repeating, value: dictation.recording)
                .accessibilityLabel(dictation.recording ? "Recording your idea" : "Microphone")
            Text("Create an app by voice")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(dictation.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextEditor(text: $spokenText)
                .frame(minHeight: 130, maxHeight: 210)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("Your spoken app idea")
            Button(dictation.recording ? "Stop Listening" : "Listen Again") {
                if dictation.recording { dictation.stop() }
                else { Task { await dictation.start() } }
            }
            .buttonStyle(.bordered)
            Spacer()
            HStack(spacing: 14) {
                Button("Cancel") {
                    dictation.stop()
                    cancel()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("Generate Now") {
                    dictation.stop()
                    generate(spokenText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            guard !started else { return }
            started = true
            Task { await dictation.start() }
        }
        .onChange(of: dictation.transcript) { spokenText = $0 }
        .onDisappear { dictation.stop() }
    }
}
