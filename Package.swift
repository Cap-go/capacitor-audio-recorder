// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCapacitorAudioRecorder",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapgoCapacitorAudioRecorder",
            targets: ["CapacitorAudioRecorderPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CapacitorAudioRecorderPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CapacitorAudioRecorderPlugin"),
        .testTarget(
            name: "CapacitorAudioRecorderPluginTests",
            dependencies: ["CapacitorAudioRecorderPlugin"],
            path: "ios/Tests/CapacitorAudioRecorderPluginTests")
    ]
)
