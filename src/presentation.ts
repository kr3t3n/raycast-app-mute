import { AppRecord } from "./types";

export type AppSection = "Muted" | "Playing Audio" | "Running" | "Installed";

export const applicationKeywords = (app: AppRecord) =>
  [app.name, app.bundleId, app.executableName].filter((value): value is string => Boolean(value));

export function sectionFor(app: AppRecord): AppSection {
  return app.muted ? "Muted" : app.hasAudio ? "Playing Audio" : app.running ? "Running" : "Installed";
}

export function stateLabel(app: AppRecord): string {
  return app.muted ? "Muted" : app.hasAudio ? "Playing Audio" : "Installed";
}

export function groupApps(apps: AppRecord[], includeInstalled: boolean): Map<AppSection, AppRecord[]> {
  const groups = new Map<AppSection, AppRecord[]>([
    ["Muted", []],
    ["Playing Audio", []],
    ["Running", []],
    ["Installed", []],
  ]);
  const seen = new Set<string>();
  for (const app of apps) {
    if (seen.has(app.id) || (!includeInstalled && !app.running && !app.muted)) continue;
    seen.add(app.id);
    const section = app.muted ? "Muted" : app.hasAudio ? "Playing Audio" : "Installed";
    groups.get(section)?.push(app);
  }
  for (const values of groups.values()) values.sort((a, b) => a.name.localeCompare(b.name));
  return groups;
}
