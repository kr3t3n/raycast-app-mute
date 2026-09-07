import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { AgentResponse, AppRecord } from "./types";

const execFileAsync = promisify(execFile);
const protocolVersion = 1;
const clientPath = `${process.env.HOME}/Library/Application Support/AppMute/AppMuteAgent.app/Contents/MacOS/app-mute-client`;

async function request<T>(body: object): Promise<AgentResponse<T>> {
  const input = Buffer.from(JSON.stringify({ protocolVersion, ...body })).toString("base64");
  try {
    const { stdout } = await execFileAsync(clientPath, [input], {
      timeout: 15_000,
      maxBuffer: 2 * 1024 * 1024,
    });
    const text = stdout.toString().trim();
    return JSON.parse(text) as AgentResponse<T>;
  } catch (error) {
    const message =
      error instanceof Error && "stderr" in error && typeof (error as { stderr?: Buffer }).stderr !== "undefined"
        ? (error as { stderr?: Buffer }).stderr?.toString().trim()
        : undefined;
    return {
      code: "AGENT_UNAVAILABLE",
      message: message || "AppMuteAgent could not start. Run npm run agent:build.",
    };
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
  request<undefined>({
    operation: "set",
    appId: app.bundleId || app.id,
    bundleId: app.bundleId,
    path: app.path,
    muted,
  });

export const toggleMuted = (app: AppRecord) =>
  request<undefined>({
    operation: "toggle",
    appId: app.bundleId || app.id,
    bundleId: app.bundleId,
    path: app.path,
  });
