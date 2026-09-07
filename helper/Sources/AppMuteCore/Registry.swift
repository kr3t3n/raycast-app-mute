import Foundation

public let staleProcessGraceSeconds: TimeInterval = 30

public struct MuteRecord: Equatable {
  public let appID: String
  public var processIDs: Set<pid_t>
  public var requestedAt: Date
  public var lastProcessSeenAt: Date

  public init(appID: String, processIDs: Set<pid_t>, requestedAt: Date, lastProcessSeenAt: Date) {
    self.appID = appID
    self.processIDs = processIDs
    self.requestedAt = requestedAt
    self.lastProcessSeenAt = lastProcessSeenAt
  }
}

public final class MuteRegistry {
  public private(set) var records: [String: MuteRecord] = [:]

  public init() {}

  public func set(_ appID: String, muted: Bool, processes: Set<pid_t>, now: Date = Date()) -> String {
    if muted {
      if records[appID] != nil { return "ALREADY_MUTED" }
      records[appID] = MuteRecord(appID: appID, processIDs: processes, requestedAt: now, lastProcessSeenAt: now)
      return "OK"
    }
    guard records.removeValue(forKey: appID) != nil else { return "ALREADY_UNMUTED" }
    return "OK"
  }

  public func updateProcesses(_ appID: String, processes: Set<pid_t>, now: Date = Date()) {
    guard var record = records[appID] else { return }
    record.processIDs = processes
    if !processes.isEmpty { record.lastProcessSeenAt = now }
    records[appID] = record
  }

  public func removeStale(now: Date = Date()) -> [MuteRecord] {
    let stale = records.values.filter {
      $0.processIDs.isEmpty && now.timeIntervalSince($0.lastProcessSeenAt) >= staleProcessGraceSeconds
    }
    stale.forEach { records.removeValue(forKey: $0.appID) }
    return stale
  }
}
