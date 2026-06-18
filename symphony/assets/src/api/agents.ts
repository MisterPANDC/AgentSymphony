import { api } from "./client";
import type { AgentAssetRegistryDTO, AgentAuthMode, AgentMcpRegistryDTO, AgentMcpServerDTO, AvailableAgentDTO, RegisteredAgentDTO } from "../types/agent";

export const dispatchAgents = () => api<{ dispatch: unknown }>(`/api/agents/dispatch`, { method: "POST" });

export const listAgents = () => api<{ agents: RegisteredAgentDTO[]; availableAgents: AvailableAgentDTO[]; mcp: AgentMcpRegistryDTO; assets: AgentAssetRegistryDTO }>(`/api/agents`);

export const registerAgent = (input: {
  provider: "codex";
  name?: string;
  authMode: AgentAuthMode;
  apiKey?: string;
  authJson?: string;
  mcpServerNames?: string[];
  skillNames?: string[];
  pluginNames?: string[];
}) =>
  api<{ agent: RegisteredAgentDTO; login: { command?: string | null; startedAt?: string | null } }>(`/api/agents/register`, {
    method: "POST",
    body: JSON.stringify(input)
  });

export const loginAgent = (input: string | { id: string; apiKey?: string; authJson?: string }) => {
  const id = typeof input === "string" ? input : input.id;
  const body = typeof input === "string" ? undefined : JSON.stringify(input);

  return api<{ agent: RegisteredAgentDTO; login: { command?: string | null; startedAt?: string | null } }>(`/api/agents/${id}/login`, {
    method: "POST",
    body
  });
};

export const updateAgent = (input: { id: string; name?: string; mcpServerNames?: string[] }) =>
  api<{ agent: RegisteredAgentDTO }>(`/api/agents/${input.id}`, {
    method: "PATCH",
    body: JSON.stringify(input)
  });

export const deleteAgent = (id: string) =>
  api<{ agent: RegisteredAgentDTO }>(`/api/agents/${id}`, {
    method: "DELETE"
  });

export const listAgentMcp = () => api<{ mcp: AgentMcpRegistryDTO }>(`/api/agents/mcp`);

export const saveAgentMcpRegistry = (input: { mcpServers: Record<string, AgentMcpServerDTO> }) =>
  api<{ mcp: AgentMcpRegistryDTO }>(`/api/agents/mcp`, {
    method: "POST",
    body: JSON.stringify(input)
  });

export const saveAgentAssetRegistry = (input: { skills: AgentAssetRegistryDTO["skills"]; plugins: AgentAssetRegistryDTO["plugins"] }) =>
  api<{ assets: AgentAssetRegistryDTO }>(`/api/agents/assets`, {
    method: "POST",
    body: JSON.stringify(input)
  });

export const installAgentAsset = (input: { id: string; kind: "skills" | "plugins"; name: string }) =>
  api<{ agent: RegisteredAgentDTO }>(`/api/agents/${input.id}/assets/${input.kind}/${encodeURIComponent(input.name)}`, {
    method: "POST"
  });

export const removeAgentAsset = (input: { id: string; kind: "skills" | "plugins"; name: string }) =>
  api<{ agent: RegisteredAgentDTO }>(`/api/agents/${input.id}/assets/${input.kind}/${encodeURIComponent(input.name)}`, {
    method: "DELETE"
  });

export const refreshAgentUsage = (id: string) =>
  api<{ agent: RegisteredAgentDTO }>(`/api/agents/${id}/usage`, {
    method: "POST"
  });
