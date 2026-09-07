import CoreAudio
import Foundation

enum TapError: Error {
  case noAudioSession
  case rejected(OSStatus)
}

/// Owns Core Audio process taps. Requires macOS 14.2+.
@available(macOS 14.2, *)
final class ProcessTapController {
  private var tapIDs: [String: AudioObjectID] = [:]

  func mute(appID: String, processObjectIDs: [AudioObjectID]) throws {
    guard !processObjectIDs.isEmpty else { throw TapError.noAudioSession }
    if tapIDs[appID] != nil { return }

    let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
    description.muteBehavior = .muted
    description.name = "AppMute \(appID)"
    description.isPrivate = true

    var tapID = AudioObjectID(kAudioObjectUnknown)
    let status = AudioHardwareCreateProcessTap(description, &tapID)
    guard status == noErr else { throw TapError.rejected(status) }
    tapIDs[appID] = tapID
  }

  func unmute(appID: String) {
    guard let tapID = tapIDs.removeValue(forKey: appID) else { return }
    AudioHardwareDestroyProcessTap(tapID)
  }

  func releaseAll() {
    tapIDs.keys.forEach(unmute)
  }

  /// Core Audio process objects whose PID matches any of `pids`.
  static func processObjectIDs(matching pids: Set<pid_t>) -> [AudioObjectID] {
    guard !pids.isEmpty else { return [] }

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

    var pidAddress = AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyPID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    return processObjects.filter { objectID in
      var pid: pid_t = 0
      var pidSize = UInt32(MemoryLayout<pid_t>.size)
      guard AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &pid) == noErr else {
        return false
      }
      return pids.contains(pid)
    }
  }
}
