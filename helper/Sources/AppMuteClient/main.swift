import Darwin
import Foundation

// Decodes one base64 JSON request, ensures AppMuteAgent is listening, sends the
// request over the per-user control socket, and prints the JSON response.

let supportDir = (NSHomeDirectory() as NSString)
  .appendingPathComponent("Library/Application Support/AppMute")
let socketPath = (supportDir as NSString).appendingPathComponent("control.sock")
let agentPath = (supportDir as NSString)
  .appendingPathComponent("AppMuteAgent.app/Contents/MacOS/AppMuteAgent")

guard CommandLine.arguments.count == 2,
      let requestData = Data(base64Encoded: CommandLine.arguments[1])
else {
  fputs("usage: app-mute-client <base64-json>\n", stderr)
  exit(64)
}

func connectSocket() -> Int32? {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }

  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  _ = socketPath.withCString { source in
    withUnsafeMutablePointer(to: &address.sun_path) { destination in
      destination.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: address.sun_path)) {
        strncpy($0, source, MemoryLayout.size(ofValue: address.sun_path) - 1)
      }
    }
  }

  let length = socklen_t(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
  } == 0

  if ok { return fd }
  close(fd)
  return nil
}

func startAgentIfNeeded() {
  if connectSocket() != nil { return }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: agentPath)
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try? process.run()

  for _ in 0 ..< 50 {
    Thread.sleep(forTimeInterval: 0.05)
    if connectSocket() != nil { return }
  }
}

startAgentIfNeeded()

guard let fd = connectSocket() else {
  fputs("{\"code\":\"AGENT_UNAVAILABLE\",\"message\":\"AppMuteAgent could not start.\",\"data\":null}\n", stdout)
  exit(1)
}

_ = requestData.withUnsafeBytes { write(fd, $0.baseAddress, requestData.count) }
var buffer = [UInt8](repeating: 0, count: 65_536)
let count = read(fd, &buffer, buffer.count)
close(fd)

if count > 0 {
  FileHandle.standardOutput.write(Data(buffer.prefix(count)))
} else {
  fputs("{\"code\":\"AGENT_UNAVAILABLE\",\"message\":\"AppMuteAgent returned no data.\",\"data\":null}\n", stdout)
  exit(1)
}
