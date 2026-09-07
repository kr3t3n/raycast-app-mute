import { AgentResponse } from "./types";
export function failureMessage(response: AgentResponse, appName: string): string {
  switch (response.code) {
    case "NOT_RUNNING": return `${appName} is not running.`;
    case "NO_AUDIO_SESSION": return `${appName} has no audio session. Play audio and try again.`;
    case "APP_STOPPED": return `${appName} stopped before the action. Refresh the list.`;
    case "PERMISSION_DENIED": return "Allow system audio access for AppMuteAgent.";
    case "UNSUPPORTED_MACOS": return "App mute needs macOS 14.2 or later.";
    case "PROTOCOL_MISMATCH": return "AppMuteAgent needs reinstalling.";
    case "TAP_REJECTED": return `macOS could not mute ${appName} (${response.code}).`;
    default: return response.message || "AppMuteAgent could not start.";
  }
}
