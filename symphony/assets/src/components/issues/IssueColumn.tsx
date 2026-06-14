import type { PointerEvent as ReactPointerEvent } from "react";
import { Ban, Plus } from "lucide-react";
import type { IssueDTO, WorkflowStatus } from "../../types/issue";
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
  onIssueCreated?: (issue: IssueDTO) => void;
  onIssueOpen: (issue: IssueDTO) => void;
  onIssuePointerDown: (event: ReactPointerEvent<HTMLElement>, issue: IssueDTO) => void;
}) {
  const columnClasses = ["panel board-column min-h-[320px]", draggingIssue ? "is-drag-active" : "", isDragOver ? "is-drag-over" : "", `is-drop-${dropState}`]
    .filter(Boolean)
    .join(" ");

  return (
    <section
      className={columnClasses}
      data-workflow-status={status}
    >
      <div className="panel-header">
        <h2 className="flex items-center gap-2 text-xs font-semibold capitalize text-[#4f535c]">
          <StatusIcon status={status} size={14} />
          {formatStatusLabel(status)}
        </h2>
        <div className="board-header-meta">
          <span className="board-count">{issues.length}</span>
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
              <span className="mono min-w-0 truncate text-[11px] text-[#686b73]">{issue.identifier}</span>
              {issue.isBlocked && (
                <span className="status-pill blocked">
                  <StatusIcon status="blocked" size={12} />
                  blocked
                </span>
              )}
              {issue.activeRunId && (
                <span className="status-pill in_progress">
                  <StatusIcon status="in_progress" size={12} />
                  active run
                </span>
              )}
            </div>
            <h3 className="line-clamp-2 text-sm font-medium leading-5 text-[#1d1d1f]">{issue.title}</h3>
          </article>
        ))}
        <CreateIssueDialog
          defaultStatus={status}
          onCreated={onIssueCreated}
          trigger={
            <button className="board-add-issue-button" type="button">
              <Plus size={14} />
              <span>New issue</span>
            </button>
          }
        />
      </div>
    </section>
  );
}
