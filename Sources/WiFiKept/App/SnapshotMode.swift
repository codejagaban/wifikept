import SwiftUI
import AppKit

/// Debug harness: launch with WIFIKEPT_SNAPSHOT=/some/dir to render every
/// tab (plus the menu bar popover) to PNG after a few seconds of live
/// sampling, then exit. Used to verify the UI without screen recording.
@MainActor
enum SnapshotMode {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["WIFIKEPT_SNAPSHOT"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            print("AI available: \(AppState.shared.insights.aiAvailable)")
            if ProcessInfo.processInfo.environment["WIFIKEPT_SPEEDTEST"] != nil {
                await AppState.shared.speed.run()
                if let r = AppState.shared.speed.result {
                    print(String(format: "Speed test: %.1f Mbps down, %.1f Mbps up, latency %@, dns %@",
                                 r.downloadMbps, r.uploadMbps,
                                 r.latencyMs.map { Fmt.ms($0) } ?? "n/a",
                                 r.dnsMs.map { Fmt.ms($0) } ?? "n/a"))
                }
            }
            let base = URL(fileURLWithPath: dir)
            for tab in MainTab.allCases {
                let view = SnapshotTabView(tab: tab)
                    .environmentObject(AppState.shared)
                write(view: view, width: 1000, to: base.appendingPathComponent("tab-\(tab.rawValue).png"))
            }
            write(view: MenuBarView().environmentObject(AppState.shared),
                  width: nil, to: base.appendingPathComponent("menubar.png"))
            exit(0)
        }
    }

    private static func write(view: some View, width: CGFloat?, to url: URL) {
        // WIFIKEPT_APPEARANCE=light renders the light theme; default is dark.
        let light = ProcessInfo.processInfo.environment["WIFIKEPT_APPEARANCE"] == "light"
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, light ? .light : .dark))
        if let width {
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        }
        renderer.scale = 2
        let appearance = NSAppearance(named: light ? .aqua : .darkAqua)!
        var png: Data?
        appearance.performAsCurrentDrawingAppearance {
            if let img = renderer.nsImage,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                png = rep.representation(using: .png, properties: [:])
            }
        }
        try? png?.write(to: url)
    }
}

private struct SnapshotTabView: View {
    var tab: MainTab
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            switch tab {
            case .overview: OverviewView()
            case .signal: SignalView()
            case .speed: SpeedView()
            case .trends: TrendsView()
            case .usage: UsageView()
            case .ask: AskView().frame(height: 700)
            case .details: DetailsView()
            }
        }
        .padding(20)
        .frame(width: 1000)
        .background(Theme.windowBG)
    }
}
