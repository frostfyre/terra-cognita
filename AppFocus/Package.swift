// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFocus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AppFocus", targets: ["AppFocus"])
    ],
    targets: [
        .executableTarget(
            name: "AppFocus",
            path: "Sources/AppFocus"
        )
    ]
)
