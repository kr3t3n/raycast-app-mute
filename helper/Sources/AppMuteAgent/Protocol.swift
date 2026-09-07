import Foundation

struct Request: Codable {
  let protocolVersion: Int
  let operation: String
  let appID: String?
  let muted: Bool?
  let path: String?
  let bundleId: String?

  enum CodingKeys: String, CodingKey {
    case protocolVersion
    case operation
    case appID = "appId"
    case muted
    case path
    case bundleId
  }
}

struct Response<T: Encodable>: Encodable {
  let code: String
  let message: String
  let data: T?
}

struct AppRecord: Codable {
  let id: String
  let name: String
  let bundleId: String?
  let path: String?
  let executableName: String?
  let running: Bool
  let hasAudio: Bool
  let muted: Bool
  let iconPath: String?
}

let supportedProtocolVersion = 1
