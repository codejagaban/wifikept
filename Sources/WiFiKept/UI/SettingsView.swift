import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettings()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "chart.bar") }
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(width: 500, height: 360)
    }
}

/// Shared chrome so every tab is the same size and scrolls when it needs to.
private struct SettingsTab<Content: View>: View {
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: 500, height: 360)
            .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .system).scheme)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage("background.interval") private var backgroundInterval = 60.0
    @AppStorage("battery.saver") private var batterySaverEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsTab {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceSetting.allCases) { a in
                        Text(a.rawValue).tag(a.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
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

            Section("Energy") {
                Picker("Background updates", selection: $backgroundInterval) {
                    Text("Every 30 seconds").tag(30.0)
                    Text("Every minute").tag(60.0)
                    Text("Every 2 minutes").tag(120.0)
                    Text("Every 5 minutes").tag(300.0)
                }
                Toggle("Slow down further on battery", isOn: $batterySaverEnabled)
                Text("How often WiFiKept samples while you're not looking at it — full speed resumes instantly when you open the window or menu bar. Usage totals stay exact at any interval; longer ones mean coarser Trends history and per-app attribution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Menu bar

private struct MenuBarSettings: View {
    @AppStorage("menubar.metric") private var metricRaw = MenuBarMetric.quality.rawValue

    var body: some View {
        SettingsTab {
            Section("Menu bar") {
                Picker("Show next to the icon", selection: $metricRaw) {
                    ForEach(MenuBarMetric.allCases) { m in
                        Label(m.rawValue, systemImage: m.icon).tag(m.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text("The icon changes to match the metric you pick. Click it any time for the full popover — readings refresh the moment it opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Data

private struct DataSettings: View {
    @AppStorage("budget.gb") private var budgetGB = 0.0
    @State private var showCustomBudget = false
    @State private var customBudgetText = ""

    static let budgetPresets: [Double] = [10, 20, 50, 100, 200, 500, 1000]

    /// Picker selection: 0 = off, a preset value, or -1 for the custom field.
    private var budgetSelection: Binding<Double> {
        Binding(
            get: {
                if budgetGB == 0 && !showCustomBudget { return 0 }
                return showCustomBudget || !Self.budgetPresets.contains(budgetGB) ? -1 : budgetGB
            },
            set: { choice in
                if choice == -1 {
                    customBudgetText = budgetGB > 0 ? String(format: "%g", budgetGB) : ""
                    showCustomBudget = true
                } else {
                    showCustomBudget = false
                    budgetGB = choice
                    if choice > 0 { Notifier.requestAuthorization() }
                }
            })
    }

    private var parsedCustomBudget: Double? {
        guard let value = Double(customBudgetText.replacingOccurrences(of: ",", with: ".")),
              value > 0, value <= 100_000 else { return nil }
        return value
    }

    private func applyCustomBudget() {
        guard let value = parsedCustomBudget else { return }
        budgetGB = value
        Notifier.requestAuthorization()
    }

    var body: some View {
        SettingsTab {
            Section("Monthly budget") {
                Picker("Limit", selection: budgetSelection) {
                    Text("Off").tag(0.0)
                    ForEach(Self.budgetPresets, id: \.self) { gb in
                        Text(gb >= 1000 ? "1 TB" : "\(Int(gb)) GB").tag(gb)
                    }
                    Divider()
                    Text("Custom…").tag(-1.0)
                }
                if showCustomBudget {
                    HStack {
                        TextField("e.g. 250", text: $customBudgetText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .onSubmit(applyCustomBudget)
                        Text("GB per month")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Set", action: applyCustomBudget)
                            .disabled(parsedCustomBudget == nil)
                    }
                }
                Text("Get a notification when this Mac passes 80% and 100% of the budget in a calendar month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speed tests") {
                Text("Speed tests only run when you start one from the Speed tab — each run moves roughly 100–300 MB, so WiFiKept never tests on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if budgetGB > 0 && !Self.budgetPresets.contains(budgetGB) {
                showCustomBudget = true
                customBudgetText = String(format: "%g", budgetGB)
            }
        }
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @AppStorage("updates.auto") private var autoUpdates = true
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        SettingsTab {
            Section("Updates") {
                LabeledContent("Version", value: updater.currentVersion)
                Toggle("Check automatically", isOn: $autoUpdates)
                HStack {
                    switch updater.state {
                    case .idle:
                        Text("").font(.caption)
                    case .checking:
                        ProgressView().controlSize(.small)
                        Text("Checking…").font(.caption).foregroundStyle(.secondary)
                    case .upToDate:
                        Text("You're on the latest version.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .available(let v):
                        Text("Version \(v) is available.")
                            .font(.caption).foregroundStyle(Theme.green)
                    case .working(let label):
                        ProgressView().controlSize(.small)
                        Text(label).font(.caption).foregroundStyle(.secondary)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                    if case .available = updater.state {
                        Button("Install & Relaunch") {
                            Task { await updater.installAvailableUpdate() }
                        }
                    } else if case .working = updater.state {
                        EmptyView()
                    } else {
                        Button("Check Now") {
                            Task { await updater.check() }
                        }
                    }
                }
                Text("Updates are downloaded from the project's GitHub releases and installed in place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        SettingsTab {
            Section("Apple Intelligence") {
                LabeledContent("Status") {
                    Text(app.insights.aiAvailable ? "Available — insights are generated on-device"
                                                  : "Unavailable — using built-in summaries")
                        .foregroundStyle(app.insights.aiAvailable ? .green : .secondary)
                }
            }

            Section("Privacy") {
                Text("All readings stay on this Mac. The only network traffic WiFiKept originates is the speed test itself (via Cloudflare) and the update check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Location access is required by macOS to read Wi-Fi identifiers like SSID and BSSID — your location itself is never read or stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
