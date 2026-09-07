import Foundation

/// Append-only diagnostic log at ~/Library/Logs/AppMute/agent.log
enum AgentLog {
  private static let queue = DispatchQueue(label: "com.kr3t3n.app-mute.log")
  private static let directory = (NSHomeDirectory() as NSString)
    .appendingPathComponent("Library/Logs/AppMute")
  private static let path = (directory as NSString).appendingPathComponent("agent.log")
  private static let latestPath = (NSHomeDirectory() as NSString)
    .appendingPathComponent("Library/Application Support/AppMute/latest-log.txt")

  static func info(_ message: String, fields: [String: Any] = [:]) {
    write(level: "INFO", message: message, fields: fields)
  }

  static func error(_ message: String, fields: [String: Any] = [:]) {
    write(level: "ERROR", message: message, fields: fields)
  }

  static func write(level: String, message: String, fields: [String: Any]) {
    queue.async {
      try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      var payload: [String: Any] = [
        "ts": isoNow(),
        "level": level,
        "msg": message,
      ]
      for (key, value) in fields {
        payload[key] = value
      }
      guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let line = String(data: data, encoding: .utf8)
      else { return }

      let text = line + "\n"
      if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
      }
      guard let handle = FileHandle(forWritingAtPath: path) else { return }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      if let bytes = text.data(using: .utf8) {
        try? handle.write(contentsOf: bytes)
      }

      // Small rolling snapshot for quick paste / remote read.
      if let existing = try? String(contentsOfFile: latestPath, encoding: .utf8) {
        let combined = existing + text
        let trimmed = combined.split(separator: "\n").suffix(200).joined(separator: "\n") + "\n"
        try? trimmed.write(toFile: latestPath, atomically: true, encoding: .utf8)
      } else {
        try? text.write(toFile: latestPath, atomically: true, encoding: .utf8)
      }
    }
  }

  private static func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}
