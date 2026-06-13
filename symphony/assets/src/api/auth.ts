import { api } from "./client";
import type { AuthSession, GitLabProject } from "../types/auth";

export function getAuthSession(): Promise<AuthSession> {
  return api<AuthSession>("/api/auth/session");
}

export function listGitLabProjects(refresh = false): Promise<{ projects: GitLabProject[] }> {
  return api<{ projects: GitLabProject[] }>(refresh ? "/api/projects?refresh=1" : "/api/projects");
}

export function activateGitLabProject(projectId: number | string): Promise<Pick<AuthSession, "project" | "user" | "permissions">> {
  return api<Pick<AuthSession, "project" | "user" | "permissions">>(`/api/projects/${projectId}/activate`, { method: "POST" });
}
