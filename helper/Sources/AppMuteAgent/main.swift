import AppKit
import CoreAudio
import Foundation
import AppMuteCore

// Serves JSON request/response over a Unix domain socket at
// ~/Library/Application Support/AppMute/control.sock (mode 0600, current uid).

let registry = MuteRegistry()

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

func relatedPIDs(for app: RunningApp) -> Set<pid_t> {
  var pids: Set<pid_t> = [app.pid]
  if let bundleID = app.bundleID {
    for other in NSWorkspace.shared.runningApplications {
      guard let otherBundle = other.bundleIdentifier else { continue }
      if otherBundle == bundleID || otherBundle.hasPrefix(bundleID + ".") {
        pids.insert(other.processIdentifier)
      }
    }
  }
  return pids
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
      AppRecord(
        id: app.id,
        name: app.name,
        bundleId: app.bundleID,
        path: app.path,
        executableName: app.executableName,
        running: true,
        hasAudio: false,
        muted: registry.records[app.id] != nil,
        iconPath: app.path
      )
    }
    return try! JSONEncoder().encode(Response(code: "OK", message: "OK", data: apps))

  case "set", "toggle":
    guard let appID = request.appID, let app = AppDiscovery.runningApps().first(where: { $0.id == appID }) else {
      return try! JSONEncoder().encode(response("NOT_RUNNING", "The app is not running."))
    }

    let targetMuted = request.operation == "toggle" ? registry.records[appID] == nil : request.muted == true

    if !targetMuted {
      runtime.taps.unmute(appID: appID)
      let code = registry.set(appID, muted: false, processes: [], now: Date())
      return try! JSONEncoder().encode(response(code, "Unmuted \(app.name)."))
    }

    let pids = relatedPIDs(for: app)
    let audioProcesses = ProcessTapController.processObjectIDs(matching: pids)
    do {
      try runtime.taps.mute(appID: appID, processObjectIDs: audioProcesses)
      let code = registry.set(appID, muted: true, processes: pids, now: Date())
      if code == "ALREADY_MUTED" {
        return try! JSONEncoder().encode(response("ALREADY_MUTED", "\(app.name) is already muted."))
      }
      return try! JSONEncoder().encode(response("OK", "Muted \(app.name)."))
    } catch TapError.noAudioSession {
      return try! JSONEncoder().encode(response("NO_AUDIO_SESSION", "\(app.name) has no audio session."))
    } catch {
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
