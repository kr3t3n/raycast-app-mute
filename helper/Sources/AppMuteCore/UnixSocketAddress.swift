import Darwin
import Foundation

public enum UnixSocketAddress {
  /// Fill a `sockaddr_un` without overlapping exclusive access to `sun_path`.
  public static func make(path: String) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    path.withCString { source in
      withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
        let maxCopy = max(capacity - 1, 0)
        let length = min(strlen(source), maxCopy)
        if length > 0, let base = raw.baseAddress {
          memcpy(base, source, length)
        }
      }
    }
    return address
  }
}
