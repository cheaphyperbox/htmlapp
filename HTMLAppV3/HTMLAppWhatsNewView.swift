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

    // Compile-time release identity. This is not computed from a possibly
    // stale IPA Info.plist or the GitHub runner's commit count.
    static let compiledVersion = "1.6.3"
    static let compiledBuild = "10"

    static var installedVersion: String { compiledVersion }
    static var installedBuild: String { compiledBuild }
    static var packagedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Missing"
    }
    static var packagedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Missing"
    }
    static var packagingMatchesCode: Bool {
        packagedVersion == compiledVersion && packagedBuild == compiledBuild
    }

    static func entries(for version: String) -> [Entry] {
        if version == "1.6.3" { return [
            Entry(id: "timers", title: "Self-updating Live Activity timers", description: "Countdown Live Activities can now use native deadline-based timer labels even when HTMLApp is asleep.", symbol: "timer", tint: .orange),
            Entry(id: "voice-lock", title: "Voice create from Lock Screen", description: "A dedicated Lock Screen widget opens a voice-first AI creation screen.", symbol: "mic.fill", tint: .blue)
        ] }
        if version == "1.6.2" { return [
            Entry(id: "offline-whisper", title: "Whisper offline dictation", description: "Switch between Apple Speech and local Whisper speech recognition in Settings.", symbol: "waveform", tint: .blue),
            Entry(id: "dictation-guide", title: "Test your microphone", description: "Try Apple dictation during onboarding and choose Whisper if your words do not appear.", symbol: "mic.circle", tint: .purple)
        ] }
        if version == "1.6.1" { return [
            Entry(id: "edit-history", title: "Restore AI edits", description: "Revisit saved AI edit versions from the Library and restore the HTML you want.", symbol: "clock.arrow.circlepath", tint: .blue),
            Entry(id: "regenerate-draft", title: "Start a fresh draft", description: "Regenerate an unsaved app from its original prompt.", symbol: "arrow.clockwise", tint: .purple),
            Entry(id: "edit-summary", title: "Explain each AI edit", description: "Forge records a short description of AI changes.", symbol: "text.bubble", tint: .green),
            Entry(id: "symbols", title: "SF Symbols in HTML", description: "Generated apps can search a curated native SF Symbols catalog and render supported symbols.", symbol: "star.square", tint: .orange),
            Entry(id: "onboarding-demo", title: "Calculator tutorial", description: "Practice a simulated AI build, calculator controls, and spoken edit ideas during onboarding.", symbol: "plus.forwardslash.minus", tint: .purple)
        ] }
        if version == "1.6" || version.hasPrefix("1.6.") {
            return [
                Entry(id: "safe-library", title: "Safer saved apps",
                      description: "HTMLApp protects your Library if stored data cannot be read, preserves a damaged copy, and keeps a rolling recovery backup.",
                      symbol: "externaldrive.badge.checkmark", tint: .blue),
                Entry(id: "quick-tests", title: "Faster AI app testing",
                      description: "Forge distinguishes blocking failures from advice, fixes simple document problems locally, and limits expensive AI repair retries.",
                      symbol: "bolt.fill", tint: .orange),
                Entry(id: "qa-timeline", title: "More accurate AI work history",
                      description: "A separate AI repair segment shows where time went without counting the same HTML bytes as tests or icons.",
                      symbol: "chart.pie.fill", tint: .purple),
                Entry(id: "package-version", title: "Verified IPA versions",
                      description: "Build metadata now includes the app and widget versions, with validation of the final packaged IPA.",
                      symbol: "checkmark.shield", tint: .green)
            ]
        }

        if version == "1.5" || version.hasPrefix("1.5.") {
            return [Entry(id: "version", title: "Reliable version tracking", description: "The app and packaged IPA display the same release and build numbers, checked before packaging.", symbol: "checkmark.seal", tint: .blue)]
        }
        if version == "1.4" || version.hasPrefix("1.4.") {
            return [
                Entry(id: "verified-build", title: "Check exactly which build you're running",
                      description: "Settings now shows a hardcoded app release and the actual IPA Info.plist version side by side, including warnings if they don't match.",
                      symbol: "checkmark.shield.fill", tint: .blue),
                Entry(id: "fast-qa", title: "Faster generation and dependable testing",
                      description: "Forge runs its local app checks first and asks a separate reviewer only when concrete errors need repairing.",
                      symbol: "bolt.fill", tint: .orange),
                Entry(id: "icon-check", title: "Stop blank app icons",
                      description: "Icon rendering checks for genuinely visible artwork instead of accepting a background-only image.",
                      symbol: "app.badge.fill", tint: .purple),
                Entry(id: "style-feedback", title: "Tell Forge what to change about every mockup",
                      description: "Drag the floating microphone onto the screen to dictate feedback and regenerate all mockups around it.",
                      symbol: "mic.fill", tint: .pink)
            ]
        }
        if version == "1.3" || version.hasPrefix("1.3.") {
            return [
                Entry(id: "guided-start", title: "A guided welcome",
                      description: "A clearer, six-step tour teaches you to create, open, edit, organize, and share HTML apps. Skip any step whenever you like.",
                      symbol: "hand.wave.fill", tint: .indigo),
                Entry(id: "easy-setup", title: "Set things up as you go",
                      description: "Choose your Library layout and optionally connect your AI provider during setup. Permission requests remain your choice.",
                      symbol: "slider.horizontal.3", tint: .blue),
                Entry(id: "try-menu", title: "Learn app shortcuts",
                      description: "Try the long-press menu on a safe example so you know how to favorite, edit, move, and share apps.",
                      symbol: "hand.tap.fill", tint: .orange),
                Entry(id: "release-notes", title: "Never miss an update",
                      description: "HTMLApp remembers the last installed version and displays this What's New page when a newer version opens.",
                      symbol: "sparkles.rectangle.stack", tint: .pink),
                Entry(id: "replay", title: "Help whenever you need it",
                      description: "Replay the tutorial or reopen this changelog from Settings → Help & Updates.",
                      symbol: "questionmark.circle.fill", tint: .mint)
            ]
        }
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
                        Image(systemName: "sparkles")
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
                        if !HTMLAppReleaseNotes.packagingMatchesCode {
                            Label("This IPA's packaged version does not match the app code. Please update your build process.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if updates.isEmpty {
                        whatsNewRow(title: "You're on version \(version)",
                                    detail: "Detailed release notes have not been published for this version.",
                                    symbol: "checkmark.seal.fill", tint: .blue)
                    } else {
                        Text("Highlights in this version")
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
