import AudioToolbox
import CoreAudio
import Foundation

enum TapError: Error {
  case noAudioSession
  case rejected(OSStatus)
}

/// Owns Core Audio process taps plus private aggregate devices. Requires macOS 14.2+.
///
/// Creating a tap with `muteBehavior = .muted` is not enough. Mute takes effect when the
/// tap is attached to a private aggregate device (and kept alive). See Apple’s Core Audio
/// taps sample and CATapMuteBehavior.
@available(macOS 14.2, *)
final class ProcessTapController {
  private struct Session {
    let tapID: AudioObjectID
    let aggregateID: AudioObjectID
    let ioProcID: AudioDeviceIOProcID?
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

    let aggregateDesc: [String: Any] = [
      kAudioAggregateDeviceNameKey: "AppMute Aggregate \(appID)",
      kAudioAggregateDeviceUIDKey: "com.kr3t3n.app-mute.\(tapUUID.uuidString)",
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapUIDKey: tapUUID.uuidString,
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

    // Discard samples. CATapMuted usually mutes as soon as the aggregate exists; starting
    // a read also covers mute-when-tapped behavior and keeps the session active.
    var ioProcID: AudioDeviceIOProcID?
    let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, _, _, _, _ in }
    if ioStatus == noErr, let proc = ioProcID {
      if AudioDeviceStart(aggregateID, proc) != noErr {
        AudioDeviceDestroyIOProcID(aggregateID, proc)
        ioProcID = nil
      }
    } else {
      ioProcID = nil
    }

    sessions[appID] = Session(tapID: tapID, aggregateID: aggregateID, ioProcID: ioProcID)
  }

  func unmute(appID: String) {
    guard let session = sessions.removeValue(forKey: appID) else { return }
    if let proc = session.ioProcID {
      AudioDeviceStop(session.aggregateID, proc)
      AudioDeviceDestroyIOProcID(session.aggregateID, proc)
    }
    AudioHardwareDestroyAggregateDevice(session.aggregateID)
    AudioHardwareDestroyProcessTap(session.tapID)
  }

  func releaseAll() {
    sessions.keys.forEach(unmute)
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
