// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FoldContinuity",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FoldContinuity", targets: ["FoldContinuity"])
    ],
    targets: [
        .target(name: "FoldContinuity", path: "Sources/FoldContinuity"),
        .testTarget(
            name: "FoldContinuityTests",
            dependencies: ["FoldContinuity"],
            path: "Tests/FoldContinuityTests"
        )
    ]
)
