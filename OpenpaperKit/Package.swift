// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenpaperKit",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [.library(name: "OpenpaperKit", targets: ["OpenpaperKit"])],
    targets: [
        .target(name: "OpenpaperKit"),
        .testTarget(name: "OpenpaperKitTests", dependencies: ["OpenpaperKit"])
    ]
)
