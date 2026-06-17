import type { ApprovalDecision, CodexRenderPart, CodexTurnStatus } from "../../codex";
import { CodexPartRenderer } from "./CodexPartRenderer";

export type CodexMessageRendererProps = {
  parts: readonly CodexRenderPart[];
  status?: CodexTurnStatus;
  onResolveApproval?: (requestId: string, decision: ApprovalDecision) => Promise<void> | void;
};

const isRunning = (status: CodexTurnStatus | undefined) => status === "inProgress" || status === "running";

export function CodexMessageRenderer({ parts, status, onResolveApproval }: CodexMessageRendererProps) {
  if (!parts.length) {
    return isRunning(status) ? <div className="ai-chat-working">Codex is working...</div> : null;
  }

  return (
    <div className="ai-chat-codex-message">
      {parts.map((part) => (
        <CodexPartRenderer key={part.id} part={part} onResolveApproval={onResolveApproval} />
      ))}
    </div>
  );
}
