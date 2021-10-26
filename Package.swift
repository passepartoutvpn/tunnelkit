// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TunnelKit",
    platforms: [
        .macOS(.v10_15), .iOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "TunnelKitCore",
            targets: ["TunnelKitCore"]
        ),
        .library(
            name: "TunnelKitAppExtension",
            targets: ["TunnelKitAppExtension"]
        ),
        .library(
            name: "TunnelKitManager",
            targets: ["TunnelKitManager"]
        ),
        .library(
            name: "TunnelKitNative",
            targets: ["TunnelKitNative"]
        ),
        .library(
            name: "TunnelKitOpenVPN",
            targets: ["TunnelKitOpenVPN"]
        ),
        .library(
            name: "TunnelKitLZO",
            targets: ["TunnelKitLZO"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver", from: "1.9.0"),
        .package(url: "https://github.com/keeshux/openssl-apple", from: "1.1.100")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "TunnelKitCore",
            dependencies: [
                "InternalUtils",
                "TunnelKitCoreObjC",
                "SwiftyBeaver"]),
        .target(
            name: "TunnelKitCoreObjC",
            dependencies: []),
        .target(
            name: "TunnelKitAppExtension",
            dependencies: [
                "TunnelKitCore",
                "SwiftyBeaver"]),
        .target(
            name: "TunnelKitManager",
            dependencies: [
                "TunnelKitCore"]),
        .target(
            name: "TunnelKitNative",
            dependencies: [
                "TunnelKitCore",
                "TunnelKitManager"]),
        .target(
            name: "TunnelKitOpenVPN",
            dependencies: [
                "TunnelKitCore",
                "TunnelKitOpenVPNObjC",
                "TunnelKitAppExtension",
                "TunnelKitManager"]),
        .target(
            name: "TunnelKitOpenVPNObjC",
            dependencies: [
                "TunnelKitCoreObjC",
                "openssl-apple"]),
        .target(
            name: "TunnelKitLZO",
            dependencies: [],
            exclude: [
                "lib/COPYING",
                "lib/Makefile",
                "lib/README.LZO"
            ]),
        .target(
            name: "InternalUtils",
            dependencies: []),
        .testTarget(
            name: "TunnelKitCoreTests",
            dependencies: [
                "TunnelKitCore",
                "TunnelKitCoreObjC"
            ]),
        .testTarget(
            name: "TunnelKitOpenVPNTests",
            dependencies: [
                "TunnelKitCoreTests",
                "TunnelKitOpenVPN",
                "TunnelKitOpenVPNObjC",
                "TunnelKitLZO"
            ],
            resources: [
                .process("Resources")
            ]),
        .testTarget(
            name: "TunnelKitLZOTests",
            dependencies: [
                "TunnelKitLZO"
            ]),
    ]
)