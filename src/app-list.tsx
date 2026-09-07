import { Action, ActionPanel, closeMainWindow, getPreferenceValues, Icon, List, showToast, Toast } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { listApps, setMuted, toggleMuted } from "./agent-client";
import { failureMessage } from "./error-message";
import { applicationKeywords, groupApps, stateLabel } from "./presentation";
import { AppRecord } from "./types";
type Mode = "mute" | "unmute" | "toggle";
type Preferences = { candidateApps: "running" | "all"; includeBackgroundApps: boolean; closeAfterAction: boolean };
const sections = ["Muted", "Playing Audio", "Running", "Installed"] as const;

export function AppList({ mode, initialSearchText }: { mode: Mode; initialSearchText?: string }) {
  const preferences = getPreferenceValues<Preferences>();
  const { data, isLoading, revalidate } = usePromise(listApps);
  const groups = groupApps(data?.data ?? [], preferences.candidateApps === "all");
  async function act(app: AppRecord) {
    const response = mode === "toggle" ? await toggleMuted(app) : await setMuted(app, mode === "mute");
    if (["OK", "ALREADY_MUTED", "ALREADY_UNMUTED"].includes(response.code)) {
      await showToast({ style: Toast.Style.Success, title: response.message || `${mode === "unmute" ? "Unmuted" : "Muted"} ${app.name}` });
      if (preferences.closeAfterAction) await closeMainWindow(); else await revalidate();
    } else await showToast({ style: Toast.Style.Failure, title: failureMessage(response, app.name) });
  }
  return <List isLoading={isLoading} searchText={initialSearchText} searchBarPlaceholder="Search apps by name, executable, or bundle ID">
    {sections.map((section) => { const records = groups.get(section) ?? []; return records.length ? <List.Section key={section} title={section}>{records.map((app) => <List.Item key={app.id} title={app.name} subtitle={stateLabel(app)} icon={app.iconPath || Icon.SpeakerOn} keywords={applicationKeywords(app)} actions={<ActionPanel><Action title={mode === "toggle" ? "Toggle App Mute" : mode === "mute" ? "Mute App" : "Unmute App"} onAction={() => act(app)} /><Action title="Refresh" icon={Icon.ArrowClockwise} onAction={revalidate} /></ActionPanel>} />)}</List.Section> : null; })}
  </List>;
}
