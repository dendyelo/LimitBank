// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LimitBank",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LimitBank", targets: ["LimitBank"])
    ],
    targets: [
        .executableTarget(
            name: "LimitBank",
            path: "Sources"
        ),
        .testTarget(
            name: "LimitBankTests",
            dependencies: ["LimitBank"],
            path: "Tests/LimitBankTests"
        )
    ]
)
