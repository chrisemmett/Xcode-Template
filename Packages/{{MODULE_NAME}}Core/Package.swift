// swift-tools-version: 6.0
// The app's platform-neutral logic. Foundation only (no UIKit, SwiftUI or
// SwiftData), so `make test-core` runs it with plain `swift test` on any Mac or
// Linux machine, including a Claude cloud session that has no Xcode.
import PackageDescription

let package = Package(
    name: "{{MODULE_NAME}}Core",
    platforms: [.iOS("{{IOS_DEPLOYMENT_TARGET}}"), .macOS(.v15)],
    products: [
        .library(name: "{{MODULE_NAME}}Core", targets: ["{{MODULE_NAME}}Core"]),
    ],
    targets: [
        .target(
            name: "{{MODULE_NAME}}Core",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "{{MODULE_NAME}}CoreTests",
            dependencies: ["{{MODULE_NAME}}Core"]
        ),
    ]
)
