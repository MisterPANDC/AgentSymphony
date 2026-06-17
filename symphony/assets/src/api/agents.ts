import { api } from "./client";
import type { AgentAuthMode, AgentMcpRegistryDTO, AvailableAgentDTO, RegisteredAgentDTO } from "../types/agent";

export const dispatchAgents = () => api<{ dispatch: unknown }>(`/api/agents/dispatch`, { method: "POST" });

export const listAgents = () => api<{ agents: RegisteredAgentDTO[]; availableAgents: AvailableAgentDTO[]; mcp: AgentMcpRegistryDTO }>(`/api/agents`);

export const registerAgent = (input: { provider: "codex"; name?: string; authMode: AgentAuthMode; apiKey?: string; authJson?: string; mcpServerNames?: string[] }) =>
  api<{ agent: RegisteredAgentDTO; login: { command?: string | null; startedAt?: string | null } }>(`/api/agents/register`, {
    method: "POST",
    body: JSON.stringify(input)
  });

export const listAgentMcp = () => api<{ mcp: AgentMcpRegistryDTO }>(`/api/agents/mcp`);

export const createAgentMcpServer = (input: { name: string; command: string; args?: string[]; env?: Record<string, string>; startupTimeoutSec?: number }) =>
  api<{ mcp: AgentMcpRegistryDTO }>(`/api/agents/mcp`, {
    method: "POST",
    body: JSON.stringify(input)
  });

export const refreshAgentUsage = (id: string) =>
  api<{ agent: RegisteredAgentDTO }>(`/api/agents/${id}/usage`, {
    method: "POST"
  });
