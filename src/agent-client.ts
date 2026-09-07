import { runAppleScript } from "@raycast/utils";
import { AgentResponse, AppRecord } from "./types";

const protocolVersion = 1;
const clientPath = `${process.env.HOME}/Library/Application Support/AppMute/AppMuteAgent.app/Contents/MacOS/app-mute-client`;
const quote = (value: string) => `'${value.replace(/'/g, "'\\\"'\\\"'")}'`;

async function request<T>(body: object): Promise<AgentResponse<T>> {
  const input = Buffer.from(JSON.stringify({ protocolVersion, ...body })).toString("base64");
  try {
    return JSON.parse(await runAppleScript(`do shell script ${quote(`${clientPath} ${input}`)}`)) as AgentResponse<T>;
  } catch {
    return { code: "AGENT_UNAVAILABLE", message: "AppMuteAgent could not start. Run npm run agent:build." };
  }
}

/** Agent list is used for mute-state enrichment; Raycast getApplications owns the picker. */
export const listApps = () => request<AppRecord[]>({ operation: "list" });

export async function listMutedApps(): Promise<AgentResponse<{ mutedIds: string[] }>> {
  const response = await listApps();
  if (response.code !== "OK" || !response.data) {
    return { code: response.code, message: response.message, data: { mutedIds: [] } };
  }
  return {
    code: "OK",
    message: response.message,
    data: { mutedIds: response.data.filter((app) => app.muted).map((app) => app.id) },
  };
}

export const setMuted = (app: AppRecord, muted: boolean) =>
  request<undefined>({ operation: "set", appId: app.id, muted });

export const toggleMuted = (app: AppRecord) => request<undefined>({ operation: "toggle", appId: app.id });
