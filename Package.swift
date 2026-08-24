// swift-tools-version: 6.0
import PackageDescription

// LUTzy is split into a library plus a thin `@main` executable so the app's own
// code can be unit-tested: `@testable` cannot import an executable target.
// Everything of substance lives in LUTzyKit; the LUTzy target is just the entry
// point, the app delegate, and the asset catalog.
let package = Package(
    name: "LUTzy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LUTzy", targets: ["LUTzy"]),
        .executable(name: "lutcheck", targets: ["lutcheck"]),
        .library(name: "LUTzyKit", targets: ["LUTzyKit"]),
    ],
    targets: [
        .target(
            name: "LUTzyKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Lets the `lutcheck` verifier @testable-import the module, so
                // colour maths can be checked under the CLI toolchain without
                // XCTest (which needs a full Xcode this machine lacks).
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug)),
            ],
            linkerSettings: [
                .linkedFramework("PhotosUI"),
            ]
        ),
        .executableTarget(
            name: "LUTzy",
            dependencies: ["LUTzyKit"],
            exclude: ["Assets.xcassets", "LUTzy.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lutcheck",
            dependencies: ["LUTzyKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LUTzyKitTests",
            dependencies: ["LUTzyKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
