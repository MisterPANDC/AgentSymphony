import type { PointerEvent as ReactPointerEvent } from "react";
import { Ban, ChevronLeft, ChevronRight, Plus } from "lucide-react";
import { canUserCreateIssueInStatus, type IssueDTO, type WorkflowStatus } from "../../types/issue";
import { CreateIssueDialog } from "./CreateIssueDialog";
import { formatStatusLabel, StatusIcon } from "./StatusIcon";

export type BoardDropState = "idle" | "current" | "allowed" | "denied";

export function IssueColumn({
  status,
  issues,
  draggingIssue,
  dropState,
  isDragOver,
  dragDisabled,
  collapsed,
  onCollapsedChange,
  onIssueCreated,
  onIssueOpen,
  onIssuePointerDown
}: {
  status: WorkflowStatus;
  issues: IssueDTO[];
  draggingIssue: IssueDTO | null;
  dropState: BoardDropState;
  isDragOver: boolean;
  dragDisabled: boolean;
  collapsed: boolean;
  onCollapsedChange: () => void;
  onIssueCreated?: (issue: IssueDTO) => void;
  onIssueOpen: (issue: IssueDTO) => void;
  onIssuePointerDown: (event: ReactPointerEvent<HTMLElement>, issue: IssueDTO) => void;
}) {
  const columnClasses = [
    "board-column",
    collapsed ? "is-collapsed" : "",
    issues.length === 0 ? "is-empty" : "",
    draggingIssue ? "is-drag-active" : "",
    isDragOver ? "is-drag-over" : "",
    `is-drop-${dropState}`
  ]
    .filter(Boolean)
    .join(" ");
  const canCreateIssue = canUserCreateIssueInStatus(status);
  const statusLabel = formatStatusLabel(status);

  if (collapsed) {
    return (
      <section className={columnClasses} data-workflow-status={status}>
        <button className="board-collapsed-column-button" type="button" onClick={onCollapsedChange} aria-label={`Show ${statusLabel} column`} title="Show column">
          <span className="board-collapsed-column-title">
            <StatusIcon status={status} size={14} />
            <span>{statusLabel}</span>
          </span>
          <span className="issue-group-count">{issues.length}</span>
          <ChevronRight size={14} strokeWidth={1.8} />
        </button>
      </section>
    );
  }

  return (
    <section className={columnClasses} data-workflow-status={status}>
      <div className="board-column-header">
        <h2 className="board-column-title">
          <StatusIcon status={status} size={14} />
          <span>{statusLabel}</span>
          <span className="issue-group-count">{issues.length}</span>
        </h2>
        <div className="board-column-actions">
          {canCreateIssue && (
            <CreateIssueDialog
              defaultStatus={status}
              onCreated={onIssueCreated}
              trigger={
                <button className="board-column-icon-button" type="button" aria-label={`Create ${statusLabel} issue`} title="New issue">
                  <Plus size={14} strokeWidth={1.8} />
                </button>
              }
            />
          )}
          <button className="board-column-icon-button" type="button" onClick={onCollapsedChange} aria-label={`Hide ${statusLabel} column`} title="Hide column">
            <ChevronLeft size={14} strokeWidth={1.8} />
          </button>
        </div>
      </div>
      <div className="board-column-body">
        {draggingIssue && dropState === "denied" && (
          <div className="board-drop-blocked-indicator" aria-hidden="true">
            <span>
              <Ban size={18} strokeWidth={1.8} />
            </span>
          </div>
        )}
        {issues.map((issue) => (
          <article
            key={issue.id}
            className={`issue-card board-issue-card${draggingIssue?.id === issue.id ? " is-dragging" : ""}`}
            role="button"
            tabIndex={dragDisabled ? -1 : 0}
            aria-label={`Open ${issue.identifier}`}
            aria-disabled={dragDisabled}
            onKeyDown={(event) => {
              if (dragDisabled) {
                return;
              }

              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                onIssueOpen(issue);
              }
            }}
            onPointerDown={(event) => onIssuePointerDown(event, issue)}
          >
            <div className="mb-1 flex min-w-0 items-center gap-1.5">
              <span className="mono min-w-0 truncate text-[11px] text-[#686b73]">#{issue.iid}</span>
              {issue.isBlocked && (
                <span className="status-pill blocked">
                  <StatusIcon status="blocked" size={12} />
                  blocked
                </span>
              )}
            </div>
            <h3 className="line-clamp-2 text-sm font-medium leading-5 text-[#1d1d1f]">{issue.title}</h3>
          </article>
        ))}
      </div>
    </section>
  );
}
