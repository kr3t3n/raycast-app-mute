import AppKit
import CoreAudio
import Darwin
import Foundation
import AppMuteCore

// Serves JSON request/response over a Unix domain socket at
// ~/Library/Application Support/AppMute/control.sock (mode 0600, current uid).

let registry = MuteRegistry()
let supportDir = (NSHomeDirectory() as NSString)
  .appendingPathComponent("Library/Application Support/AppMute")
let lastActionPath = (supportDir as NSString).appendingPathComponent("last-action.json")

@available(macOS 14.2, *)
final class AgentRuntime {
  let taps = ProcessTapController()
}

@available(macOS 14.2, *)
enum AgentRuntimeHolder {
  static let shared = AgentRuntime()
}

func response(_ code: String, _ message: String) -> Response<String> {
  Response(code: code, message: message, data: nil)
}

func writeLastAction(_ payload: [String: Any]) {
  try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
  guard JSONSerialization.isValidJSONObject(payload),
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  else { return }
  try? data.write(to: URL(fileURLWithPath: lastActionPath), options: .atomic)
  AgentLog.info("lastAction", fields: payload)
}

func findRunningApp(request: Request) -> RunningApp? {
  let apps = AppDiscovery.runningApps()
  let candidates = [request.appID, request.bundleId, request.path].compactMap { $0 }
  for key in candidates {
    if let match = apps.first(where: { $0.id == key || $0.bundleID == key || $0.path == key }) {
      return match
    }
  }
  if let path = request.path ?? request.appID, path.hasSuffix(".app") {
    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    return apps.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }
  for key in candidates {
    if let match = apps.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
      return match
    }
    if let match = apps.first(where: { $0.name.localizedCaseInsensitiveContains(key) }) {
      return match
    }
  }
  return nil
}

func findRunningApp(target: MuteArming.Target) -> RunningApp? {
  let apps = AppDiscovery.runningApps()
  if let match = apps.first(where: { $0.bundleID == target.bundleID || $0.id == target.key || $0.path == target.path }) {
    return match
  }
  return apps.first { $0.name.caseInsensitiveCompare(target.name) == .orderedSame }
}

func registryKey(for app: RunningApp) -> String {
  app.bundleID ?? app.id
}

func armTarget(for app: RunningApp, key: String) -> MuteArming.Target {
  MuteArming.Target(
    key: key,
    name: app.name,
    bundleID: app.bundleID,
    path: app.path,
    pid: app.pid
  )
}

func markMenuMuted(key: String, name: String) {
  DispatchQueue.main.async {
    MenuBarController.shared.setMuted(key: key, name: name)
  }
}

func markMenuUnmuted(key: String) {
  DispatchQueue.main.async {
    MenuBarController.shared.setUnmuted(key: key)
  }
}

@available(macOS 14.2, *)
func applyMuteTap(for app: RunningApp, key: String) throws -> Int {
  let matches = ProcessTapController.matches(for: app)
  let audioProcesses = ProcessTapController.processObjectIDs(for: app)
  try AgentRuntimeHolder.shared.taps.mute(appID: key, processObjectIDs: audioProcesses)
  let pids = Set(matches.map(\.pid))
  _ = registry.set(key, muted: false, processes: [], now: Date())
  _ = registry.set(key, muted: true, processes: pids, now: Date())
  return audioProcesses.count
}

@available(macOS 14.2, *)
func reconcileArmedMutes() {
  let runtime = AgentRuntimeHolder.shared
  for target in MuteArming.shared.all() {
    guard let app = findRunningApp(target: target) else { continue }
    let audioProcesses = ProcessTapController.processObjectIDs(for: app)
    guard !audioProcesses.isEmpty else { continue }

    let current = runtime.taps.tappedProcessObjectIDs(appID: target.key) ?? []
    if Set(current) == Set(audioProcesses) { continue }

    do {
      let count = try applyMuteTap(for: app, key: target.key)
      AgentLog.info("reconcile.attached", fields: [
        "key": target.key,
        "name": target.name,
        "processCount": count,
      ])
      markMenuMuted(key: target.key, name: target.name)
    } catch {
      AgentLog.error("reconcile.failed", fields: [
        "key": target.key,
        "error": String(describing: error),
      ])
    }
  }
}

func handle(_ request: Request) -> Data {
  AgentLog.info("request", fields: [
    "operation": request.operation,
    "appId": request.appID as Any,
    "bundleId": request.bundleId as Any,
    "path": request.path as Any,
    "muted": request.muted as Any,
  ])

  guard request.protocolVersion == supportedProtocolVersion else {
    return try! JSONEncoder().encode(response("PROTOCOL_MISMATCH", "AppMuteAgent needs reinstalling."))
  }

  guard #available(macOS 14.2, *) else {
    return try! JSONEncoder().encode(response("UNSUPPORTED_MACOS", "App mute needs macOS 14.2 or later."))
  }

  let runtime = AgentRuntimeHolder.shared

  switch request.operation {
  case "health":
    return try! JSONEncoder().encode(Response(code: "OK", message: "Agent is ready.", data: "1"))

  case "list":
    let apps = AppDiscovery.runningApps().map { app in
      let key = registryKey(for: app)
      return AppRecord(
        id: key,
        name: app.name,
        bundleId: app.bundleID,
        path: app.path,
        executableName: app.executableName,
        running: true,
        hasAudio: false,
        muted: registry.records[key] != nil || MuteArming.shared.contains(key),
        iconPath: nil
      )
    }
    let payload: Response<[AppRecord]> = Response(code: "OK", message: "OK", data: apps)
    return try! JSONEncoder().encode(payload)

  case "diagnose":
    guard let app = findRunningApp(request: request) else {
      return try! JSONEncoder().encode(response("NOT_RUNNING", "The app is not running."))
    }
    let matches = ProcessTapController.matches(for: app)
    let all = ProcessTapController.allAudioProcesses()
    let body: [String: Any] = [
      "app": [
        "name": app.name,
        "bundleId": app.bundleID as Any,
        "path": app.path as Any,
        "pid": app.pid,
      ],
      "armed": MuteArming.shared.contains(registryKey(for: app)),
      "sessions": runtime.taps.activeSessionSummary(),
      "matched": matches.map { match -> [String: Any] in
        [
          "objectID": match.objectID,
          "pid": match.pid,
          "path": match.path as Any,
          "isRunningOutput": match.isRunningOutput,
        ]
      },
      "allAudioProcesses": all.prefix(40).map { match -> [String: Any] in
        [
          "objectID": match.objectID,
          "pid": match.pid,
          "path": match.path as Any,
          "isRunningOutput": match.isRunningOutput,
        ]
      },
    ]
    writeLastAction(["operation": "diagnose", "result": body])
    let summary =
      "\(app.name): \(matches.count) matched, \(matches.filter(\.isRunningOutput).count) outputting, \(all.count) total audio processes."
    return try! JSONEncoder().encode(Response(code: "OK", message: summary, data: summary))

  case "set", "toggle":
    guard let app = findRunningApp(request: request) else {
      writeLastAction(["operation": request.operation, "code": "NOT_RUNNING"])
      return try! JSONEncoder().encode(response("NOT_RUNNING", "The app is not running."))
    }
    let key = registryKey(for: app)
    let targetMuted =
      request.operation == "toggle"
      ? (registry.records[key] == nil && !MuteArming.shared.contains(key))
      : request.muted == true

    if !targetMuted {
      runtime.taps.unmute(appID: key)
      MuteArming.shared.disarm(key)
      let code = registry.set(key, muted: false, processes: [], now: Date())
      writeLastAction(["operation": "unmute", "app": app.name, "key": key, "code": code])
      markMenuUnmuted(key: key)
      return try! JSONEncoder().encode(response(code, "Unmuted \(app.name)."))
    }

    let matches = ProcessTapController.matches(for: app)
    let audioProcesses = ProcessTapController.processObjectIDs(for: app)
    let target = armTarget(for: app, key: key)
    MuteArming.shared.arm(target)

    writeLastAction([
      "operation": "mute",
      "app": app.name,
      "key": key,
      "matchedCount": matches.count,
      "outputtingCount": matches.filter(\.isRunningOutput).count,
      "tappedObjectIDs": audioProcesses,
      "armed": true,
      "matches": matches.map { match -> [String: Any] in
        [
          "objectID": match.objectID,
          "pid": match.pid,
          "path": match.path as Any,
          "isRunningOutput": match.isRunningOutput,
        ]
      },
    ])

    if audioProcesses.isEmpty {
      _ = registry.set(key, muted: false, processes: [], now: Date())
      _ = registry.set(key, muted: true, processes: [], now: Date())
      markMenuMuted(key: key, name: app.name)
      writeLastAction([
        "operation": "mute",
        "app": app.name,
        "key": key,
        "code": "OK",
        "armed": true,
        "attached": false,
      ])
      return try! JSONEncoder().encode(
        response("OK", "Muted \(app.name) (armed — will silence when it plays audio).")
      )
    }

    do {
      let count = try applyMuteTap(for: app, key: key)
      markMenuMuted(key: key, name: app.name)
      writeLastAction([
        "operation": "mute",
        "app": app.name,
        "key": key,
        "code": "OK",
        "armed": true,
        "attached": true,
        "tappedObjectIDs": audioProcesses,
        "matchedCount": matches.count,
        "outputtingCount": matches.filter(\.isRunningOutput).count,
      ])
      return try! JSONEncoder().encode(
        response("OK", "Muted \(app.name) (\(count) audio process\(count == 1 ? "" : "es")).")
      )
    } catch TapError.rejected(let status) {
      // Keep armed so a later reconcile can attach.
      _ = registry.set(key, muted: false, processes: [], now: Date())
      _ = registry.set(key, muted: true, processes: [], now: Date())
      markMenuMuted(key: key, name: app.name)
      writeLastAction([
        "operation": "mute",
        "app": app.name,
        "code": "TAP_REJECTED",
        "status": status,
        "armed": true,
      ])
      return try! JSONEncoder().encode(
        response("OK", "Muted \(app.name) (armed — tap attach failed, will retry).")
      )
    } catch {
      _ = registry.set(key, muted: false, processes: [], now: Date())
      _ = registry.set(key, muted: true, processes: [], now: Date())
      markMenuMuted(key: key, name: app.name)
      return try! JSONEncoder().encode(
        response("OK", "Muted \(app.name) (armed — will silence when it plays audio).")
      )
    }

  case "stop":
    runtime.taps.releaseAll()
    MuteArming.shared.disarmAll()
    for key in Array(registry.records.keys) {
      _ = registry.set(key, muted: false, processes: [], now: Date())
    }
    DispatchQueue.main.async {
      MenuBarController.shared.clear()
    }
    return try! JSONEncoder().encode(response("OK", "Agent stopped."))

  default:
    return try! JSONEncoder().encode(response("AGENT_UNAVAILABLE", "Unknown operation."))
  }
}

func unmuteKey(_ key: String) {
  guard #available(macOS 14.2, *) else { return }
  AgentRuntimeHolder.shared.taps.unmute(appID: key)
  MuteArming.shared.disarm(key)
  _ = registry.set(key, muted: false, processes: [], now: Date())
  markMenuUnmuted(key: key)
  AgentLog.info("menu.unmute", fields: ["key": key])
}

AgentLog.info("agent.start", fields: [
  "pid": Int(getpid()),
  "macos": ProcessInfo.processInfo.operatingSystemVersionString,
])

NotificationCenter.default.addObserver(
  forName: .appMuteUnmuteRequested,
  object: nil,
  queue: .main
) { note in
  guard let key = note.object as? String else { return }
  unmuteKey(key)
}

NotificationCenter.default.addObserver(
  forName: .appMuteUnmuteAllRequested,
  object: nil,
  queue: .main
) { _ in
  for key in Array(Set(registry.records.keys).union(MuteArming.shared.all().map(\.key))) {
    unmuteKey(key)
  }
}

DispatchQueue.global(qos: .userInitiated).async {
  SocketServer(handle: handle).run()
}

if #available(macOS 14.2, *) {
  Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    reconcileArmedMutes()
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MenuBarController.shared.start()
AgentLog.info("agent.uiReady", fields: [:])
app.run()
