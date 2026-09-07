import AppKit
import Foundation

/// Menu bar indicator for muted apps. macOS has no public API to badge another app's Dock icon.
final class MenuBarController: NSObject, NSMenuDelegate {
  static let shared = MenuBarController()

  private var statusItem: NSStatusItem?
  private var mutedNames: [String: String] = [:]

  func start() {
    assert(Thread.isMainThread)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      if let image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "App Mute") {
        image.isTemplate = true
        button.image = image
        button.title = ""
      } else {
        button.title = "🔇"
      }
      button.toolTip = "App Mute"
      button.appearsDisabled = false
    }
    statusItem = item
    reload()
    AgentLog.info("menubar.start", fields: ["ok": statusItem != nil])
  }

  func setMuted(key: String, name: String) {
    let work = { [weak self] in
      self?.mutedNames[key] = name
      self?.reload()
    }
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  func setUnmuted(key: String) {
    let work = { [weak self] in
      self?.mutedNames.removeValue(forKey: key)
      self?.reload()
    }
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  func clear() {
    let work = { [weak self] in
      self?.mutedNames.removeAll()
      self?.reload()
    }
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
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

    if let button = statusItem.button {
      if button.image != nil {
        button.title = count == 0 ? "" : "\(count)"
      } else {
        button.title = count == 0 ? "♪" : "🔇\(count)"
      }
      button.toolTip = hoverText(for: apps)
    }

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self

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
    AgentLog.info("menubar.unmuteClick", fields: ["key": key])
    NotificationCenter.default.post(name: .appMuteUnmuteRequested, object: key)
  }

  @objc private func unmuteAllFromMenu() {
    AgentLog.info("menubar.unmuteAllClick", fields: [:])
    NotificationCenter.default.post(name: .appMuteUnmuteAllRequested, object: nil)
  }

  func menuWillOpen(_ menu: NSMenu) {
    AgentLog.info("menubar.menuWillOpen", fields: ["count": mutedNames.count])
  }
}

extension Notification.Name {
  static let appMuteUnmuteRequested = Notification.Name("appMuteUnmuteRequested")
  static let appMuteUnmuteAllRequested = Notification.Name("appMuteUnmuteAllRequested")
}
