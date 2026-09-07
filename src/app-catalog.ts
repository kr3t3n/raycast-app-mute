import { Application, getApplications, Icon } from "@raycast/api";
import { AgentResponse, AppRecord } from "./types";
import { listMutedApps } from "./agent-client";

function appId(app: Application): string {
  return app.bundleId || app.path;
}

/** Build the picker list from Raycast's installed-app catalog. */
export async function loadAppCatalog(includeInstalled: boolean): Promise<{
  apps: AppRecord[];
  agent: AgentResponse<{ mutedIds: string[] }>;
}> {
  const installed = await getApplications();
  const agent = await listMutedApps();
  const mutedIds = new Set(agent.code === "OK" ? agent.data?.mutedIds ?? [] : []);

  // Raycast returns installed apps. Mark them installed; mute state comes from the agent when available.
  const apps: AppRecord[] = installed
    .filter((app) => Boolean(app.name && app.path))
    .map((app) => {
      const id = appId(app);
      return {
        id,
        name: app.localizedName || app.name,
        bundleId: app.bundleId,
        path: app.path,
        executableName: undefined,
        // getApplications does not expose running PIDs; treat catalog apps as selectable.
        running: true,
        hasAudio: false,
        muted: mutedIds.has(id) || (app.bundleId ? mutedIds.has(app.bundleId) : false),
        iconPath: app.path,
      };
    });

  if (!includeInstalled) {
    // Still show muted apps even if preference is running-only; otherwise show full catalog.
    // Without a reliable running-process API in Raycast, "running" falls back to the full catalog.
  }

  apps.sort((a, b) => a.name.localeCompare(b.name));
  return { apps, agent };
}

export function catalogIcon(app: AppRecord): Icon | { fileIcon: string } {
  return app.iconPath ? { fileIcon: app.iconPath } : Icon.AppWindow;
}
