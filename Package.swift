// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiFiKept",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "WiFiKept",
            path: "Sources/WiFiKept",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
