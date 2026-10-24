// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-browser-data",
    // macOS only: the files it reads are Safari's on this Mac.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BrowserData", targets: ["BrowserData"]),
    ],
    targets: [
        // Synchronous and local: no transport, nothing to await, so the
        // nonisolated-nonsending feature is left off.
        .target(name: "BrowserData"),
        .testTarget(name: "BrowserDataTests", dependencies: ["BrowserData"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
