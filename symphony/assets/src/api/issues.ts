import { api } from "./client";
import type { IssueDTO, NoteDTO, WorkflowStatus } from "../types/issue";

export interface CreateIssueInput {
  title: string;
  description?: string;
  labels?: string;
  workflowStatus: WorkflowStatus;
}

export const listIssues = (params = "") => api<{ issues: IssueDTO[] }>(`/api/issues${params}`);
export const getIssue = (id: string) => api<{ issue: IssueDTO }>(`/api/issues/${id}`);
export const getIssueNotes = (id: string) => api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`);

export function createIssue(input: CreateIssueInput) {
  return api<{ issue: IssueDTO }>("/api/issues", {
    method: "POST",
    body: JSON.stringify(input)
  });
}

export function updateIssueWorkflow(id: string, status: WorkflowStatus, reason?: string, options: { confirmStopRun?: boolean } = {}) {
  return api<{ issue: IssueDTO }>(`/api/issues/${id}/workflow`, {
    method: "PATCH",
    body: JSON.stringify({ status, reason, confirmStopRun: options.confirmStopRun })
  });
}

export function updateIssueLabels(id: string, labels: string[]) {
  return api<{ issue: IssueDTO }>(`/api/issues/${id}/gitlab`, {
    method: "PATCH",
    body: JSON.stringify({ labels: labels.join(",") })
  });
}

export function updateIssueTitle(id: string, title: string) {
  return api<{ issue: IssueDTO }>(`/api/issues/${id}/gitlab`, {
    method: "PATCH",
    body: JSON.stringify({ title })
  });
}

export function createIssueNote(id: string, body: string) {
  return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`, {
    method: "POST",
    body: JSON.stringify({ body })
  });
}
