import AppKit
import Foundation

/// Menu bar indicator for muted apps. macOS has no public API to badge another app's Dock icon.
@MainActor
final class MenuBarController {
  static let shared = MenuBarController()

  private var statusItem: NSStatusItem?
  private var mutedNames: [String: String] = [:]

  func start() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "🔇"
    item.button?.toolTip = "App Mute"
    statusItem = item
    reload()
  }

  func setMuted(key: String, name: String) {
    mutedNames[key] = name
    reload()
  }

  func setUnmuted(key: String) {
    mutedNames.removeValue(forKey: key)
    reload()
  }

  func clear() {
    mutedNames.removeAll()
    reload()
  }

  func reload() {
    guard let statusItem else { return }
    let count = mutedNames.count
    statusItem.button?.title = count == 0 ? "♪" : "🔇\(count)"
    statusItem.button?.toolTip = count == 0 ? "App Mute — nothing muted" : "App Mute — \(count) muted"

    let menu = NSMenu()
    if count == 0 {
      menu.addItem(withTitle: "Nothing muted", action: nil, keyEquivalent: "")
    } else {
      let header = NSMenuItem(title: "Muted apps", action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      menu.addItem(.separator())
      for (key, name) in mutedNames.sorted(by: { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }) {
        let item = NSMenuItem(title: "Unmute \(name)", action: #selector(unmuteFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key
        menu.addItem(item)
      }
      menu.addItem(.separator())
      let unmuteAll = NSMenuItem(title: "Unmute All", action: #selector(unmuteAllFromMenu), keyEquivalent: "")
      unmuteAll.target = self
      menu.addItem(unmuteAll)
    }
    menu.addItem(.separator())
    menu.addItem(withTitle: "App Mute Agent", action: nil, keyEquivalent: "").isEnabled = false
    statusItem.menu = menu
  }

  @objc private func unmuteFromMenu(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    NotificationCenter.default.post(name: .appMuteUnmuteRequested, object: key)
  }

  @objc private func unmuteAllFromMenu() {
    NotificationCenter.default.post(name: .appMuteUnmuteAllRequested, object: nil)
  }
}

extension Notification.Name {
  static let appMuteUnmuteRequested = Notification.Name("appMuteUnmuteRequested")
  static let appMuteUnmuteAllRequested = Notification.Name("appMuteUnmuteAllRequested")
}
