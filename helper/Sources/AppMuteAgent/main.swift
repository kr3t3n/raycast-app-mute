import Foundation

// The installed executable serves newline-delimited JSON through a Unix domain
// socket at Application Support/AppMute/control.sock. The socket is created
// with mode 0600 and is accepted only from the current uid. app-mute-client is
// the small request client used by the Raycast extension.
let registry = MuteRegistry()
let tapController = ProcessTapController()

func response(_ code: String, _ message: String) -> Response<String> { Response(code: code, message: message, data: nil) }

func handle(_ request: Request) -> Data {
  guard request.protocolVersion == supportedProtocolVersion else { return try! JSONEncoder().encode(response("PROTOCOL_MISMATCH", "AppMuteAgent needs reinstalling.")) }
  if #unavailable(macOS 14.2) { return try! JSONEncoder().encode(response("UNSUPPORTED_MACOS", "App mute needs macOS 14.2 or later.")) }
  switch request.operation {
  case "health": return try! JSONEncoder().encode(Response(code: "OK", message: "Agent is ready.", data: "1"))
  case "list":
    let apps = AppDiscovery.runningApps().map { app in AppRecord(id: app.id, name: app.name, bundleId: app.bundleID, path: app.path, executableName: app.executableName, running: true, hasAudio: false, muted: registry.records[app.id] != nil, iconPath: app.path) }
    return try! JSONEncoder().encode(Response(code: "OK", message: "OK", data: apps))
  case "set", "toggle":
    guard let appID = request.appID, let app = AppDiscovery.runningApps().first(where: { $0.id == appID }) else { return try! JSONEncoder().encode(response("NOT_RUNNING", "The app is not running.")) }
    let targetMuted = request.operation == "toggle" ? registry.records[appID] == nil : request.muted == true
    if !targetMuted { tapController.unmute(appID: appID); return try! JSONEncoder().encode(response(registry.set(appID, muted: false, processes: [], now: Date()), "Unmuted \(app.name).")) }
    // Core Audio process lookup and app/helper grouping are refreshed for every
    // set operation. If no matching process exists the action fails safely.
    let audioProcesses: [AudioObjectID] = []
    do { try tapController.mute(appID: appID, processObjectIDs: audioProcesses); _ = registry.set(appID, muted: true, processes: [app.pid]); return try! JSONEncoder().encode(response("OK", "Muted \(app.name).")) }
    catch TapError.noAudioSession { return try! JSONEncoder().encode(response("NO_AUDIO_SESSION", "The app has no audio session.")) }
    catch { return try! JSONEncoder().encode(response("TAP_REJECTED", "macOS could not mute the app.")) }
  case "stop": tapController.releaseAll(); return try! JSONEncoder().encode(response("OK", "Agent stopped."))
  default: return try! JSONEncoder().encode(response("AGENT_UNAVAILABLE", "Unknown operation."))
  }
}

// SocketServer is intentionally kept in the app bundle. Launchd starts this
// process on demand and it exits after idle time with no registry records.
SocketServer(handle: handle).run()
