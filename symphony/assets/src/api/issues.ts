import { api } from "./client";
import type { IssueDTO, MergeRequestDTO, NoteDTO, WorkflowStatus } from "../types/issue";

export interface CreateIssueInput {
  title: string;
  description?: string;
  labels?: string;
  workflowStatus: WorkflowStatus;
}

export const listIssues = (params = "") => api<{ issues: IssueDTO[] }>(`/api/issues${params}`);
export const getIssue = (id: string) => api<{ issue: IssueDTO }>(`/api/issues/${id}`);
export const getIssueNotes = (id: string) => api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`);
export const getIssueMergeRequests = (id: string) => api<{ mergeRequests: MergeRequestDTO[] }>(`/api/issues/${id}/merge_requests`);
export const getMergeRequestNotes = (issueId: string, mergeRequestIid: number | string) =>
  api<{ notes: NoteDTO[] }>(`/api/issues/${issueId}/merge_requests/${mergeRequestIid}/notes`);

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

export function updateIssueDescription(id: string, description: string) {
  return api<{ issue: IssueDTO }>(`/api/issues/${id}/gitlab`, {
    method: "PATCH",
    body: JSON.stringify({ description })
  });
}

export function updateMergeRequestGitLab(issueId: string, mergeRequestIid: number | string, attrs: { title?: string; description?: string; labels?: string[] }) {
  const body: Record<string, string> = {};

  if (attrs.title !== undefined) body.title = attrs.title;
  if (attrs.description !== undefined) body.description = attrs.description;
  if (attrs.labels !== undefined) body.labels = attrs.labels.join(",");

  return api<{ mergeRequest: MergeRequestDTO }>(`/api/issues/${issueId}/merge_requests/${mergeRequestIid}/gitlab`, {
    method: "PATCH",
    body: JSON.stringify(body)
  });
}

export function createIssueNote(id: string, body: string, files: File[] = []) {
  if (files.length > 0) {
    const form = new FormData();
    form.set("body", body);
    files.forEach((file) => form.append("files", file));

    return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`, {
      method: "POST",
      body: form
    });
  }

  return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes`, {
    method: "POST",
    body: JSON.stringify({ body })
  });
}

export function createIssueNoteReply(id: string, discussionId: string, body: string, files: File[] = []) {
  const path = `/api/issues/${id}/discussions/${encodeURIComponent(discussionId)}/notes`;

  if (files.length > 0) {
    const form = new FormData();
    form.set("body", body);
    files.forEach((file) => form.append("files", file));

    return api<{ notes: NoteDTO[] }>(path, {
      method: "POST",
      body: form
    });
  }

  return api<{ notes: NoteDTO[] }>(path, {
    method: "POST",
    body: JSON.stringify({ body })
  });
}

export function createMergeRequestNote(issueId: string, mergeRequestIid: number | string, body: string, files: File[] = []) {
  const path = `/api/issues/${issueId}/merge_requests/${mergeRequestIid}/notes`;

  if (files.length > 0) {
    const form = new FormData();
    form.set("body", body);
    files.forEach((file) => form.append("files", file));

    return api<{ notes: NoteDTO[] }>(path, {
      method: "POST",
      body: form
    });
  }

  return api<{ notes: NoteDTO[] }>(path, {
    method: "POST",
    body: JSON.stringify({ body })
  });
}

export function createMergeRequestNoteReply(issueId: string, mergeRequestIid: number | string, discussionId: string, body: string, files: File[] = []) {
  const path = `/api/issues/${issueId}/merge_requests/${mergeRequestIid}/discussions/${encodeURIComponent(discussionId)}/notes`;

  if (files.length > 0) {
    const form = new FormData();
    form.set("body", body);
    files.forEach((file) => form.append("files", file));

    return api<{ notes: NoteDTO[] }>(path, {
      method: "POST",
      body: form
    });
  }

  return api<{ notes: NoteDTO[] }>(path, {
    method: "POST",
    body: JSON.stringify({ body })
  });
}

export function updateIssueNote(id: string, noteId: number | string, body: string, files: File[] = []) {
  if (files.length > 0) {
    const form = new FormData();
    form.set("body", body);
    files.forEach((file) => form.append("files", file));

    return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes/${noteId}`, {
      method: "PUT",
      body: form
    });
  }

  return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes/${noteId}`, {
    method: "PUT",
    body: JSON.stringify({ body })
  });
}

export function updateMergeRequestNote(issueId: string, mergeRequestIid: number | string, noteId: number | string, body: string, files: File[] = []) {
  const path = `/api/issues/${issueId}/merge_requests/${mergeRequestIid}/notes/${noteId}`;

  if (files.length > 0) {
    const form = new FormData();
    form.set("body", body);
    files.forEach((file) => form.append("files", file));

    return api<{ notes: NoteDTO[] }>(path, {
      method: "PUT",
      body: form
    });
  }

  return api<{ notes: NoteDTO[] }>(path, {
    method: "PUT",
    body: JSON.stringify({ body })
  });
}

export function deleteIssueNote(id: string, noteId: number | string) {
  return api<{ notes: NoteDTO[] }>(`/api/issues/${id}/notes/${noteId}`, {
    method: "DELETE"
  });
}

export function deleteMergeRequestNote(issueId: string, mergeRequestIid: number | string, noteId: number | string) {
  return api<{ notes: NoteDTO[] }>(`/api/issues/${issueId}/merge_requests/${mergeRequestIid}/notes/${noteId}`, {
    method: "DELETE"
  });
}
