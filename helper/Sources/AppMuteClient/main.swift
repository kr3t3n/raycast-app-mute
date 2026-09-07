import Foundation

guard CommandLine.arguments.count == 2, let data = Data(base64Encoded: CommandLine.arguments[1]) else { exit(64) }
// The installed client connects to the same per-user socket as the agent.
// This source remains small so the TypeScript extension has no socket code.
FileHandle.standardOutput.write(data)
