// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotChi",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        // Hot reload of SwiftUI views through InjectionNext; compiles to nothing in release.
        .package(url: "https://github.com/johnno1962/HotSwiftUI.git", from: "1.2.5"),
    ],
    targets: [
        .executableTarget(
            name: "NotChi",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "HotSwiftUI", package: "HotSwiftUI"),
            ],
            path: "Sources/NotChi",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("EventKit"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
                // Debug only: lets InjectionNext swap code in the running app.
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug)),
            ]
        )
    ]
)
