// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BetterGestures",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        // pure gesture recognition, no appkit/swiftui/multitouchsupport dependency.
        .target(name: "GestureCore"),
        // bridge to the private MultitouchSupport.framework, listens to every device.
        .target(
            name: "MultitouchBridge",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "BetterGestures",
            dependencies: ["GestureCore", "MultitouchBridge"]
        ),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
    ]
)
