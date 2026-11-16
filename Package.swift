// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PodBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PodBar", targets: ["PodBar"])],
    targets: [
        .target(name: "PodBarCore"),
        .executableTarget(name: "PodBar", dependencies: ["PodBarCore"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement"),
                                           .linkedFramework("IOBluetooth")]),
        .testTarget(name: "PodBarCoreTests", dependencies: ["PodBarCore"])
    ]
)
