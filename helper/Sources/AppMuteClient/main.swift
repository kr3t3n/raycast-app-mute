import Darwin
import Foundation
import AppMuteCore

// Decodes one base64 JSON request, ensures AppMuteAgent is listening via launchd,
// sends the request over the per-user control socket, and prints the JSON response.

signal(SIGPIPE, SIG_IGN)

let supportDir = (NSHomeDirectory() as NSString)
  .appendingPathComponent("Library/Application Support/AppMute")
let socketPath = (supportDir as NSString).appendingPathComponent("control.sock")
let agentLabel = "gui/\(getuid())/com.kr3t3n.app-mute-agent"
let launchAgentPlist = (NSHomeDirectory() as NSString)
  .appendingPathComponent("Library/LaunchAgents/com.kr3t3n.app-mute-agent.plist")

guard CommandLine.arguments.count == 2,
      let requestData = Data(base64Encoded: CommandLine.arguments[1])
else {
  fputs("usage: app-mute-client <base64-json>\n", stderr)
  exit(64)
}

func connectSocket() -> Int32? {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }

  var address = UnixSocketAddress.make(path: socketPath)
  let length = socklen_t(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
  } == 0

  if ok { return fd }
  close(fd)
  return nil
}

func runLaunchctl(_ arguments: [String]) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  process.arguments = arguments
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try? process.run()
  process.waitUntilExit()
}

func ensureAgent() {
  if let existing = connectSocket() {
    close(existing)
    return
  }

  if FileManager.default.fileExists(atPath: launchAgentPlist) {
    runLaunchctl(["kickstart", "-k", agentLabel])
  }

  for _ in 0 ..< 100 {
    Thread.sleep(forTimeInterval: 0.05)
    if let ready = connectSocket() {
      close(ready)
      return
    }
  }
}

func readAll(from fd: Int32) -> Data {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 64 * 1024)
  while true {
    let count = read(fd, &buffer, buffer.count)
    if count <= 0 { break }
    data.append(contentsOf: buffer.prefix(count))
    if data.count > 8_000_000 { break }
  }
  return data
}

ensureAgent()

guard let fd = connectSocket() else {
  fputs(
    "{\"code\":\"AGENT_UNAVAILABLE\",\"message\":\"AppMuteAgent could not start. Run npm run agent:build.\",\"data\":null}\n",
    stdout
  )
  exit(1)
}

_ = requestData.withUnsafeBytes { raw in
  guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
  var offset = 0
  while offset < requestData.count {
    let written = write(fd, base.advanced(by: offset), requestData.count - offset)
    if written <= 0 { break }
    offset += written
  }
}
shutdown(fd, SHUT_WR)

let responseData = readAll(from: fd)
close(fd)

if !responseData.isEmpty {
  FileHandle.standardOutput.write(responseData)
  if responseData.last != UInt8(ascii: "\n") {
    FileHandle.standardOutput.write(Data([UInt8(ascii: "\n")]))
  }
} else {
  fputs(
    "{\"code\":\"AGENT_UNAVAILABLE\",\"message\":\"AppMuteAgent returned no data.\",\"data\":null}\n",
    stdout
  )
  exit(1)
}
