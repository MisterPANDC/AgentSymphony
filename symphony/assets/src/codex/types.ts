export type JsonRpcId = string | number | null;

export type CodexJsonRpcMessage = {
  jsonrpc?: "2.0" | string;
  id?: JsonRpcId;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: unknown;
} & Record<string, unknown>;

export type CodexTurnStatus = "idle" | "inProgress" | "completed" | "failed" | "interrupted" | (string & {});

export type ApprovalDecision = "accept" | "acceptForSession" | "decline" | "cancel";

export type CodexRenderPart =
  | { type: "text"; id: string; text: string; raw?: unknown }
  | { type: "reasoning"; id: string; summary?: string; raw?: unknown }
  | { type: "plan"; id: string; steps: unknown[]; raw?: unknown }
  | { type: "command"; id: string; command: string; cwd?: string; status?: string; output?: string; raw?: unknown }
  | { type: "fileChange"; id: string; files: unknown[]; diff?: string; raw?: unknown }
  | { type: "approval"; id: string; requestId: string; approvalType: "command" | "fileChange"; payload: unknown; raw?: unknown }
  | { type: "toolCall"; id: string; name?: string; args?: unknown; result?: unknown; status?: string; raw?: unknown }
  | { type: "webSearch"; id: string; query?: string; raw?: unknown }
  | { type: "imageView"; id: string; path?: string; raw?: unknown }
  | { type: "error"; id: string; message: string; raw?: unknown }
  | { type: "unknown"; id: string; method?: string; raw: unknown };

export type CodexRenderState = {
  parts: CodexRenderPart[];
  status: CodexTurnStatus;
  activeTurnId?: string;
};

export type CodexNormalizedEvent =
  | { kind: "itemStarted"; item: Record<string, unknown>; raw: unknown }
  | { kind: "itemCompleted"; item: Record<string, unknown>; raw: unknown }
  | { kind: "agentMessageDelta"; itemId: string; delta: string; raw: unknown }
  | { kind: "reasoningDelta"; itemId: string; delta: string; raw: unknown }
  | { kind: "planDelta"; itemId: string; delta: string; raw: unknown }
  | { kind: "planUpdated"; id: string; steps: unknown[]; raw: unknown }
  | { kind: "commandOutputDelta"; itemId: string; delta: string; raw: unknown }
  | { kind: "fileChangePatchUpdated"; itemId: string; patch: unknown; raw: unknown }
  | { kind: "approvalRequested"; requestId: string; itemId?: string; approvalType: "command" | "fileChange"; payload: unknown; raw: unknown }
  | { kind: "approvalResolved"; requestId: string; raw: unknown }
  | { kind: "turnStarted"; status: CodexTurnStatus; turnId?: string; raw: unknown }
  | { kind: "turnCompleted"; status: CodexTurnStatus; turnId?: string; raw: unknown }
  | { kind: "error"; id: string; message: string; raw: unknown }
  | { kind: "unknown"; id: string; method?: string; raw: unknown };

export const initialCodexRenderState: CodexRenderState = {
  parts: [],
  status: "idle"
};
