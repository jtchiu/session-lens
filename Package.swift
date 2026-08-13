// swift-tools-version: 6.0
import Foundation
import PackageDescription

let developerDirectory =
  ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
  ?? "/Library/Developer/CommandLineTools"
let developerFrameworks = "\(developerDirectory)/Library/Developer/Frameworks"
let developerTestingLibraries = "\(developerDirectory)/Library/Developer/usr/lib"

let package = Package(
  name: "SessionLens",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SessionLensCore", targets: ["SessionLensCore"]),
    .executable(name: "SessionLens", targets: ["SessionLens"]),
    .executable(name: "SessionLensClaudeBridge", targets: ["SessionLensClaudeBridge"]),
  ],
  targets: [
    .target(name: "SessionLensCore"),
    .executableTarget(
      name: "SessionLens",
      dependencies: ["SessionLensCore"],
      resources: [.process("Resources")]
    ),
    .executableTarget(name: "SessionLensClaudeBridge", dependencies: ["SessionLensCore"]),
    .testTarget(
      name: "SessionLensCoreTests",
      dependencies: ["SessionLensCore"],
      swiftSettings: [
        .unsafeFlags(["-F", developerFrameworks])
      ],
      linkerSettings: [
        .linkedFramework("Testing"),
        .unsafeFlags([
          "-F", developerFrameworks,
          "-Xlinker", "-rpath",
          "-Xlinker", developerFrameworks,
          "-Xlinker", "-rpath",
          "-Xlinker", developerTestingLibraries,
        ]),
      ]
    ),
  ]
)
