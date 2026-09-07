import AppKit
import CoreAudio
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
  return nil
}

func registryKey(for app: RunningApp) -> String {
  app.bundleID ?? app.id
}

func handle(_ request: Request) -> Data {
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
      let matches = ProcessTapController.matches(for: app)
      return AppRecord(
        id: key,
        name: app.name,
        bundleId: app.bundleID,
        path: app.path,
        executableName: app.executableName,
        running: true,
        hasAudio: matches.contains(where: \.isRunningOutput),
        muted: registry.records[key] != nil,
        iconPath: app.path
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
    let targetMuted = request.operation == "toggle" ? registry.records[key] == nil : request.muted == true

    if !targetMuted {
      runtime.taps.unmute(appID: key)
      let code = registry.set(key, muted: false, processes: [], now: Date())
      writeLastAction(["operation": "unmute", "app": app.name, "key": key, "code": code])
      return try! JSONEncoder().encode(response(code, "Unmuted \(app.name)."))
    }

    let matches = ProcessTapController.matches(for: app)
    let audioProcesses = ProcessTapController.processObjectIDs(for: app)
    writeLastAction([
      "operation": "mute",
      "app": app.name,
      "key": key,
      "matchedCount": matches.count,
      "outputtingCount": matches.filter(\.isRunningOutput).count,
      "tappedObjectIDs": audioProcesses,
      "matches": matches.map { match -> [String: Any] in
        [
          "objectID": match.objectID,
          "pid": match.pid,
          "path": match.path as Any,
          "isRunningOutput": match.isRunningOutput,
        ]
      },
    ])

    do {
      try runtime.taps.mute(appID: key, processObjectIDs: audioProcesses)
      let pids = Set(matches.map(\.pid))
      let code = registry.set(key, muted: true, processes: pids, now: Date())
      if code == "ALREADY_MUTED" {
        return try! JSONEncoder().encode(response("ALREADY_MUTED", "\(app.name) is already muted."))
      }
      let message =
        "Muted \(app.name) (\(audioProcesses.count) audio process\(audioProcesses.count == 1 ? "" : "es"))."
      writeLastAction([
        "operation": "mute",
        "app": app.name,
        "key": key,
        "code": "OK",
        "tappedObjectIDs": audioProcesses,
        "matchedCount": matches.count,
        "outputtingCount": matches.filter(\.isRunningOutput).count,
      ])
      return try! JSONEncoder().encode(response("OK", message))
    } catch TapError.noAudioSession {
      writeLastAction(["operation": "mute", "app": app.name, "code": "NO_AUDIO_SESSION", "matchedCount": matches.count])
      return try! JSONEncoder().encode(
        response("NO_AUDIO_SESSION", "\(app.name) has no audio session. Play sound in the app, then try again.")
      )
    } catch TapError.rejected(let status) {
      writeLastAction(["operation": "mute", "app": app.name, "code": "TAP_REJECTED", "status": status])
      return try! JSONEncoder().encode(
        response("TAP_REJECTED", "macOS could not mute \(app.name) (status \(status)).")
      )
    } catch {
      writeLastAction(["operation": "mute", "app": app.name, "code": "TAP_REJECTED"])
      return try! JSONEncoder().encode(response("TAP_REJECTED", "macOS could not mute \(app.name)."))
    }

  case "stop":
    runtime.taps.releaseAll()
    return try! JSONEncoder().encode(response("OK", "Agent stopped."))

  default:
    return try! JSONEncoder().encode(response("AGENT_UNAVAILABLE", "Unknown operation."))
  }
}

SocketServer(handle: handle).run()
