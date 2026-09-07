import XCTest
@testable import AppMuteAgent

final class RegistryTests: XCTestCase {
  func testMuteIsIdempotent() { let registry = MuteRegistry(); XCTAssertEqual(registry.set("clickup", muted: true, processes: [1]), "OK"); XCTAssertEqual(registry.set("clickup", muted: true, processes: [1]), "ALREADY_MUTED") }
  func testUnmuteIsIdempotent() { let registry = MuteRegistry(); XCTAssertEqual(registry.set("clickup", muted: false, processes: []), "ALREADY_UNMUTED") }
  func testStaleRecordExpiresAfterGracePeriod() { let registry = MuteRegistry(); let now = Date(); _ = registry.set("clickup", muted: true, processes: [], now: now); XCTAssertTrue(registry.removeStale(now: now.addingTimeInterval(staleProcessGraceSeconds - 1)).isEmpty); XCTAssertEqual(registry.removeStale(now: now.addingTimeInterval(staleProcessGraceSeconds)).map(\.appID), ["clickup"]) }
}
