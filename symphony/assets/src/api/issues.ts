import { api } from "./client";
import type { IssueDTO, NoteDTO, WorkflowStatus } from "../types/issue";

export const listIssues = (params = "") => api<{ issues: IssueDTO[] }>(`/api/issues${params}`);
export const getIssue = (id: string) => api<{ issue: IssueDTO }>(`/api/issues/${id}`);
export const getIssueNotes = (id: string) => api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`);

export function updateIssueWorkflow(id: string, status: WorkflowStatus, reason?: string) {
  return api<{ issue: IssueDTO }>(`/api/issues/${id}/workflow`, {
    method: "PATCH",
    body: JSON.stringify({ status, reason })
  });
}

export function createIssueNote(id: string, body: string) {
  return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`, {
    method: "POST",
    body: JSON.stringify({ body })
  });
}
