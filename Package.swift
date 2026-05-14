// swift-tools-version: 6.0

import PackageDescription
import Foundation

let developerDirectoryCandidates = [
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
    "/Library/Developer/CommandLineTools",
    "/Applications/Xcode.app/Contents/Developer"
].compactMap { $0 }
let developerDirectory = developerDirectoryCandidates.first {
    FileManager.default.fileExists(atPath: "\($0)/Library/Developer/Frameworks/Testing.framework")
} ?? "/Library/Developer/CommandLineTools"
let developerFrameworksPath = "\(developerDirectory)/Library/Developer/Frameworks"
let developerTestingLibrariesPath = "\(developerDirectory)/Library/Developer/usr/lib"
let testingMacrosPath = "\(developerDirectory)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

let package = Package(
    name: "VibelslandFree",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VibelslandFreeCore", targets: ["VibelslandFreeCore"]),
        .executable(name: "VibelslandFree", targets: ["VibelslandFree"])
    ],
    targets: [
        .target(
            name: "VibelslandFreeCore"
        ),
        .executableTarget(
            name: "VibelslandFree",
            dependencies: ["VibelslandFreeCore"]
        ),
        .testTarget(
            name: "VibelslandFreeCoreTests",
            dependencies: ["VibelslandFreeCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", developerFrameworksPath,
                    "-load-plugin-library", testingMacrosPath
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", developerFrameworksPath,
                    "-L", developerTestingLibrariesPath,
                    "-Xlinker", "-rpath",
                    "-Xlinker", developerFrameworksPath,
                    "-Xlinker", "-rpath",
                    "-Xlinker", developerTestingLibrariesPath
                ])
            ]
        )
    ]
)
