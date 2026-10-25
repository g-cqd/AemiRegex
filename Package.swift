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

// Dev tooling is gated behind AEMIREGEX_DEV, as in the sibling packages, so consumers never resolve it. The Aemi package
// supplies the shared `format` / `lint` plugins that the shared CI workflow runs. Pinned to one revision, like AemiJSON.
let isDev = Context.environment["AEMIREGEX_DEV"] != nil
var packageDependencies: [Package.Dependency] = []
if isDev {
    packageDependencies.append(
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "785c6b25cb3f4dc16ca2334fd69428fae4ee0b01"))
}

let package = Package(
    name: "AemiRegex",
    // The floor matches AemiJSON and Aemi (`Synchronization`'s `Mutex`/`Atomic` need these releases).
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AemiRegex", targets: ["AemiRegex"])
    ],
    dependencies: packageDependencies,
    targets: [
        // The multi-literal prefilter kernel: NEON `tbl` and SSSE3 `pshufb` nibble lookups, which Swift SIMD cannot express. A probe
        // measured 3.3 to 6.1x over the best Swift version at 100 MB on arm64 (docs/research/neon-assembly-2026-10.md).
        .target(name: "CAemiRegex"),
        // No package dependencies and no Foundation: a pattern is parsed, compiled and matched over UTF-8 bytes.
        .target(name: "AemiRegex", dependencies: ["CAemiRegex"], swiftSettings: kernelSettings),
        .testTarget(
            name: "AemiRegexTests",
            dependencies: ["AemiRegex"],
            resources: [.copy("Resources")],
            swiftSettings: strictSettings)
    ]
)

// The comparison benchmark (AemiRegex against NSRegularExpression and Swift's Regex) is dev-only, like the siblings' suites:
//   AEMIREGEX_DEV=1 swift run -c release AemiRegexBench [corpus-directory]
if Context.environment["AEMIREGEX_DEV"] != nil {
    package.targets.append(
        .executableTarget(
            name: "AemiRegexBench",
            dependencies: ["AemiRegex"],
            path: "Benchmarks/AemiRegexBench",
            swiftSettings: strictSettings))
}
