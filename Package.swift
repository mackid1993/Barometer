// swift-tools-version: 6.4

import Foundation
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"]),
]
let cSafetySettings: [CSetting] = [
    .unsafeFlags([
        "-ftrivial-auto-var-init=zero",
        "-Werror=return-type",
        "-Wuninitialized",
        "-Wconditional-uninitialized",
        "-Wimplicit-fallthrough",
        "-Wshorten-64-to-32",
        "-Werror=implicit-function-declaration",
        "-Wshadow",
        "-Wempty-body",
        "-Wbuiltin-memcpy-chk-size",
        "-Wformat-nonliteral",
        "-Warray-bounds",
        "-Warray-bounds-pointer-arithmetic",
        "-Wsuspicious-memaccess",
        "-Wsizeof-array-div",
        "-Wsizeof-pointer-div",
        "-Wreturn-stack-address",
        "-Wconversion",
        "-Wassign-enum",
        "-Wsign-compare",
    ]),
]

let developerDirectory =
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Applications/Xcode.app/Contents/Developer"
let xcodePlatformFrameworks =
    "\(developerDirectory)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
let commandLineToolsFrameworks = "\(developerDirectory)/Library/Developer/Frameworks"
let selectedToolchainFrameworks = FileManager.default.fileExists(atPath: xcodePlatformFrameworks)
    ? xcodePlatformFrameworks
    : commandLineToolsFrameworks
let testSwiftSettings = strictConcurrency + [
    .unsafeFlags([
        "-F", selectedToolchainFrameworks,
        "-Xfrontend", "-disable-cross-import-overlays",
    ]),
]
let testLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-F", selectedToolchainFrameworks,
        "-Xlinker", "-rpath",
        "-Xlinker", selectedToolchainFrameworks,
    ]),
]

let package = Package(
    name: "Barometer",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "Barometer", targets: ["Barometer"]),
        .executable(name: "mbs-probe", targets: ["mbs-probe"]),
        .library(name: "MenuBarStatsCore", targets: ["MenuBarStatsCore"]),
        .library(name: "MenuBarStatsUI", targets: ["MenuBarStatsUI"]),
        .library(name: "SystemSources", targets: ["SystemSources"]),
    ],
    targets: [
        .target(
            name: "CSystemSources",
            publicHeadersPath: "include",
            cSettings: cSafetySettings,
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
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(
            name: "MenuBarStatsCore",
            dependencies: ["SystemSources"],
            swiftSettings: strictConcurrency,
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "MenuBarStatsUI",
            dependencies: ["MenuBarStatsCore"],
            swiftSettings: strictConcurrency,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "Barometer",
            dependencies: ["MenuBarStatsUI"],
            path: "Sources/MenuBarStatsApp",
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "mbs-probe",
            dependencies: ["MenuBarStatsCore", "SystemSources"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "MenuBarStatsCoreTests",
            dependencies: ["MenuBarStatsCore"],
            resources: [
                .process("Fixtures"),
            ],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
        .testTarget(
            name: "SystemSourcesTests",
            dependencies: ["SystemSources"],
            swiftSettings: testSwiftSettings
        ),
        .testTarget(
            name: "MenuBarStatsUITests",
            dependencies: ["MenuBarStatsUI"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
