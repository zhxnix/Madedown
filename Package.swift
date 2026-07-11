// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Madedown",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Madedown", targets: ["Madedown"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Madedown",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MarkdownNotepad"
        )
    ]
)
