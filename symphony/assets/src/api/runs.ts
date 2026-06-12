import { api } from "./client";
import type { AgentRunDTO } from "../types/run";

export const listRuns = () => api<{ runs: AgentRunDTO[] }>(`/api/runs`);
export const getRun = (id: string) => api<{ run: AgentRunDTO }>(`/api/runs/${id}`);
export const cancelRun = (id: string) => api<{ run: AgentRunDTO }>(`/api/runs/${id}/cancel`, { method: "POST" });
export const retryRun = (id: string) => api<{ run: AgentRunDTO }>(`/api/runs/${id}/retry`, { method: "POST" });
