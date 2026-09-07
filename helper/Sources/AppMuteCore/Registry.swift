import Foundation

let staleProcessGraceSeconds: TimeInterval = 30

struct MuteRecord: Equatable {
  let appID: String
  var processIDs: Set<pid_t>
  var requestedAt: Date
  var lastProcessSeenAt: Date
}

final class MuteRegistry {
  private(set) var records: [String: MuteRecord] = [:]

  func set(_ appID: String, muted: Bool, processes: Set<pid_t>, now: Date = Date()) -> String {
    if muted {
      if records[appID] != nil { return "ALREADY_MUTED" }
      records[appID] = MuteRecord(appID: appID, processIDs: processes, requestedAt: now, lastProcessSeenAt: now)
      return "OK"
    }
    guard records.removeValue(forKey: appID) != nil else { return "ALREADY_UNMUTED" }
    return "OK"
  }

  func updateProcesses(_ appID: String, processes: Set<pid_t>, now: Date = Date()) {
    guard var record = records[appID] else { return }
    record.processIDs = processes
    if !processes.isEmpty { record.lastProcessSeenAt = now }
    records[appID] = record
  }

  func removeStale(now: Date = Date()) -> [MuteRecord] {
    let stale = records.values.filter { $0.processIDs.isEmpty && now.timeIntervalSince($0.lastProcessSeenAt) >= staleProcessGraceSeconds }
    stale.forEach { records.removeValue(forKey: $0.appID) }
    return stale
  }
}
