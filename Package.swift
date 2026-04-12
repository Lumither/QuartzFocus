// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuartzFocus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "QuartzFocus",
            targets: ["QuartzFocus"]
        )
    ],
    targets: [
        .target(
            name: "QuartzFocusKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "QuartzFocus",
            dependencies: ["QuartzFocusKit"]
        ),
        .testTarget(
            name: "QuartzFocusKitTests",
            dependencies: ["QuartzFocusKit"]
        ),
    ]
)
