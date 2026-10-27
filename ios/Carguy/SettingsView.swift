import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: StudyStore
    @AppStorage("apiURL") private var endpoint = ""
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 18
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @State private var token = ""
    @State private var reminderTime = Date()
    @State private var status = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Pair with your backend") {
                    TextField("HTTPS Cloud Run URL", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Device token", text: $token)
                    Button("Save device token") {
                        do { try DeviceToken.save(token); status = "Device token saved in Keychain." }
                        catch { status = error.localizedDescription }
                    }
                    Button("Sync now") { Task { await store.sync() } }.disabled(store.busy)
                    Text("Use the device token configured on your backend. Your OpenAI key stays on the server.").font(.caption)
                }
                Section("Daily reminder") {
                    Toggle("Remind me", isOn: $remindersEnabled)
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    Button("Save reminder") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                        reminderHour = parts.hour ?? 18; reminderMinute = parts.minute ?? 0
                        Task {
                            do {
                                try await Reminders.schedule(hour: reminderHour, minute: reminderMinute, enabled: remindersEnabled)
                                status = remindersEnabled ? "Daily reminder scheduled." : "Reminder disabled."
                            } catch { status = error.localizedDescription }
                        }
                    }
                }
                Section("Privacy and backup") {
                    Text("This is a personal, single-user library. Sync sends car and plaque photos, notes and learning history to your API. Plaque text recognition happens on this device. Research sends reviewed identification notes and disputed facts to OpenAI, not your selected or captured photos.")
                    Text("Sync before reinstalling the app. Unsynced device data is lost when the app is deleted.")
                }
                if !status.isEmpty { Text(status) }
            }
            .navigationTitle("Settings")
            .onAppear {
                token = DeviceToken.read()
                reminderTime = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
            }
        }
    }
}
