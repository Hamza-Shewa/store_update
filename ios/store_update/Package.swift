// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "store_update",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "store-update", targets: ["store_update"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "store_update",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // No tracking, no collected data, no required-reason APIs.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
