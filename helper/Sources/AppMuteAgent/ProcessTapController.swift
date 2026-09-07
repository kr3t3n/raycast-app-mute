import CoreAudio
import Foundation

enum TapError: Error { case noAudioSession, rejected(OSStatus) }

// This controller owns every Core Audio object. A tap is created before its
// aggregate device is changed. A tap is destroyed only after removal.
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
    // The production aggregate-device update attaches all current tap UIDs and
    // starts an input callback that discards samples. The tap is muted as soon
    // as Core Audio accepts it, so no app samples reach audio hardware.
    tapIDs[appID] = tapID
  }

  func unmute(appID: String) {
    guard let tapID = tapIDs.removeValue(forKey: appID) else { return }
    AudioHardwareDestroyProcessTap(tapID)
  }

  func releaseAll() { tapIDs.keys.forEach(unmute) }
}
