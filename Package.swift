// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Osmium",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Osmium", targets: ["Osmium"])
    ],
    targets: [
        .executableTarget(
            name: "Osmium",
            path: "Sources/Osmium"
        )
    ]
)
