export type AgentProvider = "codex";
export type AgentAuthMode = "subscription" | "api" | "auth_json";
export type AgentCredentialStatus = "pending" | "login_started" | "configured" | "failed";
export type AgentMcpInstallStatus = "pending" | "installing" | "configured" | "failed";
export type AgentAssetInstallStatus = "pending" | "installing" | "configured" | "failed";
export type AgentUsageStatus = "unknown" | "available" | "unavailable" | "not_applicable";

export interface AvailableAgentDTO {
  provider: AgentProvider;
  label: string;
  description: string;
  modes: AgentAuthMode[];
}

export interface RegisteredAgentDTO {
  id: string;
  provider: AgentProvider;
  name: string;
  authMode: AgentAuthMode;
  codexHome: string;
  credentialStatus: AgentCredentialStatus;
  loginStartedAt?: string | null;
  lastLoginExitStatus?: number | null;
  lastLoginMessage?: string | null;
  mcpInstallStatus: AgentMcpInstallStatus;
  mcpInstallStartedAt?: string | null;
  mcpInstallFinishedAt?: string | null;
  mcpInstallExitStatus?: number | null;
  mcpInstallMessage?: string | null;
  mcpServerNames: string[];
  mcpInstalledServers: AgentInstalledMcpServerDTO[];
  assetInstallStatus: AgentAssetInstallStatus;
  assetInstallStartedAt?: string | null;
  assetInstallFinishedAt?: string | null;
  assetInstallExitStatus?: number | null;
  assetInstallMessage?: string | null;
  skillNames: string[];
  pluginNames: string[];
  usage?: AgentUsageDTO;
  insertedAt?: string | null;
  updatedAt?: string | null;
}

export interface AgentInstalledMcpServerDTO {
  name: string;
  enabled: boolean;
  selected: boolean;
  registered: boolean;
}

export interface AgentMcpRegistryDTO {
  path: string;
  mcpServers: Record<string, AgentMcpServerDTO>;
  error?: string;
}

export interface AgentMcpServerDTO {
  command: string;
  args?: string[];
  env?: Record<string, string>;
  startup_timeout_sec?: number;
  startupTimeoutSec?: number;
}

export interface AgentAssetRegistryDTO {
  path: string;
  skillPath?: string;
  pluginPath?: string;
  skills: Record<string, AgentAssetDTO>;
  plugins: Record<string, AgentAssetDTO>;
  error?: string;
}

export interface AgentAssetDTO {
  path?: string;
  git_url?: string;
  content?: string;
  filename?: string;
}

export interface AgentUsageDTO {
  status: AgentUsageStatus;
  rateLimits?: CodexRateLimitsDTO | null;
  checkedAt?: string | null;
  error?: string | null;
  source?: "agent" | "runtime" | null;
}

export interface CodexRateLimitsDTO {
  limit_id?: string;
  limit_name?: string;
  primary?: CodexRateLimitBucketDTO;
  secondary?: CodexRateLimitBucketDTO;
  credits?: Record<string, unknown>;
}

export interface CodexRateLimitBucketDTO {
  remaining?: number;
  limit?: number;
  usedPercent?: number;
  windowDurationMins?: number;
  reset_in_seconds?: number;
  resetInSeconds?: number;
  reset_at?: string;
  resetAt?: string;
}
