import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case signal = "Signal"
    case speed = "Speed"
    case trends = "Trends"
    case usage = "Usage"
    case ask = "Ask"
    case details = "Details"
    var id: String { rawValue }
}

struct MainWindow: View {
    @EnvironmentObject var app: AppState
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue
    @State private var tab: MainTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                Group {
                    if tab == .ask {
                        // The chat lays out its own scroll region and pinned input bar.
                        AskView()
                    } else {
                        ScrollView {
                            content
                                .padding(20)
                                .frame(maxWidth: 1100)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .id(tab)
                .transition(.blurReplace.combined(with: .offset(y: 6)))
            }
        }
        .background(GlassBackdrop())
        .frame(minWidth: 960, minHeight: 700)
        .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .system).scheme)
    }

    private var header: some View {
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
                    .background(Circle().fill(Theme.fillSubtle))
            }
            .buttonStyle(.plain)
            .help("Settings")
            Spacer().frame(width: 16)
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(Theme.headerBG)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { t in
                Button {
                    withAnimation(.smooth(duration: 0.5, extraBounce: 0)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(tab == t ? Theme.fillSelected : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.fillSubtle))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: OverviewView()
        case .signal: SignalView()
        case .speed: SpeedView()
        case .trends: TrendsView()
        case .usage: UsageView()
        case .ask: AskView()
        case .details: DetailsView()
        }
    }
}
