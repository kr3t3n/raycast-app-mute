import {
  Action,
  ActionPanel,
  closeMainWindow,
  getPreferenceValues,
  Icon,
  List,
  showToast,
  Toast,
} from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { useState } from "react";
import { setMuted, toggleMuted } from "./agent-client";
import { catalogIcon, loadAppCatalog } from "./app-catalog";
import { failureMessage } from "./error-message";
import { applicationKeywords, groupApps, stateLabel } from "./presentation";
import { AppRecord } from "./types";

type Mode = "mute" | "unmute" | "toggle";
type Preferences = {
  candidateApps: "running" | "all";
  includeBackgroundApps: boolean;
  closeAfterAction: boolean;
};

const sections = ["Muted", "Playing Audio", "Running", "Installed"] as const;

export function AppList({ mode, initialSearchText }: { mode: Mode; initialSearchText?: string }) {
  const preferences = getPreferenceValues<Preferences>();
  const [searchText, setSearchText] = useState(initialSearchText ?? "");
  const { data, isLoading, revalidate } = usePromise(
    async () => loadAppCatalog(preferences.candidateApps === "all"),
    [preferences.candidateApps],
  );

  const apps = data?.apps ?? [];
  const groups = groupApps(apps, true);
  const agentDown = data?.agent.code === "AGENT_UNAVAILABLE";

  async function act(app: AppRecord) {
    try {
      const response = mode === "toggle" ? await toggleMuted(app) : await setMuted(app, mode === "mute");
      if (["OK", "ALREADY_MUTED", "ALREADY_UNMUTED"].includes(response.code)) {
        await showToast({
          style: Toast.Style.Success,
          title: response.message || `${mode === "unmute" ? "Unmuted" : "Muted"} ${app.name}`,
        });
        await revalidate();
        if (preferences.closeAfterAction) await closeMainWindow();
      } else {
        await showToast({ style: Toast.Style.Failure, title: failureMessage(response, app.name) });
      }
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: error instanceof Error ? error.message : "Mute action failed.",
      });
    }
  }

  return (
    <List
      isLoading={isLoading}
      searchText={searchText}
      onSearchTextChange={setSearchText}
      searchBarPlaceholder="Search apps by name or bundle ID"
      filtering
    >
      <List.EmptyView
        icon={Icon.AppWindowGrid3x3}
        title={agentDown ? "Apps load from Raycast; agent offline" : "No apps found"}
        description={
          agentDown
            ? "The app list uses Raycast getApplications. Mute actions need AppMuteAgent — run npm run agent:build."
            : "Try a shorter search, or clear the search field."
        }
      />
      {sections.map((section) => {
        const records = groups.get(section) ?? [];
        if (!records.length) return null;
        return (
          <List.Section key={section} title={section}>
            {records.map((app) => (
              <List.Item
                key={app.id}
                title={app.name}
                subtitle={stateLabel(app)}
                icon={catalogIcon(app)}
                keywords={applicationKeywords(app)}
                actions={
                  <ActionPanel>
                    <Action
                      title={
                        mode === "toggle" ? "Toggle App Mute" : mode === "mute" ? "Mute App" : "Unmute App"
                      }
                      onAction={() => act(app)}
                    />
                    <Action title="Refresh" icon={Icon.ArrowClockwise} onAction={revalidate} />
                  </ActionPanel>
                }
              />
            ))}
          </List.Section>
        );
      })}
    </List>
  );
}
