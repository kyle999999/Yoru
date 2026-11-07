// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Texture",
    products: [
        .library(
            name: "AsyncDisplayKit",
            targets: ["AsyncDisplayKit"]
        )
    ],
    dependencies: [],
    targets: [
        .binaryTarget(name: "AsyncDisplayKit", path: "AsyncDisplayKit.xcframework"),
    ]
)
