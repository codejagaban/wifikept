import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            SnapshotMode.runIfRequested()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't lose the last minute of usage accounting.
        MainActor.assumeIsolated {
            AppState.shared.flushUsage()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // menu bar app keeps sampling with the window closed
    }
}

@main
struct WiFiKeptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var app = AppState.shared

    var body: some Scene {
        Window("WiFiKept", id: "main") {
            MainWindow()
                .environmentObject(app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 780)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}
