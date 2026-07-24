import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("menubar.metric") private var metricRaw = MenuBarMetric.quality.rawValue
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage("speedtest.schedule") private var speedSchedule = 0.0
    @AppStorage("budget.gb") private var budgetGB = 0.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceSetting.allCases) { a in
                        Text(a.rawValue).tag(a.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Keep WiFiKept running so weekly and monthly usage totals stay complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Show next to the Wi-Fi icon", selection: $metricRaw) {
                    ForEach(MenuBarMetric.allCases) { m in
                        Text(m.rawValue).tag(m.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Speed test") {
                Picker("Run automatically", selection: $speedSchedule) {
                    Text("Off").tag(0.0)
                    Text("Every hour").tag(1.0)
                    Text("Every 3 hours").tag(3.0)
                    Text("Every 6 hours").tag(6.0)
                    Text("Every 12 hours").tag(12.0)
                    Text("Once a day").tag(24.0)
                }
                Text("Automatic tests build the Speed history in Trends. Each run moves roughly 100–300 MB, which also counts toward your usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data budget") {
                Picker("Monthly limit", selection: $budgetGB) {
                    Text("Off").tag(0.0)
                    ForEach([10.0, 20, 50, 100, 200, 500, 1000], id: \.self) { gb in
                        Text(gb >= 1000 ? "1 TB" : "\(Int(gb)) GB").tag(gb)
                    }
                }
                .onChange(of: budgetGB) { _, newValue in
                    if newValue > 0 { Notifier.requestAuthorization() }
                }
                Text("Get a notification when this Mac passes 80% and 100% of the budget in a calendar month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Intelligence") {
                LabeledContent("Status") {
                    Text(app.insights.aiAvailable ? "Available — insights are generated on-device"
                                                  : "Unavailable — using built-in summaries")
                        .foregroundStyle(app.insights.aiAvailable ? .green : .secondary)
                }
            }

            Section("Privacy") {
                Text("All readings stay on this Mac. The only network traffic WiFiKept originates is the speed test itself (via Cloudflare). Location access is required by macOS to read Wi-Fi identifiers like SSID and BSSID — your location itself is never read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .system).scheme)
    }
}
