export const workflowStatuses = ["triage", "todo", "in_progress", "review", "merging", "rework", "done", "canceled"] as const;

export type WorkflowStatus = (typeof workflowStatuses)[number];
export type IssueStatusFilter = WorkflowStatus | "all" | "blocked";
export const issueStatusFilters: IssueStatusFilter[] = ["all", "blocked", ...workflowStatuses];

export type Priority = "none" | "low" | "medium" | "high" | "urgent";

export interface IssueRelationRef {
  issueId: string;
  iid: number;
  identifier: string;
  title: string;
  status: WorkflowStatus;
  reason?: string | null;
  relationType?: "relates_to" | "blocks" | string | null;
  direction?: "incoming" | "outgoing" | string | null;
}

export interface IssueDTO {
  id: string;
  iid: number;
  identifier: string;
  gitlabIssueId: number;
  gitlabProjectId: number;
  webUrl: string;
  title: string;
  description: string | null;
  descriptionPreview: string | null;
  gitlabState: "opened" | "closed";
  workflowStatus: WorkflowStatus;
  priority: Priority;
  labels: string[];
  assignees: Array<{ id: number; username: string; name: string; avatarUrl: string | null }>;
  blockers: IssueRelationRef[];
  relations: {
    related: IssueRelationRef[];
    blocks: IssueRelationRef[];
    blockedBy: IssueRelationRef[];
  };
  isBlocked: boolean;
  unresolvedBlockerCount: number;
  openRuntimeBlockCount: number;
  blockedByCount: number;
  activeRunId: string | null;
  lastRunStatus: string | null;
  updatedAt: string;
  gitlabUpdatedAt: string;
  lastSyncAt: string | null;
}

export interface NoteDTO {
  id: string;
  note_id: number;
  body: string;
  author: { name: string; username: string } | null;
  system: boolean;
  internal: boolean;
  gitlab_created_at: string | null;
}
