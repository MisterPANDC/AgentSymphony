export type WorkflowStatus =
  | "triage"
  | "todo"
  | "in_progress"
  | "blocked"
  | "review"
  | "done"
  | "canceled";

export type Priority = "none" | "low" | "medium" | "high" | "urgent";

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
  blockers: Array<{ issueId: string; iid: number; identifier: string; title: string; status: WorkflowStatus }>;
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
