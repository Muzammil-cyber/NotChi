// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotChi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotChi",
            path: "Sources/NotChi",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
