import { api } from "./client";
import type { GitLabSettingsDTO } from "../types/gitlab";
import type { WorkflowSettingsDTO } from "../types/workflow";

export const getGitLabSettings = () => api<GitLabSettingsDTO>(`/api/settings/gitlab`);
export const testGitLabSettings = () => api<Record<string, unknown>>(`/api/settings/gitlab/test`, { method: "POST" });
export const updateProjectAccessToken = (projectAccessToken: string) =>
  api<Pick<GitLabSettingsDTO, "project"> & { ok: boolean }>(`/api/settings/gitlab/project-token`, {
    method: "PUT",
    body: JSON.stringify({ projectAccessToken })
  });
export const getWorkflowSettings = () => api<{ workflow: WorkflowSettingsDTO }>(`/api/settings/workflow`);
