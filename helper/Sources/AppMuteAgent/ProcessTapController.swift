import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

enum TapError: Error {
  case noAudioSession
  case rejected(OSStatus)
}

struct AudioProcessMatch: Equatable {
  let objectID: AudioObjectID
  let pid: pid_t
  let path: String?
  let isRunningOutput: Bool
}

/// Owns Core Audio process taps plus private aggregate devices. Requires macOS 14.2+.
///
/// Mute only takes effect when the tap is attached to a private aggregate built around the
/// current default output device and an IOProc is started (Milky / Apple sample pattern).
@available(macOS 14.2, *)
final class ProcessTapController {
  private struct Session {
    let tapID: AudioObjectID
    let aggregateID: AudioObjectID
    let ioProcID: AudioDeviceIOProcID
  }

  private var sessions: [String: Session] = [:]

  func mute(appID: String, processObjectIDs: [AudioObjectID]) throws {
    guard !processObjectIDs.isEmpty else { throw TapError.noAudioSession }
    if sessions[appID] != nil { return }

    let tapUUID = UUID()
    let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
    description.uuid = tapUUID
    description.muteBehavior = .muted
    description.name = "AppMute \(appID)"
    description.isPrivate = true

    var tapID = AudioObjectID(kAudioObjectUnknown)
    let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
    guard tapStatus == noErr else { throw TapError.rejected(tapStatus) }

    let tapUID: String
    do {
      tapUID = try Self.readTapUID(tapID)
    } catch {
      AudioHardwareDestroyProcessTap(tapID)
      throw error
    }

    let outputUID: String
    do {
      outputUID = try Self.defaultOutputDeviceUID()
    } catch {
      AudioHardwareDestroyProcessTap(tapID)
      throw error
    }

    let aggregateDesc: [String: Any] = [
      kAudioAggregateDeviceNameKey: "AppMute Aggregate \(appID)",
      kAudioAggregateDeviceUIDKey: "com.kr3t3n.app-mute.\(tapUUID.uuidString)",
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: outputUID],
      ],
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapUIDKey: tapUID,
          kAudioSubTapDriftCompensationKey: true,
        ],
      ],
    ]

    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateID)
    guard aggregateStatus == noErr else {
      AudioHardwareDestroyProcessTap(tapID)
      throw TapError.rejected(aggregateStatus)
    }

    var ioProcID: AudioDeviceIOProcID?
    let queue = DispatchQueue(label: "com.kr3t3n.app-mute.io.\(appID)")
    let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, _, _, _, _ in }
    guard ioStatus == noErr, let proc = ioProcID else {
      AudioHardwareDestroyAggregateDevice(aggregateID)
      AudioHardwareDestroyProcessTap(tapID)
      throw TapError.rejected(ioStatus)
    }

    let startStatus = AudioDeviceStart(aggregateID, proc)
    guard startStatus == noErr else {
      AudioDeviceDestroyIOProcID(aggregateID, proc)
      AudioHardwareDestroyAggregateDevice(aggregateID)
      AudioHardwareDestroyProcessTap(tapID)
      throw TapError.rejected(startStatus)
    }

    sessions[appID] = Session(tapID: tapID, aggregateID: aggregateID, ioProcID: proc)
  }

  func unmute(appID: String) {
    guard let session = sessions.removeValue(forKey: appID) else { return }
    AudioDeviceStop(session.aggregateID, session.ioProcID)
    AudioDeviceDestroyIOProcID(session.aggregateID, session.ioProcID)
    AudioHardwareDestroyAggregateDevice(session.aggregateID)
    AudioHardwareDestroyProcessTap(session.tapID)
  }

  func releaseAll() {
    sessions.keys.forEach(unmute)
  }

  /// Core Audio process objects that belong to the selected app (bundle helpers + path + parent chain).
  static func matches(for app: RunningApp) -> [AudioProcessMatch] {
    let related = relatedProcessIDs(for: app)
    return allProcessObjects().compactMap { objectID -> AudioProcessMatch? in
      guard let pid = pid(of: objectID) else { return nil }
      let path = processPath(pid: pid)
      let belongs =
        related.contains(pid)
        || pathBelongs(path, toAppPath: app.path)
        || parentChainBelongs(pid: pid, app: app, related: related)
      guard belongs else { return nil }
      return AudioProcessMatch(
        objectID: objectID,
        pid: pid,
        path: path,
        isRunningOutput: isRunningOutput(objectID)
      )
    }
  }

  static func processObjectIDs(for app: RunningApp) -> [AudioObjectID] {
    let matched = matches(for: app)
    let active = matched.filter(\.isRunningOutput)
    // Prefer processes that are currently outputting; fall back to every matched object.
    let chosen = active.isEmpty ? matched : active
    return chosen.map(\.objectID)
  }

  /// Core Audio process objects whose PID matches any of `pids`.
  static func processObjectIDs(matching pids: Set<pid_t>) -> [AudioObjectID] {
    guard !pids.isEmpty else { return [] }
    return allProcessObjects().filter { objectID in
      guard let pid = pid(of: objectID) else { return false }
      return pids.contains(pid)
    }
  }

  static func allAudioProcesses() -> [AudioProcessMatch] {
    allProcessObjects().compactMap { objectID in
      guard let pid = pid(of: objectID) else { return nil }
      return AudioProcessMatch(
        objectID: objectID,
        pid: pid,
        path: processPath(pid: pid),
        isRunningOutput: isRunningOutput(objectID)
      )
    }
  }

  private static func relatedProcessIDs(for app: RunningApp) -> Set<pid_t> {
    var pids: Set<pid_t> = [app.pid]
    if let bundleID = app.bundleID {
      for other in NSWorkspace.shared.runningApplications {
        guard let otherBundle = other.bundleIdentifier else { continue }
        if otherBundle == bundleID || otherBundle.hasPrefix(bundleID + ".") {
          pids.insert(other.processIdentifier)
        }
      }
    }
    if let appPath = app.path {
      for other in NSWorkspace.shared.runningApplications {
        guard let otherPath = other.bundleURL?.path else { continue }
        if otherPath == appPath || otherPath.hasPrefix(appPath + "/") {
          pids.insert(other.processIdentifier)
        }
      }
    }
    return pids
  }

  private static func pathBelongs(_ path: String?, toAppPath appPath: String?) -> Bool {
    guard let path, let appPath, !appPath.isEmpty else { return false }
    return path == appPath || path.hasPrefix(appPath + "/")
  }

  private static func parentChainBelongs(pid: pid_t, app: RunningApp, related: Set<pid_t>) -> Bool {
    var current = pid
    for _ in 0 ..< 10 {
      guard let parent = processParent(pid: current), parent > 1 else { return false }
      if parent == app.pid || related.contains(parent) { return true }
      if pathBelongs(processPath(pid: parent), toAppPath: app.path) { return true }
      current = parent
    }
    return false
  }

  private static func allProcessObjects() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
      return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var processObjects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &processObjects) == noErr else {
      return []
    }
    return processObjects
  }

  private static func pid(of objectID: AudioObjectID) -> pid_t? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyPID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var pid: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &pid) == noErr else {
      return nil
    }
    return pid
  }

  private static func isRunningOutput(_ objectID: AudioObjectID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyIsRunningOutput,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &running) == noErr else {
      return false
    }
    return running != 0
  }

  private static func readTapUID(_ tapID: AudioObjectID) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var cfUID: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &cfUID)
    guard status == noErr, let uid = cfUID?.takeRetainedValue() as String else {
      throw TapError.rejected(status)
    }
    return uid
  }

  private static func defaultOutputDeviceUID() throws -> String {
    var deviceAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let system = AudioObjectID(kAudioObjectSystemObject)
    let deviceStatus = AudioObjectGetPropertyData(system, &deviceAddress, 0, nil, &deviceSize, &deviceID)
    guard deviceStatus == noErr else { throw TapError.rejected(deviceStatus) }

    var uidAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var cfUID: Unmanaged<CFString>?
    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let uidStatus = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &cfUID)
    guard uidStatus == noErr, let uid = cfUID?.takeRetainedValue() as String else {
      throw TapError.rejected(uidStatus)
    }
    return uid
  }
}

private func processPath(pid: pid_t) -> String? {
  var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
  let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
  guard length > 0 else { return nil }
  return String(cString: buffer)
}

private func processParent(pid: pid_t) -> pid_t? {
  var info = proc_bsdshortinfo()
  let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
  let written = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size)
  guard written == size else { return nil }
  return pid_t(info.pbsi_ppid)
}
