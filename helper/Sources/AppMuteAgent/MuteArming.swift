import AppKit
import Foundation

/// Remembers apps the user wants muted even before Core Audio shows a process.
final class MuteArming: @unchecked Sendable {
  struct Target: Equatable {
    let key: String
    let name: String
    let bundleID: String?
    let path: String?
    let pid: pid_t
  }

  static let shared = MuteArming()

  private let lock = NSLock()
  private var targets: [String: Target] = [:]

  func arm(_ target: Target) {
    lock.lock()
    targets[target.key] = target
    lock.unlock()
  }

  func disarm(_ key: String) {
    lock.lock()
    targets.removeValue(forKey: key)
    lock.unlock()
  }

  func disarmAll() {
    lock.lock()
    targets.removeAll()
    lock.unlock()
  }

  func all() -> [Target] {
    lock.lock()
    defer { lock.unlock() }
    return Array(targets.values)
  }

  func contains(_ key: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return targets[key] != nil
  }
}
