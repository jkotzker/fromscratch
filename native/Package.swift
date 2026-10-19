// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FromScratch",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FromScratchCore", targets: ["FromScratchCore"]),
        .executable(name: "FromScratch", targets: ["FromScratch"]),
    ],
    targets: [
        .target(name: "FromScratchCore"),
        .executableTarget(
            name: "FromScratch",
            dependencies: ["FromScratchCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "FromScratchCoreTests",
            dependencies: ["FromScratchCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
