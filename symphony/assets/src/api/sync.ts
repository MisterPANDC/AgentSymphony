import { api } from "./client";

export const getSyncStatus = () => api<Record<string, unknown>>(`/api/sync/status`);
export const refreshSync = () => api<Record<string, unknown>>(`/api/sync/refresh`, { method: "POST" });
