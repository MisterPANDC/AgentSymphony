export const workflowStatuses = ["backlog", "todo", "in_progress", "review", "merging", "rework", "done", "canceled"] as const;

export type WorkflowStatus = (typeof workflowStatuses)[number];
export type IssueStatusFilter = WorkflowStatus | "all" | "blocked";
export const issueStatusFilters: IssueStatusFilter[] = ["all", "blocked", ...workflowStatuses];
export const dispatchCandidateStatuses = ["todo", "in_progress", "merging", "rework"] as const satisfies readonly WorkflowStatus[];
export const userCreatableWorkflowStatuses = ["backlog", "todo"] as const satisfies readonly WorkflowStatus[];
export const userTransitionTargets: Record<WorkflowStatus, WorkflowStatus[]> = {
  backlog: ["todo", "canceled"],
  todo: ["backlog", "canceled"],
  in_progress: ["backlog", "canceled"],
  review: ["backlog", "merging", "rework", "canceled"],
  merging: ["canceled"],
  rework: ["backlog", "canceled"],
  done: [],
  canceled: ["backlog"]
};

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
  mergeRequestCount: number | null;
  activeRunId: string | null;
  lastRunStatus: string | null;
  updatedAt: string;
  gitlabUpdatedAt: string;
  lastSyncAt: string | null;
}

export interface GitLabUserDTO {
  id?: number | string | null;
  username?: string | null;
  name?: string | null;
  avatarUrl?: string | null;
  webUrl?: string | null;
}

export interface MergeRequestDTO {
  id: number;
  iid: number;
  title: string;
  description: string | null;
  state: "opened" | "closed" | "locked" | "merged" | string;
  draft: boolean;
  workInProgress: boolean;
  webUrl: string;
  sourceBranch: string;
  targetBranch: string;
  mergeStatus: string | null;
  detailedMergeStatus: string | null;
  createdAt: string | null;
  updatedAt: string | null;
  mergedAt: string | null;
  closedAt: string | null;
  labels: string[];
  author: GitLabUserDTO | null;
  assignees: GitLabUserDTO[];
  reviewers: GitLabUserDTO[];
  milestone: {
    id?: number | string | null;
    iid?: number | string | null;
    title?: string | null;
    state?: string | null;
    dueDate?: string | null;
  } | null;
  userNotesCount: number | null;
  upvotes: number | null;
  downvotes: number | null;
  changesCount: string | number | null;
  references: Record<string, string | number | null>;
  headPipeline: {
    id?: number | string | null;
    status?: string | null;
    ref?: string | null;
    webUrl?: string | null;
    updatedAt?: string | null;
  } | null;
  raw: Record<string, unknown>;
}

export function canUserTransition(from: WorkflowStatus, to: WorkflowStatus) {
  return from === to || userTransitionTargets[from].includes(to);
}

export function isDispatchCandidateStatus(status: WorkflowStatus) {
  return dispatchCandidateStatuses.includes(status as (typeof dispatchCandidateStatuses)[number]);
}

export function canUserCreateIssueInStatus(status: WorkflowStatus) {
  return userCreatableWorkflowStatuses.includes(status as (typeof userCreatableWorkflowStatuses)[number]);
}

export interface NoteDTO {
  id: string;
  note_id: number;
  discussion_id?: string | null;
  discussion_reply?: boolean;
  discussion_individual_note?: boolean;
  discussion_position?: number | null;
  body: string;
  author: {
    id?: number | string | null;
    name?: string | null;
    username?: string | null;
    avatarUrl?: string | null;
    avatar_url?: string | null;
    webUrl?: string | null;
    web_url?: string | null;
  } | null;
  system: boolean;
  internal: boolean;
  gitlab_created_at: string | null;
  gitlab_updated_at?: string | null;
}
