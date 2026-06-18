import { api } from "./client";

export interface AiChatEventDTO {
  id: string;
  seq: number;
  type: string;
  payload: unknown;
  insertedAt: string;
}

export interface AiChatDTO {
  status: "idle" | "running" | "failed" | string;
  workspace: string | null;
  events: AiChatEventDTO[];
}

export interface AiChatMessageInput {
  message: string;
  agentOptions?: {
    agentId?: string;
    provider?: string;
    codex?: {
      effort?: "low" | "medium" | "high" | "xhigh";
    };
  };
}

export const getAiChat = () => api<{ chat: AiChatDTO }>("/api/ai_chat");

export const sendAiChatMessage = (input: string | AiChatMessageInput) =>
  api<{ chat: AiChatDTO }>("/api/ai_chat/messages", {
    method: "POST",
    body: JSON.stringify(typeof input === "string" ? { message: input } : input)
  });

export const resolveAiChatApproval = (requestId: string, decision: string) =>
  api<{ chat: AiChatDTO }>(`/api/ai_chat/approvals/${encodeURIComponent(requestId)}`, {
    method: "POST",
    body: JSON.stringify({ decision })
  });

export const resetAiChat = () => api<{ ok: true }>("/api/ai_chat/reset", { method: "POST" });
