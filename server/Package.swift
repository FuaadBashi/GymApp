// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BashiServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.25.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "5.1.0"),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "PostgresNIO", package: "postgres-nio"),
            .product(name: "JWT", package: "jwt"),
        ]),
        .executableTarget(name: "Run", dependencies: ["App"]),
        .testTarget(name: "AppTests", dependencies: [
            "App",
            .product(name: "XCTVapor", package: "vapor"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
