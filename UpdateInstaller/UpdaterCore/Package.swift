// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "UpdaterCore",
  platforms: [
    .macOS(.v27),
  ],
  products: [
    .library(
      name: "UpdaterCore",
      targets: ["UpdaterCore"]
    ),
  ],
  dependencies: [
    .package(path: "../../MarkEditTools"),
  ],
  targets: [
    .target(
      name: "UpdaterCore",
      path: "Sources",
      plugins: [
        .plugin(name: "SwiftLint", package: "MarkEditTools"),
      ]
    ),

    .testTarget(
      name: "UpdaterCoreTests",
      dependencies: ["UpdaterCore"],
      path: "Tests",
      plugins: [
        .plugin(name: "SwiftLint", package: "MarkEditTools"),
      ]
    ),
  ]
)
