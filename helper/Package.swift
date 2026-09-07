// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "AppMuteAgent",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "AppMuteAgent", targets: ["AppMuteAgent"]), .executable(name: "app-mute-client", targets: ["AppMuteClient"])],
  targets: [
    .executableTarget(name: "AppMuteAgent", path: "Sources/AppMuteAgent"),
    .executableTarget(name: "AppMuteClient", path: "Sources/AppMuteClient"),
    .testTarget(name: "AppMuteAgentTests", dependencies: ["AppMuteAgent"], path: "Tests/AppMuteAgentTests")
  ]
)
