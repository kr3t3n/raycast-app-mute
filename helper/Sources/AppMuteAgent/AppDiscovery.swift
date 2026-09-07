import AppKit

struct RunningApp {
  let id: String; let name: String; let bundleID: String?; let path: String?; let executableName: String?; let pid: pid_t
}

enum AppDiscovery {
  static func runningApps() -> [RunningApp] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.activationPolicy != .prohibited, let name = app.localizedName else { return nil }
      let path = app.bundleURL?.path
      return RunningApp(id: app.bundleIdentifier ?? path ?? "pid:\(app.processIdentifier)", name: name, bundleID: app.bundleIdentifier, path: path, executableName: app.executableURL?.lastPathComponent, pid: app.processIdentifier)
    }
  }
}
