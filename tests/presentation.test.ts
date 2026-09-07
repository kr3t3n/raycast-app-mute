import { describe, expect, it } from "vitest";
import { applicationKeywords, groupApps, stateLabel } from "../src/presentation";
const clickUp = { id: "com.clickup", name: "ClickUp", bundleId: "com.clickup.desktop", executableName: "ClickUp Helper", running: true, hasAudio: true, muted: false };
describe("app presentation", () => {
  it("indexes name, executable name, and bundle identifier", () => expect(applicationKeywords(clickUp)).toContain("com.clickup.desktop"));
  it("groups audio apps before normal running apps", () => expect(groupApps([clickUp, { ...clickUp, id: "safari", hasAudio: false }], false).get("Playing Audio")).toHaveLength(1));
  it("does not duplicate an app", () => expect(groupApps([clickUp, clickUp], false).get("Playing Audio")).toHaveLength(1));
  it("shows an actionable no-audio label", () => expect(stateLabel({ ...clickUp, hasAudio: false })).toBe("No Audio Session"));
});
