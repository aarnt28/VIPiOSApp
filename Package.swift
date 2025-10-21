// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "VIPAPP",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "VIPAPP", targets: ["VIPAPP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "VIPAPP",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections")
                // or .product(name: "Collections", package: "swift-collections")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VIPAPPTests",
            dependencies: ["VIPAPP"]
        )
    ]
)
