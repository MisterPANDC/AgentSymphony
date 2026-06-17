import { useState, type ReactNode } from "react";
import type { ApprovalDecision, CodexRenderPart } from "../../codex";

export type CodexPartRendererProps = {
  part: CodexRenderPart;
  onResolveApproval?: (requestId: string, decision: ApprovalDecision) => Promise<void> | void;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown) => (typeof value === "string" ? value : undefined);

const prettyJson = (value: unknown) => {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
};

const titleForApproval = (part: Extract<CodexRenderPart, { type: "approval" }>) => {
  const payload = isRecord(part.payload) ? part.payload : undefined;
  if (part.approvalType === "command") return text(payload?.command) ?? "Approve command?";
  return "Approve file changes?";
};

const fileLabel = (file: unknown, index: number) => {
  if (!isRecord(file)) return `File ${index + 1}`;
  return text(file.path) ?? text(file.file) ?? `File ${index + 1}`;
};

const stepLabel = (step: unknown, index: number) => {
  if (!isRecord(step)) return String(step);
  const label = text(step.step) ?? text(step.text) ?? `Step ${index + 1}`;
  const status = text(step.status);
  return status ? `${label} - ${status}` : label;
};

function Card({ children, tone }: { children: ReactNode; tone?: "error" | "warning" }) {
  return <section className={`ai-chat-codex-card${tone ? ` ${tone}` : ""}`}>{children}</section>;
}

function RawJson({ value }: { value: unknown }) {
  return (
    <pre className="ai-chat-raw-json">
      <code>{prettyJson(value)}</code>
    </pre>
  );
}

function TextPart({ part }: { part: Extract<CodexRenderPart, { type: "text" }> }) {
  return <div className="ai-chat-codex-text">{part.text}</div>;
}

function ReasoningPart({ part }: { part: Extract<CodexRenderPart, { type: "reasoning" }> }) {
  return (
    <details className="ai-chat-codex-details">
      <summary>Reasoning</summary>
      <div className="ai-chat-codex-detail-body">{part.summary || "No reasoning summary was provided."}</div>
    </details>
  );
}

function PlanPart({ part }: { part: Extract<CodexRenderPart, { type: "plan" }> }) {
  return (
    <Card>
      <div className="ai-chat-card-title">Plan</div>
      {part.steps.length ? (
        <ol className="ai-chat-plan-list">
          {part.steps.map((step, index) => (
            <li key={index}>{stepLabel(step, index)}</li>
          ))}
        </ol>
      ) : (
        <div className="ai-chat-muted">No plan steps yet.</div>
      )}
    </Card>
  );
}

function CommandPart({ part }: { part: Extract<CodexRenderPart, { type: "command" }> }) {
  return (
    <Card>
      <div className="ai-chat-card-title-row">
        <span>Command</span>
        {part.status ? <span className="ai-chat-mini-pill">{part.status}</span> : null}
      </div>
      <pre className="ai-chat-code-block">
        <code>{part.command.trim() || "Codex activity"}</code>
      </pre>
      {part.cwd ? <div className="ai-chat-path">cwd: {part.cwd}</div> : null}
      {part.output ? (
        <pre className="ai-chat-code-block output">
          <code>{part.output}</code>
        </pre>
      ) : null}
    </Card>
  );
}

function FileChangePart({ part }: { part: Extract<CodexRenderPart, { type: "fileChange" }> }) {
  return (
    <Card>
      <div className="ai-chat-card-title">File changes</div>
      {part.files.length ? (
        <ul className="ai-chat-file-list">
          {part.files.map((file, index) => (
            <li key={index}>{fileLabel(file, index)}</li>
          ))}
        </ul>
      ) : (
        <div className="ai-chat-muted">No file list yet.</div>
      )}
      {part.diff ? (
        <pre className="ai-chat-code-block output">
          <code>{part.diff}</code>
        </pre>
      ) : null}
    </Card>
  );
}

function ApprovalPart({ part, onResolveApproval }: { part: Extract<CodexRenderPart, { type: "approval" }>; onResolveApproval?: CodexPartRendererProps["onResolveApproval"] }) {
  const [pendingDecision, setPendingDecision] = useState<ApprovalDecision | null>(null);
  const [error, setError] = useState<string | null>(null);

  const resolve = async (decision: ApprovalDecision) => {
    if (!onResolveApproval) return;
    setError(null);
    setPendingDecision(decision);
    try {
      await onResolveApproval(part.requestId, decision);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not resolve approval.");
    } finally {
      setPendingDecision(null);
    }
  };

  const buttons: { decision: ApprovalDecision; label: string }[] = [
    { decision: "accept", label: "Approve once" },
    { decision: "acceptForSession", label: "Approve session" },
    { decision: "decline", label: "Decline" },
    { decision: "cancel", label: "Cancel" }
  ];

  return (
    <Card tone="warning">
      <div className="ai-chat-card-title">Approval required</div>
      <div className="ai-chat-approval-title">{titleForApproval(part)}</div>
      <div className="ai-chat-approval-actions">
        {buttons.map(({ decision, label }) => (
          <button key={decision} type="button" disabled={!onResolveApproval || pendingDecision !== null} onClick={() => void resolve(decision)}>
            {pendingDecision === decision ? "Resolving..." : label}
          </button>
        ))}
      </div>
      {!onResolveApproval ? <div className="ai-chat-muted">Approval handling is not available for this chat turn.</div> : null}
      {error ? <div className="ai-chat-error-copy">{error}</div> : null}
      <details className="ai-chat-codex-details nested">
        <summary>Raw approval payload</summary>
        <RawJson value={part.payload} />
      </details>
    </Card>
  );
}

function ToolCallPart({ part }: { part: Extract<CodexRenderPart, { type: "toolCall" }> }) {
  return (
    <details className="ai-chat-codex-details">
      <summary>
        Tool call{part.name ? `: ${part.name}` : ""}
        {part.status ? ` - ${part.status}` : ""}
      </summary>
      {part.args !== undefined ? <RawJson value={part.args} /> : null}
      {part.result !== undefined ? <RawJson value={part.result} /> : null}
    </details>
  );
}

function ErrorPart({ part }: { part: Extract<CodexRenderPart, { type: "error" }> }) {
  return (
    <Card tone="error">
      <div className="ai-chat-card-title">Codex error</div>
      <div className="ai-chat-error-copy">{part.message}</div>
    </Card>
  );
}

function UnknownPart({ part }: { part: Extract<CodexRenderPart, { type: "unknown" }> }) {
  return (
    <details className="ai-chat-codex-details unknown">
      <summary>Unknown Codex event{part.method ? `: ${part.method}` : ""}</summary>
      <RawJson value={part.raw} />
    </details>
  );
}

export function CodexPartRenderer({ part, onResolveApproval }: CodexPartRendererProps) {
  switch (part.type) {
    case "text":
      return <TextPart part={part} />;
    case "reasoning":
      return <ReasoningPart part={part} />;
    case "plan":
      return <PlanPart part={part} />;
    case "command":
      return <CommandPart part={part} />;
    case "fileChange":
      return <FileChangePart part={part} />;
    case "approval":
      return <ApprovalPart part={part} onResolveApproval={onResolveApproval} />;
    case "toolCall":
      return <ToolCallPart part={part} />;
    case "webSearch":
      return <Card>Web search{part.query ? <span className="ai-chat-inline-code">: {part.query}</span> : ""}</Card>;
    case "imageView":
      return <Card>Image viewed{part.path ? <span className="ai-chat-inline-code">: {part.path}</span> : ""}</Card>;
    case "error":
      return <ErrorPart part={part} />;
    case "unknown":
      return <UnknownPart part={part} />;
  }
}
