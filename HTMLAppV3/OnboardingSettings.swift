import SwiftUI

struct OnboardingView: View {
    @Binding var complete: Bool
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @State private var step = 0
    @State private var showAISetup = false
    @State private var showForgePractice = false
    @State private var showMenuExample = false
    @AppStorage("htmlapp.dictationEngine") private var dictationEngine = "apple"
    @StateObject private var dictationTest = ForgeDictation()
    @State private var dictationTestPressed = false

    @State private var demoStage = -1
    @State private var demoEdit = ""
    @StateObject private var demoDictation = ForgeDictation()
    private let numberOfSteps = 6
    private var tutorialStep: Int { [2, 3, 7, 8, 11, 12][min(max(step, 0), 5)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<numberOfSteps, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityLabel("Onboarding page \(step + 1) of \(numberOfSteps)")
                Spacer()
                if step < numberOfSteps - 1 {
                    Button("Skip Setup") { complete = true }
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 15)
            .padding(.bottom, 12)

            Spacer().frame(height: 10)

            if step == numberOfSteps - 1 {
                VStack {
                    HTMLAppFirstRunPermissionsView(onFinished: { complete = true })
                    Button("Not Now") { complete = true }
                        .padding(.vertical, 12)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Spacer()
                            Image(systemName: symbol)
                                .font(.system(size: 56, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 118, height: 118)
                                .background(
                                    LinearGradient(colors: [.indigo, .purple, .blue],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 32)
                                )
                                .shadow(color: .indigo.opacity(0.22), radius: 16, y: 8)
                            Spacer()
                        }
                        .padding(.top, 24)

                        Text(title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(detail)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        tutorialContent
                    }
                    .frame(maxWidth: 580)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    .id(step)
                    .transition(.opacity)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 9) {
                        Button {
                            advance()
                        } label: {
                            Text(step == 0 ? "Show Me How" : "Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showForgePractice) {
            AIGenerationView(demoMode: true)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showAISetup) {
            NavigationStack {
                AIConfigurationSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showAISetup = false }
                        }
                    }
            }
        }
    }

    private var title: String {
        switch step {
        case 0: return "Describe it. Get an app."
        case 1: return "Edit anything with AI"
        case 2: return "Apps, widgets and permissions"
        case 3: return "Your library, your data"
        case 4: return "Practice and connect AI"
        default: return "Optional permissions"
        }
    }

    private var detail: String {
        switch step {
        case 0: return "Describe your idea and Forge builds a real HTML app."
        case 1: return "Test the result, ask for edits, or long-press a saved app."
        case 2: return "Add apps to Home Screen and control native access."
        case 3: return "Organize folders, share apps and keep backups."
        case 4: return "Try a working calculator, then optionally connect an AI provider."
        default: return "Choose optional iOS permissions; you can change them later."
        }
    }

    private var symbol: String {
        switch step {
        case 0: return "sparkles"
        case 1: return "hand.tap.fill"
        case 2: return "apps.iphone"
        case 3: return "square.grid.2x2.fill"
        case 4: return "plus.forwardslash.minus"
        default: return "hand.raised"
        }
    }

    @ViewBuilder
    private var tutorialContent: some View {
        switch tutorialStep {
        case 0:
            tutorialRow("1", "Create or import", "Tap + in your Library to generate with AI, import HTML, or save a website.", symbol: "plus.circle.fill", tint: .blue)
            tutorialRow("2", "Open and use", "Tap a saved app to launch it. Its files and settings remain in your Library.", symbol: "play.rectangle.fill", tint: .purple)
            tutorialRow("3", "Keep improving", "Long-press an app to edit, favorite, move, share, or add it to your Home Screen.", symbol: "hand.point.up.left.fill", tint: .orange)
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your Library layout")
                    .font(.headline)
                Picker("Library layout", selection: $libraryLayout) {
                    Label("List", systemImage: "list.bullet").tag("list")
                    Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                }
                .pickerStyle(.segmented)
                Text(libraryLayout == "grid"
                     ? "Grid displays tappable app icons on pages, like the iPhone Home Screen."
                     : "List displays apps with names and details so they're easy to find.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("You can change this later in Settings.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(19)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20))
        case 2:
            tutorialRow("1", "Open Forge", "Tap + in the Library and choose Generate with AI.", symbol: "plus.app.fill", tint: .indigo)
            tutorialRow("2", "Tell it your idea", "Type your idea or hold the microphone to speak. Explore styles if you want.", symbol: "mic.fill", tint: .pink)
            tutorialRow("3", "Save and refine", "Try your app, then save it. Long-press it and choose Edit with AI for changes.", symbol: "checkmark.circle.fill", tint: .mint)
            Button {
                showAISetup = true
            } label: {
                Label("Set Up My AI Provider (Optional)", systemImage: "key.horizontal.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case 3:
            VStack(alignment: .leading, spacing: 12) {
                Text("Try a long press")
                    .font(.headline)
                HStack(spacing: 14) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 35))
                        .foregroundStyle(.indigo)
                        .frame(width: 62, height: 62)
                        .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Example App").font(.headline)
                        Text("Press and hold this sample.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 18))
                .onLongPressGesture {
                    withAnimation { showMenuExample.toggle() }
                }
                .accessibilityHint("Press and hold to reveal an example of available app actions.")
                Button(showMenuExample ? "Hide Example Menu" : "Show Example Menu") {
                    withAnimation { showMenuExample.toggle() }
                }
                .font(.subheadline.weight(.medium))
                if showMenuExample {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Favorite · Move To · Permissions", systemImage: "star.fill")
                        Label("Edit with AI · Regenerate Icon", systemImage: "sparkles")
                        Label("Share · Add to Home Screen", systemImage: "square.and.arrow.up")
                        Label("Delete (with confirmation)", systemImage: "trash")
                    }
                    .font(.subheadline)
                    .padding(16)
                    .background(Color.accentColor.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                Text("This is just a tutorial example; it won't change your real apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case 4:
            tutorialRow("1", "Find an app", "Use Search in the Library and type the name, then tap the matching app.", symbol: "magnifyingglass", tint: .blue)
            tutorialRow("2", "Make folders", "Use More to make folders; long-press an app and choose Move To.", symbol: "folder", tint: .blue)
            tutorialRow("3", "Change layouts", "Open Settings to switch list/grid, sorting and favorites.", symbol: "square.grid.2x2", tint: .blue)
        case 5:
            tutorialRow("1", "Create without AI", "Tap + and choose Write HTML Code, Import an HTML File, or Save a Website.", symbol: "plus.circle", tint: .blue)
            tutorialRow("2", "Edit source", "Long-press an app, choose Edit Raw Code, make your changes, and save.", symbol: "chevron.left.forwardslash.chevron.right", tint: .blue)
            tutorialRow("3", "Try your app", "Tap it in the Library to launch it.", symbol: "play.fill", tint: .blue)
        case 6:
            tutorialRow("1", "Try the preview", "Tap all important controls. Make sure your data remains after reopening.", symbol: "eye", tint: .blue)
            tutorialRow("2", "Choose testing speed", "Skip runs no tests; Fast checks briefly; Balanced checks and can repair errors.", symbol: "speedometer", tint: .blue)
            tutorialRow("3", "Fix a problem", "Long-press the app, choose Edit with AI, and say which button is broken.", symbol: "wrench", tint: .blue)
        case 7:
            tutorialRow("1", "Set permissions", "Long-press an app and choose Permissions. Allow only the access it needs.", symbol: "hand.raised", tint: .blue)
            tutorialRow("2", "Use widgets", "Apps that support widgets can publish them for the iOS Home Screen widget picker.", symbol: "square.grid.2x2", tint: .blue)
            tutorialRow("3", "Explore device tools", "Some apps support notifications, reminders, widgets and sharing.", symbol: "bell", tint: .blue)
        case 8:
            tutorialRow("1", "Share nearby", "Choose Share with Nearby Devices. The receiving device chooses Receive, then accepts.", symbol: "dot.radiowaves.left.and.right", tint: .blue)
            tutorialRow("2", "Export code", "Export Raw Code sends source; a separate full Library backup can include your saved data.", symbol: "square.and.arrow.up", tint: .blue)
            tutorialRow("3", "Use Home Screen", "Long-press an app and choose Add to Home Screen, then follow the iOS setup guide.", symbol: "apps.iphone", tint: .blue)
        case 9:
            tutorialRow("1", "Find Settings", "Tap the gear to change layout and configure your AI provider.", symbol: "gearshape", tint: .blue)
            tutorialRow("2", "Read debug logs", "Developer Mode shows AI logs and timings. Review private information before sharing logs.", symbol: "ladybug", tint: .blue)
            tutorialRow("3", "Learn again", "Select Replay Tutorial in Settings whenever you need help.", symbol: "arrow.counterclockwise", tint: .blue)
        case 10:
            VStack(spacing: 16) {
                Text("1. Try Apple's dictation first").font(.headline)
                Text("Hold the microphone, speak clearly, then release. Check the words below.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Image(systemName: dictationTest.recording ? "mic.fill" : "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(dictationTest.recording ? Color.white : Color.accentColor)
                    .frame(width: 112, height: 112)
                    .background(dictationTest.recording ? Color.red : Color.accentColor.opacity(0.12),
                                in: Circle())
                    .accessibilityLabel("Hold to dictate, release to transcribe")
                    .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
                        if pressing && !dictationTestPressed {
                            dictationTestPressed = true
                            Task { await dictationTest.start() }
                        } else if !pressing && dictationTestPressed {
                            dictationTestPressed = false
                            dictationTest.stop()
                        }
                    }, perform: {})
                Text(dictationTest.status).font(.caption).foregroundStyle(.secondary)
                Text(dictationTest.transcript.isEmpty ? "Your words will appear here…" : dictationTest.transcript)
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                if dictationTest.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing appeared? Apple's speech recognition may not work on this device. Try Whisper.")
                        .font(.subheadline)
                    Button("Try Whisper Offline Instead") {
                        dictationTest.stop()
                        dictationEngine = "whisper"
                        dictationTest.transcript = ""
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("Words appeared! You can keep this dictation engine or try the other one.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Picker("Dictation engine", selection: $dictationEngine) {
                    Text("Apple").tag("apple")
                    Text("Whisper Offline").tag("whisper")
                }
                .pickerStyle(.segmented)
                Text("Whisper downloads a model on first use. No account, API key, or speech-recognition charge is required. Audio stays on your device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case 11:
            VStack(alignment: .leading, spacing: 12) {
                Text("Try Forge yourself with a working calculator — no AI credits required.")
                    .font(.headline)
                tutorialRow("1", "Generate", "Edit the sample prompt and tap Make My App. Watch the fake build progress.", symbol: "sparkles", tint: .blue)
                tutorialRow("2", "Test", "Tap the calculator's real buttons. Try 7 + 3 = before making changes.", symbol: "hand.tap", tint: .purple)
                tutorialRow("3", "Drag the mic", "Drag the floating microphone fully onto the screen, speak while holding, then release. Tapping it opens the typed edit option.", symbol: "mic.fill", tint: .orange)
                tutorialRow("4", "Type an edit", "In the edit field, type something like ‘Make the buttons purple’ and tap Apply Change.", symbol: "pencil", tint: .mint)
                tutorialRow("5", "Save", "Tap Save App. In this lesson it simulates saving without changing your Library.", symbol: "square.and.arrow.down", tint: .green)
                Text("A practice edit changes the preview locally. Real Forge uses your configured AI provider and can save the result to your Library.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Start Hands-On Forge Practice") { showForgePractice = true }
                    .buttonStyle(.borderedProminent)
                Button("Connect AI Provider (Optional)") { showAISetup = true }
                    .buttonStyle(.bordered)
            }
        default:
            tutorialRow("1", "Send to a friend", "Open Share with Nearby Devices on the sending device. The other device chooses Receive. Accept the connection and the app imports automatically.", symbol: "dot.radiowaves.left.and.right", tint: .blue)
            tutorialRow("2", "Add to Home Screen", "Long-press an app and choose Add to Home Screen. HTMLApp shows the steps to approve its profile in iOS Settings.", symbol: "apps.iphone", tint: .orange)
            tutorialRow("3", "Find more options", "In Settings, you can choose a layout, manage your AI connection, and replay this tutorial.", symbol: "gearshape.fill", tint: .purple)
        }
    }

    private func tutorialRow(_ number: String, _ heading: String, _ explanation: String,
                             symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(heading)").font(.headline)
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private func startCalculatorDemo() {
        demoStage = 0
        Task {
            // 8 visible phases, approximately 40 seconds total.
            for stage in 1...8 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                demoStage = stage
            }
        }
    }

    static let calculatorDemoHTML = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>body{font:20px -apple-system;margin:0;padding:16px;background:#f4f4f7;color:#17171a}
    #screen{text-align:right;font-size:30px;background:white;border-radius:10px;padding:12px;margin-bottom:10px}
    main{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
    button{padding:16px 2px;border:0;border-radius:12px;background:white;font:inherit}
    button:last-child{background:#3378ed;color:white}</style></head><body>
    <div id="screen">0</div><main>
    <button>7</button><button>8</button><button>9</button><button>÷</button>
    <button>4</button><button>5</button><button>6</button><button>×</button>
    <button>1</button><button>2</button><button>3</button><button>−</button>
    <button>C</button><button>0</button><button>+</button><button>=</button>
    </main><script>
    let a=null,op=null,input="0";
    const screen=document.querySelector("#screen");
    document.querySelector("main").addEventListener("click",e=>{
      if(e.target.tagName!=="BUTTON")return;
      const t=e.target.textContent;
      if(/^\\d$/.test(t)){input=input==="0"?t:input+t;}
      else if(t==="C"){a=null;op=null;input="0";}
      else if(t==="="&&op&&a!==null){
        const b=Number(input);
        const result=op==="+"?a+b:op==="−"?a-b:op==="×"?a*b:b===0?"Error":a/b;
        input=String(result);a=null;op=null;
      }else if(["+","−","×","÷"].includes(t)){a=Number(input);op=t;input="0";}
      screen.textContent=input;
    });
    </script></body></html>
    """

    private func advance() {
        guard step < numberOfSteps - 1 else { complete = true; return }
        withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @AppStorage("librarySortMode") private var librarySortModeRaw = LibrarySortMode.alphabeticalAZ.rawValue
    @AppStorage("librarySortDateBasis") private var librarySortDateBasisRaw = LibrarySortDateBasis.modified.rawValue
    @AppStorage("libraryFoldersOnTop") private var libraryFoldersOnTop = true
    @AppStorage("libraryFavoritesOnTop") private var libraryFavoritesOnTop = true
    @AppStorage("askBeforeSwitch") private var askBeforeSwitch = true
    @AppStorage("closeOnFlipShake") private var closeOnFlipShake = false
    @AppStorage("htmlapp.shakeExitSeconds") private var shakeExitSeconds = 1.0
    @AppStorage("htmlapp.shakeFadeEndAngle") private var shakeFadeEndAngle = 70.0
    @AppStorage("sourceRefreshDays") private var sourceRefreshDays = 3
    @AppStorage("autoApplyWebsiteUpdates") private var autoApplyWebsiteUpdates = false
    @AppStorage("webClipFullScreen") private var webClipFullScreen = true
    @AppStorage("webClipPrecomposed") private var webClipPrecomposed = false
    @AppStorage("allowJavaScript") private var allowJavaScript = true
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("htmlapp.icloud.syncApps") private var iCloudSyncApps = false
    @AppStorage("htmlapp.icloud.syncData") private var iCloudSyncData = false
    @AppStorage("htmlapp.previousOpenedVersion") private var previousOpenedVersion = ""
    @State private var showWhatsNew = false
    @State private var working = false
    @AppStorage("htmlapp.dictationEngine") private var dictationEngine = "apple"

    private var selectedSortMode: LibrarySortMode {
        LibrarySortMode(rawValue: librarySortModeRaw) ?? .alphabeticalAZ
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("AI & Voice") {
                    NavigationLink {
                        AIConfigurationSettingsView()
                    } label: {
                        Label("AI Connection & Generation", systemImage: "sparkles")
                    }
                    Picker("Voice Dictation", selection: $dictationEngine) {
                        Label("Apple Speech — Live", systemImage: "waveform").tag("apple")
                        Label("Whisper Offline", systemImage: "mic").tag("whisper")
                    }
                    .pickerStyle(.navigationLink)
                    Text(dictationEngine == "apple"
                         ? "See words live while speaking. Some devices may use Apple's speech service."
                         : "Record first, then transcribe on-device after releasing the microphone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Library") {
                    Picker("Layout", selection: $libraryLayout) {
                        Label("List", systemImage: "list.bullet").tag("list")
                        Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    }
                    .pickerStyle(.segmented)

                    DisclosureGroup("Sorting & Organization") {
                        Picker("Sort Apps", selection: $librarySortModeRaw) {
                            ForEach(LibrarySortMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        if selectedSortMode.usesDateBasis {
                            Picker("Sort by Date", selection: $librarySortDateBasisRaw) {
                                ForEach(LibrarySortDateBasis.allCases) { basis in
                                    Text(basis.title).tag(basis.rawValue)
                                }
                            }
                        }
                        Toggle("Folders First", isOn: $libraryFoldersOnTop)
                        Toggle("Favorites First", isOn: $libraryFavoritesOnTop)
                    }
                }

                Section("iCloud") {
                    Toggle("Sync Saved Apps", isOn: $iCloudSyncApps)
                        .onChange(of: iCloudSyncApps) { enabled in
                            if enabled { store.requestICloudSync() }
                        }
                    if iCloudSyncApps {
                        Toggle("Include Saved App Data", isOn: $iCloudSyncData)
                            .onChange(of: iCloudSyncData) { _ in
                                store.requestICloudSync()
                            }
                        Button("Sync Now") { store.requestICloudSync() }
                        Text("iCloud sync requires a compatible signing profile. App permissions and credentials never sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Manage") {
                    NavigationLink {
                        GeneratedIntegrationsView().environmentObject(store)
                    } label: {
                        Label("Widgets & Background Tasks", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        HTMLAppDataTransferView().environmentObject(store)
                    } label: {
                        Label("Backup, Import & Transfer", systemImage: "square.and.arrow.up.on.square")
                    }
                    Toggle("Confirm App Switching", isOn: $askBeforeSwitch)
                }

                Section("Help") {
                    Button {
                        onboardingComplete = false
                        dismiss()
                    } label: {
                        Label("Guided Tutorial", systemImage: "questionmark.circle")
                    }
                    Button { showWhatsNew = true } label: {
                        Label("What's New", systemImage: "sparkles.rectangle.stack")
                    }
                }

                Section {
                    DisclosureGroup("Advanced Settings") {
                        Toggle("Close App with Face-Down Shake", isOn: $closeOnFlipShake)
                        if closeOnFlipShake {
                            HStack {
                                Text("Shake Duration")
                                Spacer()
                                Text(shakeExitSeconds.formatted(.number.precision(.fractionLength(1))) + " s")
                            }
                            Slider(value: $shakeExitSeconds, in: 0.5...5.0, step: 0.1)
                        }
                        Toggle("Developer Mode", isOn: $developerMode)

                        if developerMode {
                            NavigationLink {
                                ForgeDeveloperDiagnosticsView().environmentObject(store)
                            } label: {
                                Label("Diagnostics", systemImage: "ladybug")
                            }
                            NavigationLink {
                                AIDebugTraceView()
                            } label: {
                                Label("AI Edit Logs", systemImage: "doc.text.magnifyingglass")
                            }
                            Toggle("Auto-Apply Website Updates", isOn: $autoApplyWebsiteUpdates)
                            Stepper("Source Cache: \(sourceRefreshDays) Days",
                                    value: $sourceRefreshDays, in: 1...30)
                            Toggle("Full-Screen Home Screen Apps", isOn: $webClipFullScreen)
                            Toggle("Precomposed App Icons", isOn: $webClipPrecomposed)
                            Toggle("Allow JavaScript", isOn: $allowJavaScript)
                            HStack {
                                Text("Shake Fade Angle")
                                Spacer()
                                Text("\(Int(shakeFadeEndAngle))°")
                            }
                            Slider(value: $shakeFadeEndAngle, in: 20...180, step: 5)
                            Button("Refresh External Sources") { refreshAll() }
                                .disabled(working || store.apps.isEmpty)
                            Button("Rebuild Saved Icons") { rebuildIcons() }
                                .disabled(working || store.apps.isEmpty)
                            Button("Clear Source Caches", role: .destructive) {
                                SourceCache.shared.clearAll()
                            }
                            LabeledContent("Saved Apps", value: "\(store.apps.count)")
                            LabeledContent("Folders", value: "\(store.folders.count)")
                        }
                    }
                } footer: {
                    Text("Less-used controls and developer tools stay here without cluttering everyday settings.")
                }

                Section {
                    LabeledContent("Version", value: HTMLAppReleaseNotes.compiledVersion)
                    if developerMode {
                        LabeledContent("Source Build", value: HTMLAppReleaseNotes.compiledBuild)
                        LabeledContent("Installed IPA", value: HTMLAppReleaseNotes.packagedVersion)
                        LabeledContent("IPA Build", value: HTMLAppReleaseNotes.packagedBuild)
                        if !previousOpenedVersion.isEmpty {
                            LabeledContent("Updated From", value: previousOpenedVersion)
                        }
                        if !HTMLAppReleaseNotes.packagingMatchesCode {
                            Label("Installed IPA metadata differs from the source version.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
            .sheet(isPresented: $showWhatsNew) {
                HTMLAppWhatsNewView(previousVersion: nil) {
                    showWhatsNew = false
                }
            }
        }
    }

    private var librarySortDescription: String {
        switch selectedSortMode {
        case .alphabeticalAZ, .alphabeticalZA:
            return libraryFoldersOnTop
                ? "Folders are grouped above apps, then names use the selected alphabetical order."
                : "Folders and apps are mixed together and sorted by name."
        case .latestFirst:
            return "The newest items appear first using \(sortDateBasisTitle.lowercased())."
        case .latestLast:
            return "The newest items appear last using \(sortDateBasisTitle.lowercased())."
        case .recentlyOpened:
            return "Recently used items appear first. Creating a new app counts as recent activity, so it appears at the top of the app ordering immediately."
        }
    }

    private var sortDateBasisTitle: String {
        (LibrarySortDateBasis(rawValue: librarySortDateBasisRaw) ?? .modified).title
    }

    private func refreshAll() {
        working = true
        Task {
            for app in store.apps { await SourceCache.shared.refresh(app: app, force: true) }
            working = false
            store.notice = "External sources refreshed."
        }
    }

    private func rebuildIcons() {
        working = true
        Task {
            await store.rebuildIcons()
            working = false
        }
    }
}
