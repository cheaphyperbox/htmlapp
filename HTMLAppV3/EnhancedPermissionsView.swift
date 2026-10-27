import SwiftUI
import UIKit

struct EnhancedAppPermissionsView: View {
    let app: SavedHTMLApp
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [HTMLPermission: HTMLPermissionChoice]
    @State private var sensorChoice: HTMLPermissionChoice
    @State private var showAll = false
    @State private var showingStorageManagement = false
    @State private var requested: Set<String>

    init(app: SavedHTMLApp) {
        self.app = app
        _requested = State(initialValue: HTMLPermissionStore.requested(appID: app.id))
        _choices = State(initialValue: Dictionary(uniqueKeysWithValues: HTMLPermission.allCases.map {
            ($0, HTMLPermissionStore.choice(for: $0, appID: app.id))
        }))
        _sensorChoice = State(initialValue: HTMLSensorPermissionPolicy.choice(appID: app.id))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AppIconView(app: app, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.headline)
                            Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("HTML App Permissions") {
                    ForEach(HTMLPermission.allCases.filter { showAll || requested.contains($0.rawValue) || choices[$0] != .ask }) { permission in
                        permissionRow(
                            title: permission.title,
                            detail: permission.detail,
                            symbol: permission.symbol,
                            selection: binding(for: permission)
                        )
                    }

                    if showAll || requested.contains("motionSensor") || sensorChoice != .ask {
                    permissionRow(
                        title: "Motion & Orientation",
                        detail: "Allows device orientation, compass direction, accelerometer, and gyroscope events while this HTML app is open.",
                        symbol: "gyroscope",
                        selection: Binding(
                            get: { sensorChoice },
                            set: {
                                sensorChoice = $0
                                HTMLSensorPermissionPolicy.set($0, appID: app.id)
                            }
                        )
                    )
                    }
                    Button(showAll ? "Show requested only" : "Show all permissions") {
                        showAll.toggle()
                    }
                }

                Section("Developer · App Data") {
                    LabeledContent("Portable data", value: ByteCountFormatter.string(fromByteCount: Int64((try? HTMLAppPortableDataStore.fileURL(appID: app.id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file))
                    LabeledContent("SQLite data", value: ByteCountFormatter.string(fromByteCount: Int64((try? HTMLAppDocumentDatabase.databaseURL(appID: app.id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file))
                    Button("Manage Storage") { showingStorageManagement = true }
                }
                Section {
                    Button("Open HTMLApp in iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Reset All to Ask", role: .destructive) {
                        HTMLPermissionStore.reset(appID: app.id)
                        HTMLSensorPermissionPolicy.reset(appID: app.id)
                        for permission in HTMLPermission.allCases { choices[permission] = .ask }
                        sensorChoice = .ask
                    }
                } footer: {
                    Text("Haptics do not require a per-app permission. Other protected capabilities remain subject to both this saved-app choice and any iOS system permission that applies.")
                }
            }
            .sheet(isPresented: $showingStorageManagement) { HTMLAppStorageManagementView(app: app) }
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, symbol: String, selection: Binding<HTMLPermissionChoice>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Menu {
                    ForEach(HTMLPermissionChoice.allCases) { choice in
                        Button(choice.title) { selection.wrappedValue = choice }
                    }
                } label: {
                    Text(selection.wrappedValue.title)
                        .font(.subheadline.weight(.medium))
                }
            }
            if showAll { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }

    private func binding(for permission: HTMLPermission) -> Binding<HTMLPermissionChoice> {
        Binding(
            get: { choices[permission] ?? .ask },
            set: {
                choices[permission] = $0
                HTMLPermissionStore.set($0, for: permission, appID: app.id)
            }
        )
    }
}
