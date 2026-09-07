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
    if let button = item.button {
      button.title = "♪"
      button.toolTip = "App Mute"
    }
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

  private var sortedMuted: [(key: String, name: String)] {
    mutedNames
      .map { (key: $0.key, name: $0.value) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  func reload() {
    guard let statusItem else { return }
    let apps = sortedMuted
    let count = apps.count

    statusItem.button?.title = count == 0 ? "♪" : "🔇\(count)"
    statusItem.button?.toolTip = hoverText(for: apps)

    let menu = NSMenu()
    menu.autoenablesItems = false

    if count == 0 {
      let empty = NSMenuItem(title: "Nothing muted", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      let header = NSMenuItem(title: "Muted — click to unmute", action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      menu.addItem(.separator())

      for app in apps {
        let item = NSMenuItem(
          title: app.name,
          action: #selector(unmuteFromMenu(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = app.key
        item.isEnabled = true
        item.toolTip = "Unmute \(app.name)"
        menu.addItem(item)
      }

      menu.addItem(.separator())
      let unmuteAll = NSMenuItem(
        title: "Unmute All",
        action: #selector(unmuteAllFromMenu),
        keyEquivalent: ""
      )
      unmuteAll.target = self
      unmuteAll.isEnabled = true
      menu.addItem(unmuteAll)
    }

    menu.addItem(.separator())
    let footer = NSMenuItem(title: "App Mute", action: nil, keyEquivalent: "")
    footer.isEnabled = false
    menu.addItem(footer)

    statusItem.menu = menu
  }

  private func hoverText(for apps: [(key: String, name: String)]) -> String {
    if apps.isEmpty {
      return "App Mute — nothing muted"
    }
    let names = apps.map(\.name).joined(separator: "\n")
    return "Muted:\n\(names)\n\nClick for menu"
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
