import { hashUnknown, normalizeCodexEvent } from "./normalizeCodexEvent";
import type { CodexJsonRpcMessage, CodexNormalizedEvent, CodexRenderPart, CodexRenderState } from "./types";
import { initialCodexRenderState } from "./types";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const asString = (value: unknown): string | undefined => (typeof value === "string" ? value : undefined);
const asArray = (value: unknown): unknown[] | undefined => (Array.isArray(value) ? value : undefined);
const asStringish = (value: unknown): string | undefined => {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return undefined;
};
const field = (record: Record<string, unknown> | undefined, key: string) => record?.[key];
const append = (current: string | undefined, delta: string) => `${current ?? ""}${delta}`;

const itemId = (item: Record<string, unknown>, raw: unknown) => asStringish(item.id) ?? `item:${hashUnknown(raw)}`;
const itemType = (item: Record<string, unknown>) => asString(field(item, "type"));

const commandName = (item: Record<string, unknown>) => {
  const server = asStringish(field(item, "server"));
  const tool = asStringish(field(item, "tool"));
  if (server && tool) return `${server}/${tool}`;
  return tool ?? server;
};

const diffFromChanges = (changes: unknown[] | undefined): string | undefined => {
  if (!changes?.length) return undefined;
  const diffs = changes
    .map((change) => (isRecord(change) ? asString(field(change, "diff")) : undefined))
    .filter((diff): diff is string => Boolean(diff));
  return diffs.length ? diffs.join("\n") : undefined;
};

const upsertPart = (state: CodexRenderState, part: CodexRenderPart, insertAfterId?: string): CodexRenderState => {
  const index = state.parts.findIndex((existing) => existing.id === part.id);
  if (index >= 0) {
    const parts = [...state.parts];
    parts[index] = part;
    return { ...state, parts };
  }

  if (insertAfterId) {
    const afterIndex = state.parts.findIndex((existing) => existing.id === insertAfterId);
    if (afterIndex >= 0) {
      const parts = [...state.parts];
      parts.splice(afterIndex + 1, 0, part);
      return { ...state, parts };
    }
  }

  return { ...state, parts: [...state.parts, part] };
};

const updatePart = (state: CodexRenderState, id: string, create: () => CodexRenderPart, update: (part: CodexRenderPart) => CodexRenderPart): CodexRenderState => {
  const index = state.parts.findIndex((part) => part.id === id);
  if (index < 0) return upsertPart(state, create());

  const parts = [...state.parts];
  parts[index] = update(parts[index]);
  return { ...state, parts };
};

const toRenderPart = (item: Record<string, unknown>, raw: unknown, existing?: CodexRenderPart): CodexRenderPart => {
  const id = itemId(item, raw);

  switch (itemType(item)) {
    case "agentMessage":
      return { type: "text", id, text: asString(field(item, "text")) ?? (existing?.type === "text" ? existing.text : ""), raw };
    case "reasoning": {
      const summaryValue = field(item, "summary");
      const summary = Array.isArray(summaryValue) ? summaryValue.map((part) => String(part)).join("\n") : asString(summaryValue);
      return { type: "reasoning", id, summary: summary ?? (existing?.type === "reasoning" ? existing.summary : undefined), raw };
    }
    case "plan": {
      const text = asString(field(item, "text"));
      return { type: "plan", id, steps: text ? [text] : existing?.type === "plan" ? existing.steps : [], raw };
    }
    case "commandExecution":
      return {
        type: "command",
        id,
        command: asString(field(item, "command")) ?? (existing?.type === "command" ? existing.command : ""),
        cwd: asString(field(item, "cwd")) ?? (existing?.type === "command" ? existing.cwd : undefined),
        status: asString(field(item, "status")) ?? (existing?.type === "command" ? existing.status : undefined),
        output: asString(field(item, "aggregatedOutput")) ?? (existing?.type === "command" ? existing.output : undefined),
        raw
      };
    case "fileChange": {
      const files = asArray(field(item, "changes"));
      return { type: "fileChange", id, files: files ?? (existing?.type === "fileChange" ? existing.files : []), diff: diffFromChanges(files) ?? (existing?.type === "fileChange" ? existing.diff : undefined), raw };
    }
    case "mcpToolCall":
      return { type: "toolCall", id, name: commandName(item), args: field(item, "arguments"), result: field(item, "result") ?? field(item, "error"), status: asString(field(item, "status")), raw };
    case "dynamicToolCall":
      return { type: "toolCall", id, name: asStringish(field(item, "tool")), args: field(item, "arguments"), result: field(item, "contentItems") ?? field(item, "success"), status: asString(field(item, "status")), raw };
    case "webSearch":
      return { type: "webSearch", id, query: asString(field(item, "query")), raw };
    case "imageView":
      return { type: "imageView", id, path: asString(field(item, "path")), raw };
    default:
      return { type: "unknown", id, method: itemType(item), raw };
  }
};

const reduceNormalizedEvent = (state: CodexRenderState, event: CodexNormalizedEvent): CodexRenderState => {
  switch (event.kind) {
    case "turnStarted":
      return { parts: [], status: event.status, activeTurnId: event.turnId };
    case "turnCompleted":
      return { ...state, status: event.status, activeTurnId: event.turnId ?? state.activeTurnId };
    case "itemStarted":
    case "itemCompleted": {
      const id = itemId(event.item, event.raw);
      const existing = state.parts.find((part) => part.id === id);
      return upsertPart(state, toRenderPart(event.item, event.raw, existing));
    }
    case "agentMessageDelta":
      return updatePart(state, event.itemId, () => ({ type: "text", id: event.itemId, text: event.delta, raw: event.raw }), (part) => (part.type === "text" ? { ...part, text: append(part.text, event.delta), raw: event.raw } : { type: "text", id: event.itemId, text: event.delta, raw: event.raw }));
    case "reasoningDelta":
      return updatePart(state, event.itemId, () => ({ type: "reasoning", id: event.itemId, summary: event.delta, raw: event.raw }), (part) => (part.type === "reasoning" ? { ...part, summary: append(part.summary, event.delta), raw: event.raw } : { type: "reasoning", id: event.itemId, summary: event.delta, raw: event.raw }));
    case "planDelta":
      return updatePart(state, event.itemId, () => ({ type: "plan", id: event.itemId, steps: [event.delta], raw: event.raw }), (part) => {
        if (part.type !== "plan") return { type: "plan", id: event.itemId, steps: [event.delta], raw: event.raw };
        const steps = [...part.steps];
        const last = steps[steps.length - 1];
        if (typeof last === "string") steps[steps.length - 1] = append(last, event.delta);
        else steps.push(event.delta);
        return { ...part, steps, raw: event.raw };
      });
    case "planUpdated":
      return upsertPart(state, { type: "plan", id: event.id, steps: event.steps, raw: event.raw });
    case "commandOutputDelta":
      return updatePart(state, event.itemId, () => ({ type: "command", id: event.itemId, command: "", output: event.delta, raw: event.raw }), (part) => (part.type === "command" ? { ...part, output: append(part.output, event.delta), raw: event.raw } : { type: "command", id: event.itemId, command: "", output: event.delta, raw: event.raw }));
    case "fileChangePatchUpdated": {
      const patch = isRecord(event.patch) ? event.patch : undefined;
      const files = asArray(field(patch, "changes"));
      const diff = diffFromChanges(files) ?? asString(field(patch, "diff"));
      return updatePart(state, event.itemId, () => ({ type: "fileChange", id: event.itemId, files: files ?? [], diff, raw: event.raw }), (part) => (part.type === "fileChange" ? { ...part, files: files ?? part.files, diff: diff ?? part.diff, raw: event.raw } : { type: "fileChange", id: event.itemId, files: files ?? [], diff, raw: event.raw }));
    }
    case "approvalRequested":
      return upsertPart(state, { type: "approval", id: `approval:${event.requestId}`, requestId: event.requestId, approvalType: event.approvalType, payload: event.payload, raw: event.raw }, event.itemId);
    case "approvalResolved":
      return { ...state, parts: state.parts.filter((part) => !(part.type === "approval" && part.requestId === event.requestId)) };
    case "error":
      return upsertPart(state, { type: "error", id: event.id, message: event.message, raw: event.raw });
    case "unknown":
      return upsertPart(state, { type: "unknown", id: event.id, method: event.method, raw: event.raw });
  }
};

export function codexReducer(state: CodexRenderState = initialCodexRenderState, rawEvent: CodexJsonRpcMessage | unknown): CodexRenderState {
  try {
    return reduceNormalizedEvent(state, normalizeCodexEvent(rawEvent));
  } catch (error) {
    return upsertPart(state, {
      type: "error",
      id: `normalizer-error:${hashUnknown(rawEvent)}`,
      message: error instanceof Error ? error.message : "Failed to normalize Codex event",
      raw: rawEvent
    });
  }
}

export function reduceCodexEvents(events: readonly (CodexJsonRpcMessage | unknown)[], initialState: CodexRenderState = initialCodexRenderState): CodexRenderState {
  return events.reduce(codexReducer, initialState);
}
