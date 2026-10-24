// swift-tools-version: 6.4
import PackageDescription

// Same strictness as the AemiJSON family: Swift 6 mode (complete concurrency checking), warnings as errors,
// and the upcoming features that tighten existentials and imports. No unsafe flags, so the library can be
// consumed through a version-pinned requirement.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

// The engine reads attacker-controlled bytes, so every unsafe construct in it must be marked `unsafe`.
let kernelSettings: [SwiftSetting] = strictSettings + [.strictMemorySafety()]

let package = Package(
    name: "AemiRegex",
    // The floor matches AemiJSON and Aemi (`Synchronization`'s `Mutex`/`Atomic` need these releases).
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AemiRegex", targets: ["AemiRegex"])
    ],
    targets: [
        // Zero package dependencies and no Foundation: a pattern is parsed, compiled and matched over UTF-8 bytes.
        .target(name: "AemiRegex", swiftSettings: kernelSettings),
        .testTarget(
            name: "AemiRegexTests",
            dependencies: ["AemiRegex"],
            resources: [.copy("Resources")],
            swiftSettings: strictSettings)
    ]
)
