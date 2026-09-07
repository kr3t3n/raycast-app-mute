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
    signal(SIGPIPE, SIG_IGN)

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

      autoreleasepool {
        let requestData = readAll(from: client)
        if !requestData.isEmpty,
           let request = try? JSONDecoder().decode(Request.self, from: requestData)
        {
          let result = handle(request)
          _ = writeAll(result, to: client)
        }
      }
      close(client)
    }
  }

  private func readAll(from fd: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = read(fd, &buffer, buffer.count)
      if count <= 0 { break }
      data.append(contentsOf: buffer.prefix(count))
      if data.count > 1_000_000 { break }
    }
    return data
  }

  private func writeAll(_ data: Data, to fd: Int32) -> Bool {
    data.withUnsafeBytes { raw in
      guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
      var offset = 0
      let total = data.count
      while offset < total {
        let written = write(fd, base.advanced(by: offset), total - offset)
        if written <= 0 {
          if errno == EINTR { continue }
          return false
        }
        offset += written
      }
      return true
    }
  }
}
