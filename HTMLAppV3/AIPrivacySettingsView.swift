import SwiftUI

struct AIPrivacySettingsView: View {
    @AppStorage("aiPrivacy.location") private var location = "off"
    @AppStorage("aiPrivacy.dateTime") private var dateTime = false
    @AppStorage("aiPrivacy.device") private var device = false
    @AppStorage("aiPrivacy.calendar") private var calendar = false
    @AppStorage("aiPrivacy.reminders") private var reminders = false
    @AppStorage("aiPrivacy.http") private var http = false

    var body: some View {
        Form {
            Section {
                Picker("Location", selection: $location) {
                    Text("Off").tag("off")
                    Text("Approximate").tag("approximate")
                    Text("Precise").tag("precise")
                }
                Toggle("Date, time, locale and time zone", isOn: $dateTime)
                Toggle("Device information and appearance", isOn: $device)
                Toggle("Upcoming calendar events", isOn: $calendar)
                Toggle("Upcoming reminders", isOn: $reminders)
                Toggle("Allow AI to make web API requests", isOn: $http)
            } header: {
                Text("AI Generation Privacy")
            } footer: {
                Text("All permissions default to off. AI tools check these switches each time. iOS permission is also required for location, calendar and reminders. Results from approved tools may be sent to your configured AI provider.")
            }
            Section("Web API limits") {
                Text("Public HTTPS GET only. Local or private hosts and redirects are blocked. Eight requests maximum, eight seconds per request and 200 KB per response.")
                Text("Tool usage appears in Forge Details → Debug. Backgrounded generation cannot request location or calendar authorization.")
            }
        }
        .navigationTitle("AI Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
