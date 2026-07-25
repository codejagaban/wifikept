import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("menubar.metric") private var metricRaw = MenuBarMetric.quality.rawValue
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage("budget.gb") private var budgetGB = 0.0
    @AppStorage("updates.auto") private var autoUpdates = true
    @AppStorage("battery.saver") private var batterySaverEnabled = true
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
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
                Toggle("Slow down sampling on battery", isOn: $batterySaverEnabled)
                Text("On battery, live readouts refresh every 5–30 s instead of every 1–10 s. Usage totals stay exact either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Menu bar shows", selection: $metricRaw) {
                    ForEach(MenuBarMetric.allCases) { m in
                        Label(m.rawValue, systemImage: m.icon).tag(m.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Speed test") {
                Text("Speed tests only run when you start one from the Speed tab — each run moves roughly 100–300 MB, so WiFiKept never tests on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data budget") {
                Picker("Monthly limit", selection: budgetSelection) {
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

            Section("Apple Intelligence") {
                LabeledContent("Status") {
                    Text(app.insights.aiAvailable ? "Available — insights are generated on-device"
                                                  : "Unavailable — using built-in summaries")
                        .foregroundStyle(app.insights.aiAvailable ? .green : .secondary)
                }
            }

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
            }

            Section("Privacy") {
                Text("All readings stay on this Mac. The only network traffic WiFiKept originates is the speed test itself (via Cloudflare). Location access is required by macOS to read Wi-Fi identifiers like SSID and BSSID — your location itself is never read.")
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
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .system).scheme)
    }
}
