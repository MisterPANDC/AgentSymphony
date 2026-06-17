import type { CodexJsonRpcMessage, CodexNormalizedEvent, CodexTurnStatus, JsonRpcId } from "./types";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const asRecord = (value: unknown): Record<string, unknown> | undefined => (isRecord(value) ? value : undefined);
const asString = (value: unknown): string | undefined => (typeof value === "string" ? value : undefined);
const asArray = (value: unknown): unknown[] | undefined => (Array.isArray(value) ? value : undefined);

const asStringish = (value: unknown): string | undefined => {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return undefined;
};

const field = (record: Record<string, unknown> | undefined, key: string) => record?.[key];
const stringField = (record: Record<string, unknown> | undefined, key: string) => asString(field(record, key));
const stringishField = (record: Record<string, unknown> | undefined, key: string) => asStringish(field(record, key));
const paramsOf = (message: Record<string, unknown>) => asRecord(message.params);

const idToString = (id: JsonRpcId | undefined): string | undefined => {
  if (typeof id === "string" || typeof id === "number") return String(id);
  return undefined;
};

export const hashUnknown = (value: unknown): string => {
  let input: string;
  try {
    input = JSON.stringify(value);
  } catch {
    input = String(value);
  }

  let hash = 5381;
  for (let i = 0; i < input.length; i += 1) {
    hash = (hash * 33) ^ input.charCodeAt(i);
  }
  return (hash >>> 0).toString(36);
};

const unknownEvent = (raw: unknown, method?: string, idPrefix = "unknown"): CodexNormalizedEvent => ({
  kind: "unknown",
  id: `${idPrefix}:${method ?? "no-method"}:${hashUnknown(raw)}`,
  method,
  raw
});

const getItem = (params: Record<string, unknown> | undefined) => asRecord(field(params, "item"));
const getItemId = (params: Record<string, unknown> | undefined) => stringishField(params, "itemId") ?? stringishField(getItem(params), "id");
const getDelta = (params: Record<string, unknown> | undefined) =>
  stringField(params, "delta") ?? stringField(params, "text") ?? stringField(params, "output") ?? stringField(params, "chunk") ?? "";

const getErrorMessage = (value: unknown): string | undefined => {
  if (typeof value === "string") return value;
  const record = asRecord(value);
  const nested = asRecord(record?.error);
  return stringField(record, "message") ?? stringField(nested, "message") ?? stringField(record, "error");
};

const getTurn = (params: Record<string, unknown> | undefined) => asRecord(field(params, "turn"));
const getTurnId = (turn: Record<string, unknown> | undefined) => stringishField(turn, "id");
const getTurnStatus = (turn: Record<string, unknown> | undefined, fallback: CodexTurnStatus): CodexTurnStatus => stringField(turn, "status") ?? fallback;

export function extractCodexJsonRpc(raw: unknown): unknown {
  const event = asRecord(raw);
  const payload = asRecord(field(event, "payload"));
  const nestedPayload = payload ? field(payload, "payload") : undefined;

  if (typeof field(payload, "raw") === "string") {
    try {
      return JSON.parse(field(payload, "raw") as string);
    } catch {
      return field(payload, "payload") ?? payload;
    }
  }

  if (isRecord(nestedPayload) && typeof nestedPayload.method === "string") return nestedPayload;
  if (isRecord(payload) && typeof payload.method === "string") return payload;
  if (isRecord(raw) && typeof raw.method === "string") return raw;
  return raw;
}

export function normalizeCodexEvent(rawInput: CodexJsonRpcMessage | unknown): CodexNormalizedEvent {
  const raw = extractCodexJsonRpc(rawInput);
  const message = asRecord(raw);
  if (!message) return unknownEvent(rawInput);

  const method = asString(message.method);
  const params = paramsOf(message);

  if (!method) {
    const errorMessage = getErrorMessage(message.error);
    if (errorMessage) {
      return {
        kind: "error",
        id: `error:${idToString(message.id as JsonRpcId | undefined) ?? hashUnknown(raw)}`,
        message: errorMessage,
        raw: rawInput
      };
    }
    return unknownEvent(rawInput);
  }

  switch (method) {
    case "turn/started":
      return { kind: "turnStarted", status: getTurnStatus(getTurn(params), "inProgress"), turnId: getTurnId(getTurn(params)), raw: rawInput };
    case "turn/completed":
      return { kind: "turnCompleted", status: getTurnStatus(getTurn(params), "completed"), turnId: getTurnId(getTurn(params)), raw: rawInput };
    case "turn/failed":
      return { kind: "error", id: `turn-failed:${hashUnknown(rawInput)}`, message: getErrorMessage(params) ?? "Codex turn failed.", raw: rawInput };
    case "turn/cancelled":
      return { kind: "turnCompleted", status: "interrupted", raw: rawInput };
    case "turn/plan/updated":
      return { kind: "planUpdated", id: `turn-plan:${stringishField(params, "turnId") ?? hashUnknown(rawInput)}`, steps: asArray(field(params, "plan")) ?? [], raw: rawInput };
    case "item/started": {
      const item = getItem(params);
      return item ? { kind: "itemStarted", item, raw: rawInput } : unknownEvent(rawInput, method, "item-started");
    }
    case "item/completed": {
      const item = getItem(params);
      return item ? { kind: "itemCompleted", item, raw: rawInput } : unknownEvent(rawInput, method, "item-completed");
    }
    case "item/agentMessage/delta": {
      const itemId = getItemId(params);
      return itemId ? { kind: "agentMessageDelta", itemId, delta: getDelta(params), raw: rawInput } : unknownEvent(rawInput, method, "agent-message-delta");
    }
    case "item/reasoning/summaryTextDelta":
    case "item/reasoning/summaryPartAdded":
    case "item/reasoning/textDelta": {
      const itemId = getItemId(params);
      return itemId ? { kind: "reasoningDelta", itemId, delta: getDelta(params), raw: rawInput } : unknownEvent(rawInput, method, "reasoning-delta");
    }
    case "item/plan/delta": {
      const itemId = getItemId(params);
      return itemId ? { kind: "planDelta", itemId, delta: getDelta(params), raw: rawInput } : unknownEvent(rawInput, method, "plan-delta");
    }
    case "item/commandExecution/outputDelta":
    case "item/fileChange/outputDelta": {
      const itemId = getItemId(params);
      return itemId ? { kind: "commandOutputDelta", itemId, delta: getDelta(params), raw: rawInput } : unknownEvent(rawInput, method, "command-output-delta");
    }
    case "item/fileChange/patchUpdated": {
      const itemId = getItemId(params);
      return itemId ? { kind: "fileChangePatchUpdated", itemId, patch: field(params, "patch") ?? params, raw: rawInput } : unknownEvent(rawInput, method, "file-change-patch");
    }
    case "item/commandExecution/requestApproval":
    case "execCommandApproval": {
      return {
        kind: "approvalRequested",
        requestId: idToString(message.id as JsonRpcId | undefined) ?? stringishField(params, "requestId") ?? hashUnknown(rawInput),
        itemId: getItemId(params),
        approvalType: "command",
        payload: params ?? message,
        raw: rawInput
      };
    }
    case "item/fileChange/requestApproval":
    case "applyPatchApproval": {
      return {
        kind: "approvalRequested",
        requestId: idToString(message.id as JsonRpcId | undefined) ?? stringishField(params, "requestId") ?? hashUnknown(rawInput),
        itemId: getItemId(params),
        approvalType: "fileChange",
        payload: params ?? message,
        raw: rawInput
      };
    }
    case "serverRequest/resolved": {
      const requestId = stringishField(params, "requestId");
      return requestId ? { kind: "approvalResolved", requestId, raw: rawInput } : unknownEvent(rawInput, method, "server-request-resolved");
    }
    case "error":
      return { kind: "error", id: `error:${hashUnknown(rawInput)}`, message: getErrorMessage(params) ?? "Codex app-server error", raw: rawInput };
    default:
      return unknownEvent(rawInput, method);
  }
}
