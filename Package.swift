// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheOnePractice",
    // The iOS app is built from these same sources by TheOnePractice.xcodeproj —
    // SwiftPM has no notion of an iOS app bundle, but it does typecheck the code
    // for the platform.
    platforms: [.macOS(.v14), .iOS(.v17)],
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
