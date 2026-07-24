import Foundation
import AppKit

/// Self-updater backed by GitHub Releases: compares the latest release tag
/// against the running version, downloads the DMG asset, swaps the app in
/// /Applications and relaunches.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case working(String)   // downloading / installing progress label
        case failed(String)
    }

    static let shared = UpdateChecker()

    @Published private(set) var state: State = .idle
    private var downloadURL: URL?

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private static let api = URL(string: "https://api.github.com/repos/codejagaban/wifikept/releases/latest")!

    private init() {
        // Auto-check shortly after launch, then daily.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            while true {
                if UserDefaults.standard.object(forKey: "updates.auto") as? Bool ?? true {
                    await check(quietly: true)
                }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    func check(quietly: Bool = false) async {
        if !quietly { state = .checking }
        do {
            var request = URLRequest(url: Self.api)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                throw URLError(.cannotParseResponse)
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmg = assets.compactMap { $0["browser_download_url"] as? String }
                .first { $0.hasSuffix(".dmg") }

            if Self.isNewer(latest, than: currentVersion), let dmg, let url = URL(string: dmg) {
                downloadURL = url
                state = .available(version: latest)
            } else if !quietly {
                state = .upToDate
            } else if case .available = state {
                // keep showing an already-found update
            } else {
                state = .idle
            }
        } catch {
            if !quietly { state = .failed("Couldn't check: \(error.localizedDescription)") }
        }
    }

    /// Download the DMG, replace /Applications/WiFiKept.app, relaunch.
    func installAvailableUpdate() async {
        guard let downloadURL else { return }
        do {
            state = .working("Downloading…")
            let (tmp, _) = try await URLSession.shared.download(from: downloadURL)
            let dmg = tmp.deletingLastPathComponent().appendingPathComponent("WiFiKept-update.dmg")
            try? FileManager.default.removeItem(at: dmg)
            try FileManager.default.moveItem(at: tmp, to: dmg)

            state = .working("Installing…")
            let mountPoint = "/tmp/wifikept-update-mount"
            try Self.run("/usr/bin/hdiutil",
                         ["attach", dmg.path, "-nobrowse", "-quiet", "-mountpoint", mountPoint])
            defer { try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"]) }

            let source = "\(mountPoint)/WiFiKept.app"
            guard FileManager.default.fileExists(atPath: source) else {
                throw URLError(.resourceUnavailable)
            }
            let dest = "/Applications/WiFiKept.app"
            try? FileManager.default.removeItem(atPath: dest)
            try Self.run("/usr/bin/ditto", [source, dest])
            try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"])

            state = .working("Relaunching…")
            AppState.shared.flushUsage()
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open '\(dest)'"]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "UpdateChecker", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) exited \(p.terminationStatus)"])
        }
    }

    /// Semver-ish compare: "1.0.2" newer than "1.0.1".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
