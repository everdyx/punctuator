// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Punctuator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Punctuator", targets: ["Punctuator"])
    ],
    targets: [
        .executableTarget(
            name: "Punctuator",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
