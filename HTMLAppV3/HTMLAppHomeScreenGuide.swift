import SwiftUI
import SafariServices
import UIKit

/// A SafariServices preview can show the profile URL inside HTMLApp, but iOS
/// may require the full Safari app to register a .mobileconfig download.
struct HTMLAppProfileSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct HTMLAppHomeScreenGuide: View {
    let appName: String
    let profileURL: URL?
    var openInSafari: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Add \(appName) to your Home Screen", systemImage: "apps.iphone")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Text("First, download the profile. Then approve it in iPhone Settings. iOS requires your approval before the icon appears.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        if let openInSafari { openInSafari() }
                        else if let profileURL { UIApplication.shared.open(profileURL) }
                    } label: {
                        Label("Continue to Safari", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    step(1, "Download the profile",
                         "Look for the profile download prompt in Safari and choose Allow. If there's no prompt, use the Open Profile in Safari button above.")
                    step(2, "Open iPhone Settings",
                         "Look for Profile Downloaded near the top. If it isn't there, open General → VPN & Device Management.")
                    step(3, "Choose the \(appName) profile",
                         "Check the displayed app name before continuing. Tap Install.")
                    step(4, "Approve in Settings",
                         "Enter your device passcode into iOS Settings if asked. Tap Install again to confirm.")
                    step(5, "Find \(appName) on your Home Screen",
                         "Go back to the Home Screen and tap the new icon.")

                    Text("HTMLApp cannot enter your passcode, approve a profile, or open the protected installation screen automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Done") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("Home Screen Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
