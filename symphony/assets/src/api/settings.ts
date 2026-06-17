import { api } from "./client";
import type { AutomationCredentialMode, GitLabSettingsDTO, LocalRepoCandidateDTO } from "../types/gitlab";
import type { WorkflowSettingsDTO } from "../types/workflow";

export const getGitLabSettings = () => api<GitLabSettingsDTO>(`/api/settings/gitlab`);
export const testGitLabSettings = () => api<Record<string, unknown>>(`/api/settings/gitlab/test`, { method: "POST" });
export const scanLocalRepoCandidates = (scope: "nearby" | "local" = "nearby") =>
  api<{ candidates: LocalRepoCandidateDTO[] }>(`/api/settings/gitlab/local-repo/candidates?scope=${scope}`);
export const updateLocalRepoPath = (localRepoPath: string) =>
  api<Pick<GitLabSettingsDTO, "project"> & { ok: boolean }>(`/api/settings/gitlab/local-repo`, {
    method: "PUT",
    body: JSON.stringify({ localRepoPath })
  });
export const updateProjectAccessToken = (projectAccessToken: string) =>
  api<Pick<GitLabSettingsDTO, "project"> & { ok: boolean }>(`/api/settings/gitlab/project-token`, {
    method: "PUT",
    body: JSON.stringify({ projectAccessToken })
  });
export const updateServiceAccountToken = (serviceAccountToken: string) =>
  api<Pick<GitLabSettingsDTO, "project" | "serviceAccount"> & { ok: boolean }>(`/api/settings/gitlab/service-account-token`, {
    method: "PUT",
    body: JSON.stringify({ serviceAccountToken })
  });
export const updateAutomationCredentialMode = (mode: AutomationCredentialMode) =>
  api<Pick<GitLabSettingsDTO, "project" | "serviceAccount"> & { ok: boolean }>(`/api/settings/gitlab/credential-mode`, {
    method: "PUT",
    body: JSON.stringify({ mode })
  });
export const getWorkflowSettings = () => api<{ workflow: WorkflowSettingsDTO }>(`/api/settings/workflow`);
