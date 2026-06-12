import { api } from "./client";
import type { IssueDTO, WorkflowStatus } from "../types/issue";

export const getWorkflowStatuses = () => api<{ statuses: WorkflowStatus[]; priorities: string[] }>(`/api/workflow/statuses`);
export const addBlocker = (id: string, blockingIssueId: string, reason?: string) =>
  api<{ blockers: IssueDTO["blockers"] }>(`/api/issues/${id}/blockers`, {
    method: "POST",
    body: JSON.stringify({ blocking_issue_id: blockingIssueId, reason })
  });
export const removeBlocker = (id: string, blockingIssueId: string) =>
  api<{ blockers: IssueDTO["blockers"] }>(`/api/issues/${id}/blockers/${blockingIssueId}`, { method: "DELETE" });
