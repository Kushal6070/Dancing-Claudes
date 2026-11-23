// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VibeClauding",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "VibeClauding",
            path: "Sources/VibeClauding",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        )
    ]
)
