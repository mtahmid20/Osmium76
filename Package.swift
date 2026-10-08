// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Caesium",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Caesium", targets: ["Caesium"])
    ],
    targets: [
        .executableTarget(
            name: "Caesium",
            path: "Sources/Caesium"
        )
    ]
)
