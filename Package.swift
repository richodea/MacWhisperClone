// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWhisperClone",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacWhisperClone",
            targets: ["MacWhisperClone"]
        )
    ],
    dependencies: [
        // WhisperKit for on-device whisper transcription (Apple Silicon native)
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // GRDB for SQLite persistence
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        // Defaults for preferences
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacWhisperClone",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Defaults", package: "Defaults"),
            ],
            path: "Sources/MacWhisperClone"
        )
    ]
)
