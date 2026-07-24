import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case signal = "Signal"
    case speed = "Speed"
    case trends = "Trends"
    case usage = "Usage"
    case details = "Details"
    var id: String { rawValue }
}

struct MainWindow: View {
    @EnvironmentObject var app: AppState
    @State private var tab: MainTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.windowBG)
        .frame(minWidth: 960, minHeight: 700)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack {
            Theme.headerBG
            HStack {
                // Space for the traffic lights.
                Spacer().frame(width: 80)
                Spacer()
                tabBar
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Settings")
                Spacer().frame(width: 16)
            }
        }
        .frame(height: 54)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(tab == t ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: OverviewView()
        case .signal: SignalView()
        case .speed: SpeedView()
        case .trends: TrendsView()
        case .usage: UsageView()
        case .details: DetailsView()
        }
    }
}
