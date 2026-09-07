// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "AppMuteAgent",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "AppMuteAgent", targets: ["AppMuteAgent"]),
    .executable(name: "app-mute-client", targets: ["AppMuteClient"]),
  ],
  targets: [
    .target(name: "AppMuteCore", path: "Sources/AppMuteCore"),
    .executableTarget(
      name: "AppMuteAgent",
      dependencies: ["AppMuteCore"],
      path: "Sources/AppMuteAgent"
    ),
    .executableTarget(
      name: "AppMuteClient",
      dependencies: ["AppMuteCore"],
      path: "Sources/AppMuteClient"
    ),
    .testTarget(
      name: "AppMuteAgentTests",
      dependencies: ["AppMuteCore"],
      path: "Tests/AppMuteAgentTests"
    ),
  ]
)
