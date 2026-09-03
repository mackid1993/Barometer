// swift-tools-version: 6.2

import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"]),
]

let commandLineToolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let testSwiftSettings = strictConcurrency + [
    .unsafeFlags(["-F", commandLineToolsFrameworks]),
]
let testLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-F", commandLineToolsFrameworks,
        "-Xlinker", "-rpath",
        "-Xlinker", commandLineToolsFrameworks,
    ]),
]

let package = Package(
    name: "MenuBarStats",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "MenuBarStatsApp", targets: ["MenuBarStatsApp"]),
        .executable(name: "mbs-probe", targets: ["mbs-probe"]),
        .library(name: "MenuBarStatsCore", targets: ["MenuBarStatsCore"]),
        .library(name: "MenuBarStatsUI", targets: ["MenuBarStatsUI"]),
        .library(name: "SystemSources", targets: ["SystemSources"]),
    ],
    targets: [
        .target(
            name: "CSystemSources",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "SystemSources",
            dependencies: ["CSystemSources"],
            swiftSettings: strictConcurrency,
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(
            name: "MenuBarStatsCore",
            dependencies: ["SystemSources"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "MenuBarStatsUI",
            dependencies: ["MenuBarStatsCore"],
            swiftSettings: strictConcurrency,
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "MenuBarStatsApp",
            dependencies: ["MenuBarStatsUI"],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "mbs-probe",
            dependencies: ["MenuBarStatsCore"],
            swiftSettings: strictConcurrency,
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "MenuBarStatsCoreTests",
            dependencies: ["MenuBarStatsCore"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
        .testTarget(
            name: "SystemSourcesTests",
            dependencies: ["SystemSources"],
            swiftSettings: testSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
