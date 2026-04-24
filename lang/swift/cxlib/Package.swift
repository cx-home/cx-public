// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cxlib",
    targets: [
        .systemLibrary(
            name: "CXC",
            path: "Sources/CXLib/include",
            pkgConfig: nil
        ),
        .target(
            name: "CXLib",
            dependencies: ["CXC"],
            path: "Sources/CXLib",
            exclude: ["include"],
            linkerSettings: [
                .linkedLibrary("cx"),
                .unsafeFlags(
                    ["-L../../../vcx/target", "-Xlinker", "-rpath", "-Xlinker", "../../../vcx/target"],
                    .when(platforms: [.macOS])
                ),
                .unsafeFlags(
                    ["-L../../../vcx/target", "-Xlinker", "-rpath", "-Xlinker", "../../../vcx/target"],
                    .when(platforms: [.linux])
                ),
            ]
        ),
        .executableTarget(
            name: "Demo",
            dependencies: ["CXLib"],
            path: "Sources/Demo"
        ),
        .executableTarget(
            name: "transform",
            dependencies: ["CXLib"],
            path: "Examples/transform"
        ),
        .executableTarget(
            name: "BenchTime",
            dependencies: ["CXLib"],
            path: "Sources/BenchTime"
        ),
        .testTarget(
            name: "ConformanceTests",
            dependencies: ["CXLib"],
            path: "Tests/ConformanceTests"
        ),
        .testTarget(
            name: "ApiTests",
            dependencies: ["CXLib"],
            path: "Tests/ApiTests"
        ),
    ]
)
