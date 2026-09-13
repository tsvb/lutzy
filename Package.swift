// swift-tools-version: 6.2
import PackageDescription

// LUTzy is split into a library plus a thin `@main` executable so the app's own
// code can be unit-tested: `@testable` cannot import an executable target.
// Everything of substance lives in LUTzyKit; the LUTzy target is just the entry
// point, the app delegate, and the asset catalog.
let package = Package(
    name: "LUTzy",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "LUTzy", targets: ["LUTzy"]),
        .library(name: "LUTzyKit", targets: ["LUTzyKit"]),
    ],
    targets: [
        .target(
            name: "LUTzyKit",
            swiftSettings: [.swiftLanguageMode(.v6)],
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
        .testTarget(
            name: "LUTzyKitTests",
            dependencies: ["LUTzyKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
