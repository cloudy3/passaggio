// swift-tools-version: 6.0
import PackageDescription

// Platform-independent logic for Passaggio. Everything here builds with plain
// Foundation so the test suite runs on macOS, in Xcode, and on non-Apple hosts.
let package = Package(
    name: "PassaggioCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PassaggioCore", targets: ["PassaggioCore"]),
    ],
    targets: [
        .target(name: "PassaggioCore"),
        .testTarget(
            name: "PassaggioCoreTests",
            dependencies: ["PassaggioCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
