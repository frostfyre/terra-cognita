// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFocus",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Library — cross-platform. Contains every view + model. Both
        // the macOS executable and a future iOS app target import this.
        .library(name: "AppFocusKit", targets: ["AppFocusKit"]),
        // Executable — macOS only. Thin @main shell that imports the
        // library, sets the activation policy, and shows GraphView.
        .executable(name: "AppFocus", targets: ["AppFocus"])
    ],
    targets: [
        .target(
            name: "AppFocusKit",
            path: "Sources/AppFocus",
            resources: [
                // "The World of Hayao Miyazaki" demo vault, bundled with
                // every target so the app launches with content even when
                // no on-disk vault is available (e.g. iOS).
                .copy("Resources/miyazaki-vault")
            ]
        ),
        .executableTarget(
            name: "AppFocus",
            dependencies: ["AppFocusKit"],
            path: "Sources/AppFocusApp"
        )
    ]
)
