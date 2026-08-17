// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushDock",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PushDock", targets: ["PushDock"])
    ],
    targets: [
        .executableTarget(
            name: "PushDock",
            path: "PushDock"
        )
    ]
)
