import SwiftUI

/// Curated release notes travel with the app, without network access.
/// Add a new entry when shipping another release line; never infer changes
/// from a build number or claim an unavailable remote changelog.
enum HTMLAppReleaseNotes {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let description: String
        let symbol: String
        let tint: Color
    }

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    static var installedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    static func entries(for version: String) -> [Entry] {
        guard version == "1.2" || version.hasPrefix("1.2.") else { return [] }
        return [
            Entry(id: "forge", title: "A smarter AI creator",
                  description: "Make an app from an idea, explore different designs, and watch its progress while Forge works.",
                  symbol: "sparkles.rectangle.stack", tint: .purple),
            Entry(id: "edit", title: "Safer AI edits",
                  description: "Forge checks the code, tries to repair mistakes, and can restore the previous app if an edit fails.",
                  symbol: "wrench.and.screwdriver.fill", tint: .blue),
            Entry(id: "share", title: "Share apps more easily",
                  description: "Nearby sending and receiving have simpler screens and automatic transfer after devices connect.",
                  symbol: "iphone.gen3.radiowaves.left.and.right", tint: .mint),
            Entry(id: "icons", title: "Fresh icons and quick actions",
                  description: "Regenerate an icon with a preview, use simpler app menus, and open saved apps using Shortcuts.",
                  symbol: "app.badge", tint: .orange),
            Entry(id: "widgets", title: "More native iOS features",
                  description: "Supported apps can show Home Screen and Lock Screen widgets, Live Activities, and Dynamic Island progress.",
                  symbol: "rectangle.on.rectangle", tint: .pink),
            Entry(id: "debug", title: "Better troubleshooting",
                  description: "Developer Mode now keeps recent AI edit logs, run timings, and app diagnostics.",
                  symbol: "ladybug.fill", tint: .indigo)
        ]
    }
}

/// Presented for a newly detected installed version, or manually from Settings.
struct HTMLAppWhatsNewView: View {
    let previousVersion: String?
    let onDone: () -> Void
    private var version: String { HTMLAppReleaseNotes.installedVersion }
    private var updates: [HTMLAppReleaseNotes.Entry] { HTMLAppReleaseNotes.entries(for: version) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 86, height: 86)
                            .background(
                                LinearGradient(colors: [.indigo, .purple, .pink],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 25)
                            )
                            .padding(.bottom, 8)

                        Text(previousVersion == nil ? "What's New in HTMLApp" : "HTMLApp was updated!")
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.8)
                        Text(previousVersion.map { "You went from version \($0) to \(version)." }
                             ?? "Discover the latest features in your installed version.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("VERSION \(version) · BUILD \(HTMLAppReleaseNotes.installedBuild)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if updates.isEmpty {
                        whatsNewRow(title: "You're on version \(version)",
                                    detail: "Detailed release notes have not been published for this version.",
                                    symbol: "checkmark.seal.fill", tint: .blue)
                    } else {
                        Text("Explore the 1.2 series improvements")
                            .font(.headline)
                        ForEach(updates) { item in
                            whatsNewRow(title: item.title, detail: item.description,
                                        symbol: item.symbol, tint: item.tint)
                        }
                    }
                    Text("You can find this page again in Settings → What's New.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Continue to HTMLApp")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func whatsNewRow(title: String, detail: String,
                             symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
