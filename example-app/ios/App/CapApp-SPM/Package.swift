// swift-tools-version: 5.9
import PackageDescription

// DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.0.0"),
        .package(name: "CapacitorFilesystem", path: "../../../node_modules/.bun/@capacitor+filesystem@8.0.0+15e98482558ccfe6/node_modules/@capacitor/filesystem"),
        .package(name: "CapgoCapacitorAudioRecorder", path: "../../../node_modules/.bun/@capgo+capacitor-audio-recorder@file+../node_modules/@capgo/capacitor-audio-recorder")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "CapacitorFilesystem", package: "CapacitorFilesystem"),
                .product(name: "CapgoCapacitorAudioRecorder", package: "CapgoCapacitorAudioRecorder")
            ]
        )
    ]
)
