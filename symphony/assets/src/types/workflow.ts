import type { WorkflowStatus } from "./issue";

export interface WorkflowSettingsDTO {
  statuses: WorkflowStatus[];
  dispatchCandidateStatuses: WorkflowStatus[];
  requiredGitlabLabels: string[];
  maxConcurrentAgents: number;
  syncIntervalMs: number;
  cursorOverlapSeconds: number;
  readOnlyImpacts: string;
}
