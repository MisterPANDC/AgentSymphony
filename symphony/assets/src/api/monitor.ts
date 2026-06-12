import { api } from "./client";
import type { MonitorStateDTO, RuntimeBlockDTO } from "../types/monitor";
import type { AgentRunDTO } from "../types/run";

export const getMonitorState = () => api<MonitorStateDTO>(`/api/monitor/state`);
export const refreshMonitor = () => api<MonitorStateDTO>(`/api/monitor/refresh`, { method: "POST" });
export const listMonitorBlocks = () => api<{ blocks: RuntimeBlockDTO[] }>(`/api/monitor/blocks`);
export const resolveBlock = (id: string) => api<{ block: RuntimeBlockDTO }>(`/api/monitor/blocks/${id}/resolve`, { method: "POST" });
export const listMonitorRuns = () => api<{ runs: AgentRunDTO[] }>(`/api/monitor/runs`);
