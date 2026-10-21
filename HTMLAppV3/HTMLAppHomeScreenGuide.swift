import SwiftUI

/// iOS does not provide a public API to silently install a configuration profile
/// or navigate directly into VPN & Device Management. Show truthful named steps.
struct HTMLAppHomeScreenGuide: View {
    let appName: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingSteps = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 50))
                        .foregroundStyle(.tint)
                    Text("Finish adding \(appName)")
                        .font(.title2.bold())
                    Text("The Home Screen icon appears only after you approve the downloaded profile in iOS Settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if showingSteps {
                        step(1, "Open the Settings app",
                             "If you see Profile Downloaded near the top, tap that. Otherwise go to General → VPN & Device Management.")
                        step(2, "Select the \(appName) profile",
                             "Check that the profile shows the correct app name before continuing.")
                        step(3, "Tap Install",
                             "iOS may ask for your device passcode. Enter it only into the genuine iOS Settings screen.")
                        step(4, "Confirm Install again",
                             "Read the iOS confirmation, then tap Install once more if you agree.")
                        step(5, "Open \(appName) from your Home Screen",
                             "The icon should appear there when the profile installation finishes.")
                    }
                    Button(showingSteps ? "Hide instructions" : "Show me each step") {
                        withAnimation { showingSteps.toggle() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    Button("I'll finish later") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
                .padding(22)
            }
            .navigationTitle("Home Screen Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            } }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
