// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cordkey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "cordkey",
            path: "Sources/cordkey",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
