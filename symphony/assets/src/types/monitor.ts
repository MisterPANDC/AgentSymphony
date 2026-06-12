import type { AgentRunDTO } from "./run";

export interface RuntimeBlockDTO {
  id: string;
  issueId: string;
  issueIdentifier: string;
  issueTitle: string;
  issueWebUrl: string;
  agentRunId: string | null;
  blockType:
    | "operator_input"
    | "approval_required"
    | "mcp_elicitation"
    | "sandbox_rejection"
    | "external_failure"
    | "blocked_by_dependency";
  message: string | null;
  insertedAt: string;
}

export interface MonitorEventDTO {
  id: string;
  type: string;
  message: string | null;
  insertedAt: string;
  issueIdentifier: string | null;
  runId: string | null;
}

export interface MonitorStateDTO {
  runtime: {
    mode: "local_single_user";
    appVersion: string | null;
    uptimeSeconds: number;
    bindHost: string;
    port: number;
    workflowPath: string;
    workflowLoaded: boolean;
    workflowLastLoadedAt: string | null;
    workflowLastError: string | null;
  };
  gitlab: {
    apiRoot: string | null;
    projectRef: string | null;
    projectId: number | null;
    projectName: string | null;
    projectWebUrl: string | null;
    readOnly: boolean;
    lastValidationAt: string | null;
    lastValidationError: string | null;
  };
  sync: {
    issueLastSuccessAt: string | null;
    issueLastAttemptAt: string | null;
    issueLastError: string | null;
    notesLastSuccessAt: string | null;
    pending: boolean;
    nextRunAt: string | null;
  };
  agents: {
    maxConcurrent: number;
    queued: number;
    starting: number;
    running: number;
    blocked: number;
    succeededRecent: number;
    failedRecent: number;
  };
  activeRuns: AgentRunDTO[];
  blocked: RuntimeBlockDTO[];
  recentEvents: MonitorEventDTO[];
}
