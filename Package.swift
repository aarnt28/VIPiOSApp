// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VIPAPP",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "VIPAPP", targets: ["VIPAPP"])
    ],
    // Declare external packages here
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "VIPAPP",
            // Targets depend on products from your dependencies
            dependencies: [
                .product(name: "Collections", package: "swift-collections")
                // or use a specific module:
                // .product(name: "OrderedCollections", package: "swift-collections")
            ],
            resources: [
                .process("Resources") // path is Sources/VIPAPP/Resources
            ]
        ),
        .testTarget(
            name: "VIPAPPTests",
            dependencies: ["VIPAPP"]
        )
    ]
)
