// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerraCognita",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Library — cross-platform. Contains every view + model. Both
        // the macOS executable and the iOS app target import this.
        .library(name: "TerraCognitaKit", targets: ["TerraCognitaKit"]),
        // Executable — macOS only. Thin @main shell that imports the
        // library, sets the activation policy, and shows GraphView.
        .executable(name: "TerraCognita", targets: ["TerraCognita"])
    ],
    targets: [
        .target(
            name: "TerraCognitaKit",
            path: "Sources/TerraCognitaKit",
            resources: [
                // "The World of Hayao Miyazaki" demo atlas, bundled with
                // every target so the app launches with content even when
                // no on-disk atlas is available (e.g. iOS).
                .copy("Resources/miyazaki-vault")
            ]
        ),
        .executableTarget(
            name: "TerraCognita",
            dependencies: ["TerraCognitaKit"],
            path: "Sources/TerraCognita"
        ),
        .testTarget(
            name: "TerraCognitaKitTests",
            dependencies: ["TerraCognitaKit"],
            path: "Tests/TerraCognitaKitTests"
        )
    ]
)
