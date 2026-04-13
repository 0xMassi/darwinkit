// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DarwinKit",
    platforms: [
        // WhisperKit requires macOS 14+. All other DarwinKit handlers
        // (NLP, Vision, Speech, iCloud) already work on 13+ but we bump
        // the whole package to keep a single build matrix.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "darwinkit", targets: ["DarwinKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // Transitive pin: WhisperKit → swift-transformers pulls
        // swift-collections, which ships a `_RopeModule` target starting
        // at 1.4.x. That module's manifest uses a Swift language version
        // setting that SwiftPM shipped with Xcode 16.4 (current GitHub
        // Actions macos runner) can't parse, causing release CI to fail
        // with `error: 'swift-collections': Some of the Swift language
        // versions used in target '_RopeModule' settings are supported.
        // (given: [5], supported: [])`. Pinning to 1.3.x (pre-rope)
        // keeps CI green without losing any functionality WhisperKit or
        // swift-transformers actually need. Revisit when the runner's
        // Xcode is newer than 16.4.
        .package(url: "https://github.com/apple/swift-collections.git", "1.1.0"..<"1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "DarwinKit",
            dependencies: [
                "DarwinKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            // Info.plist used to be embedded via -sectcreate linker flag
            // to satisfy TCC for mic access. That turned out to break
            // AVAudioEngine's input node (zero-filled stream) because
            // giving the sidecar its own CFBundleIdentifier changed how
            // CoreAudio routes mic input. TCC attribution already works
            // via the responsible-process chain up to com.stik.app,
            // which has the entitlement + usage descriptions in its real
            // Info.plist. Keep the file in the source tree for reference
            // but explicitly exclude it from the build.
            exclude: ["Info.plist"]
        ),
        .target(
            name: "DarwinKitCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "DarwinKitCoreTests",
            dependencies: ["DarwinKitCore"]
        )
    ]
)
