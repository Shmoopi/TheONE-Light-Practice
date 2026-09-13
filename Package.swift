// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheOnePractice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TheOnePractice",
            path: "Sources/TheOnePractice",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TheOnePracticeTests",
            dependencies: ["TheOnePractice"],
            path: "Tests/TheOnePracticeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
