// swift-tools-version: 6.4
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let kernelSettings: [SwiftSetting] = strictSettings + [.strictMemorySafety()]

let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "340c49040faa49313d5632003d8224d9d0084fb0")
]

let package = Package(
    name: "AemiRegex",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AemiRegex", targets: ["AemiRegex"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "AemiRegex",
            dependencies: [
                .product(name: "AemiKernels", package: "aemi"), .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiUnicode", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: kernelSettings
        ),
        .testTarget(
            name: "AemiRegexTests",
            dependencies: ["AemiRegex", .product(name: "AemiKernel", package: "aemi")],
            resources: [.copy("Resources")],
            swiftSettings: strictSettings
        )
    ]
)

if Context.environment["AEMIREGEX_DEV"] != nil {
    package.targets.append(
        .executableTarget(
            name: "AemiRegexBench",
            dependencies: ["AemiRegex"],
            path: "Benchmarks/AemiRegexBench",
            swiftSettings: strictSettings
        )
    )
}
