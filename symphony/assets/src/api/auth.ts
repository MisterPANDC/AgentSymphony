import { api } from "./client";
import type { AuthSession, GitLabProject } from "../types/auth";

export function getAuthSession(): Promise<AuthSession> {
  return api<AuthSession>("/api/auth/session");
}

export function listGitLabProjects(): Promise<{ projects: GitLabProject[] }> {
  return api<{ projects: GitLabProject[] }>("/api/projects");
}

export function activateGitLabProject(projectId: number | string): Promise<Pick<AuthSession, "project" | "user" | "permissions">> {
  return api<Pick<AuthSession, "project" | "user" | "permissions">>(`/api/projects/${projectId}/activate`, { method: "POST" });
}
