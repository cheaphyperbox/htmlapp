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
    let appID: String
    let profileURL: URL?
    var openInSafari: (() -> Void)? = nil
    var exportProfile: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedSafari = false
    @State private var askProfileDownloaded = false
    @State private var showRecovery = false
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
                        openedSafari = true
                        if let openInSafari { openInSafari() }
                        else if let profileURL { UIApplication.shared.open(profileURL) }
                    } label: {
                        Label("Add to Home Screen", systemImage: "safari")
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

                    DisclosureGroup("Didn't work? Other ways to install", isExpanded: $showRecovery) {
                        VStack(alignment: .leading, spacing: 14) {
                            step(1, "Try Safari again",
                                 "Tap Add to Home Screen above to restart the local server. Safari must open before the link expires.")
                            if let profileURL {
                                Button("Copy current profile link") {
                                    UIPasteboard.general.url = profileURL
                                }
                                .buttonStyle(.bordered)
                            }
                            step(2, "Save the configuration profile",
                                 "Save the profile to Files or AirDrop it to this iPhone, then open it from Files.")
                            Button("Save or share profile") { exportProfile?() }
                                .buttonStyle(.bordered)
                            step(3, "Approve from Settings",
                                 "Open Settings → General → VPN & Device Management and check Downloaded Profile. Remove an older conflicting profile first if needed.")
                            step(4, "Use Shortcuts without a profile",
                                 "Create a Shortcuts action to Open URL, paste the link below, then share the shortcut to your Home Screen.")
                            Button("Copy HTMLApp shortcut URL") {
                                var parts = URLComponents()
                                parts.scheme = "htmlapp"
                                parts.host = "open"
                                parts.queryItems = [URLQueryItem(name: "id", value: appID)]
                                if let link = parts.url { UIPasteboard.general.url = link }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }

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
            .onChange(of: scenePhase) { value in
                if value == .active && openedSafari {
                    openedSafari = false
                    askProfileDownloaded = true
                }
            }
            .alert("Did the profile download?", isPresented: $askProfileDownloaded) {
                Button("Yes") {}
                Button("No, show other methods") { showRecovery = true }
            } message: {
                Text("If it downloaded, approve the profile in Settings to finish adding the Home Screen icon.")
            }
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
