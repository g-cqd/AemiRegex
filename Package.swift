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

// Aemi supplies the byte kernels, UTF-8 reading, the Unicode tables and the scratch pool (ADR-0013), and the shared `format` / `lint`
// plugins the shared CI workflow runs. Pinned to one revision, like every Aemi-family package: AemiJSON, AemiMarkdown and TerminalKit pin
// the same one, since SwiftPM resolves one revision per package in a graph.
let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "a20fb18feff6a9ff54ebee5bb70f4bee126c9e8e")
]

let package = Package(
    name: "AemiRegex",
    // The floor matches AemiJSON and Aemi (`Synchronization`'s `Mutex`/`Atomic` need these releases).
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AemiRegex", targets: ["AemiRegex"])
    ],
    dependencies: packageDependencies,
    targets: [
        // No Foundation: a pattern is parsed, compiled and matched over UTF-8 bytes. The multi-literal kernel, the byte scans and the
        // Unicode data are Aemi's (ADR-0013).
        .target(
            name: "AemiRegex",
            dependencies: [
                .product(name: "AemiKernels", package: "aemi"), .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiUnicode", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: kernelSettings),
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
