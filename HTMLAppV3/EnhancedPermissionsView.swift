import SwiftUI
import UIKit

struct EnhancedAppPermissionsView: View {
    let app: SavedHTMLApp
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [HTMLPermission: HTMLPermissionChoice]
    @State private var sensorChoice: HTMLPermissionChoice

    init(app: SavedHTMLApp) {
        self.app = app
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
                    ForEach(HTMLPermission.allCases) { permission in
                        permissionRow(
                            title: permission.title,
                            detail: permission.detail,
                            symbol: permission.symbol,
                            selection: binding(for: permission)
                        )
                    }

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
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, symbol: String, selection: Binding<HTMLPermissionChoice>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(HTMLPermissionChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
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
