export type AgentCode = "OK" | "ALREADY_MUTED" | "ALREADY_UNMUTED" | "NOT_RUNNING" | "NO_AUDIO_SESSION" | "APP_STOPPED" | "PERMISSION_DENIED" | "UNSUPPORTED_MACOS" | "PROTOCOL_MISMATCH" | "TAP_REJECTED" | "AGENT_UNAVAILABLE";

export interface AppRecord {
  id: string; name: string; bundleId?: string; path?: string; executableName?: string;
  running: boolean; hasAudio: boolean; muted: boolean; iconPath?: string;
}
export interface AgentResponse<T = undefined> { code: AgentCode; message: string; data?: T; }
