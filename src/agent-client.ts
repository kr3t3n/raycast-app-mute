import { appendFileSync, mkdirSync } from "node:fs";
import { execFile as execFileCb } from "node:child_process";
import { promisify } from "node:util";
import { homedir } from "node:os";
import { join } from "node:path";
import { AgentResponse, AppRecord } from "./types";

const execFileAsync = promisify(execFileCb);
const protocolVersion = 1;
const home = process.env.HOME || homedir();
const clientPath = `${home}/Library/Application Support/AppMute/AppMuteAgent.app/Contents/MacOS/app-mute-client`;
const logDir = join(home, "Library/Logs/AppMute");
const raycastLog = join(logDir, "raycast.log");

function logRaycast(event: string, fields: Record<string, unknown> = {}) {
  try {
    mkdirSync(logDir, { recursive: true });
    const line = JSON.stringify({ ts: new Date().toISOString(), event, ...fields }) + "\n";
    appendFileSync(raycastLog, line);
  } catch {
    // Logging must never break mute actions.
  }
}

async function request<T>(body: object): Promise<AgentResponse<T>> {
  const input = Buffer.from(JSON.stringify({ protocolVersion, ...body })).toString("base64");
  logRaycast("request", body as Record<string, unknown>);
  try {
    const { stdout, stderr } = await execFileAsync(clientPath, [input], {
      timeout: 15_000,
      maxBuffer: 2 * 1024 * 1024,
    });
    const text = stdout.toString().trim();
    const parsed = JSON.parse(text) as AgentResponse<T>;
    logRaycast("response", {
      code: parsed.code,
      message: parsed.message,
      stderr: stderr?.toString().trim() || undefined,
    });
    return parsed;
  } catch (error) {
    const message =
      error instanceof Error && "stderr" in error && typeof (error as { stderr?: Buffer }).stderr !== "undefined"
        ? (error as { stderr?: Buffer }).stderr?.toString().trim()
        : undefined;
    logRaycast("error", {
      message: message || (error instanceof Error ? error.message : String(error)),
    });
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
