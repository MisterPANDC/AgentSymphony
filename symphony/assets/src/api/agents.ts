import { api } from "./client";

export const dispatchAgents = () => api<{ dispatch: unknown }>(`/api/agents/dispatch`, { method: "POST" });
