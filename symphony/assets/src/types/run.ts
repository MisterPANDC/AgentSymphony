export type RunStatus = "queued" | "starting" | "running" | "blocked" | "succeeded" | "failed" | "canceled" | "stale";

export interface AgentRunDTO {
  id: string;
  issueId: string;
  issueIdentifier: string;
  issueTitle: string;
  issueWebUrl: string;
  runNumber: number;
  status: RunStatus;
  workspacePath: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  lastHeartbeatAt: string | null;
  currentTurn: number | null;
  exitReason: string | null;
  errorMessage: string | null;
}
