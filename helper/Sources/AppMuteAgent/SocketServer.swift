import Darwin
import Foundation
import AppMuteCore

final class SocketServer {
  private let handle: (Request) -> Data
  private let path = (NSHomeDirectory() as NSString)
    .appendingPathComponent("Library/Application Support/AppMute/control.sock")

  init(handle: @escaping (Request) -> Data) {
    self.handle = handle
  }

  func run() {
    try? FileManager.default.createDirectory(
      atPath: (path as NSString).deletingLastPathComponent,
      withIntermediateDirectories: true
    )
    unlink(path)

    let server = socket(AF_UNIX, SOCK_STREAM, 0)
    guard server >= 0 else { return }

    var address = UnixSocketAddress.make(path: path)
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    guard withUnsafePointer(to: &address, {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, length) }
    }) == 0 else {
      close(server)
      return
    }

    chmod(path, S_IRUSR | S_IWUSR)
    guard listen(server, 16) == 0 else {
      close(server)
      return
    }

    while true {
      let client = accept(server, nil, nil)
      guard client >= 0 else { continue }

      var peerUID: uid_t = 0
      var peerGID: gid_t = 0
      guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == getuid() else {
        close(client)
        continue
      }

      var bytes = [UInt8](repeating: 0, count: 65_536)
      let count = read(client, &bytes, bytes.count)
      if count > 0, let request = try? JSONDecoder().decode(Request.self, from: Data(bytes.prefix(count))) {
        let result = handle(request)
        _ = result.withUnsafeBytes { write(client, $0.baseAddress, result.count) }
      }
      close(client)
    }
  }
}
