import { api } from "./client";
import type { AgentRunDTO } from "../types/run";

export const dispatchAgents = () => api<{ dispatch: unknown }>(`/api/agents/dispatch`, { method: "POST" });
export const runIssue = (id: string) => api<{ run: AgentRunDTO }>(`/api/issues/${id}/run`, { method: "POST" });
