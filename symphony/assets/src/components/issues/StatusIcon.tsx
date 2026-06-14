import type { IssueStatusFilter, WorkflowStatus } from "../../types/issue";

export type StatusIconStatus = IssueStatusFilter | WorkflowStatus;

const statusLabels: Record<StatusIconStatus, string> = {
  all: "All",
  blocked: "Blocked",
  triage: "Triage",
  todo: "Todo",
  in_progress: "In Progress",
  review: "Human Review",
  merging: "Merging",
  rework: "Rework",
  done: "Done",
  canceled: "Canceled"
};

const statusKinds: Record<
  StatusIconStatus,
  | "all"
  | "triage"
  | "backlog"
  | "todo"
  | "started-quarter"
  | "started-half"
  | "started-three-quarter"
  | "started-rework"
  | "done"
  | "canceled"
  | "blocked"
> = {
  all: "all",
  blocked: "blocked",
  triage: "triage",
  todo: "todo",
  in_progress: "started-quarter",
  review: "started-half",
  merging: "started-three-quarter",
  rework: "started-rework",
  done: "done",
  canceled: "canceled"
};

export function formatStatusLabel(status: StatusIconStatus) {
  return statusLabels[status] ?? status.replace("_", " ");
}

export function statusIconForRunStatus(status: string): StatusIconStatus {
  if (status === "succeeded") return "done";
  if (status === "blocked" || status === "failed") return "blocked";
  if (status === "canceled" || status === "stale") return "canceled";
  return "in_progress";
}

function statusClassName(status: StatusIconStatus) {
  return status.replace(/_/g, "-");
}

export function StatusIcon({
  status,
  size = 14,
  className = ""
}: {
  status: StatusIconStatus;
  size?: number;
  className?: string;
}) {
  const kind = statusKinds[status] ?? "todo";
  const classes = ["linear-status-icon", `linear-status-icon--${statusClassName(status)}`, className].filter(Boolean).join(" ");

  return (
    <span className={classes} style={{ width: size, height: size }} aria-hidden="true">
      <svg viewBox="0 0 16 16" focusable="false">
        {kind === "all" && (
          <>
            <circle cx="5" cy="5" r="2" fill="currentColor" opacity="0.55" />
            <circle cx="11" cy="5" r="2" fill="currentColor" opacity="0.78" />
            <circle cx="5" cy="11" r="2" fill="currentColor" opacity="0.78" />
            <circle cx="11" cy="11" r="2" fill="currentColor" opacity="0.55" />
          </>
        )}
        {kind === "triage" && (
          <circle cx="8" cy="8" r="5.35" fill="none" stroke="currentColor" strokeDasharray="0.85 2.55" strokeLinecap="butt" strokeWidth="2.35" />
        )}
        {kind === "backlog" && <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" strokeDasharray="0.01 3.1" strokeLinecap="round" strokeWidth="2" />}
        {kind === "todo" && <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" strokeWidth="2" />}
        {kind === "started-quarter" && (
          <>
            <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" strokeWidth="2" />
            <path d="M8 8V2.8a5.2 5.2 0 0 1 5.2 5.2Z" fill="currentColor" />
          </>
        )}
        {kind === "started-half" && (
          <>
            <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" strokeWidth="2" />
            <path d="M8 8V2.8a5.2 5.2 0 0 1 0 10.4Z" fill="currentColor" />
          </>
        )}
        {kind === "started-three-quarter" && (
          <>
            <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" strokeWidth="2" />
            <path d="M8 8V2.8a5.2 5.2 0 1 1-5.2 5.2Z" fill="currentColor" />
          </>
        )}
        {kind === "started-rework" && (
          <>
            <circle cx="8" cy="8" r="5.2" fill="none" stroke="currentColor" strokeWidth="2" />
            <path d="M8 8v5.2a5.2 5.2 0 0 1 0-10.4Z" fill="currentColor" />
          </>
        )}
        {kind === "done" && (
          <>
            <circle cx="8" cy="8" r="6.15" fill="currentColor" />
            <path d="m5.35 8.25 1.75 1.75 3.65-4" fill="none" stroke="var(--status-icon-mark)" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.65" />
          </>
        )}
        {kind === "canceled" && (
          <>
            <circle cx="8" cy="8" r="6.15" fill="currentColor" />
            <path d="m6.05 6.05 3.9 3.9m0-3.9-3.9 3.9" fill="none" stroke="var(--status-icon-mark)" strokeLinecap="round" strokeWidth="1.55" />
          </>
        )}
        {kind === "blocked" && (
          <>
            <circle cx="8" cy="8" r="6.15" fill="currentColor" />
            <path d="M5.1 8h5.8" fill="none" stroke="var(--status-icon-mark)" strokeLinecap="round" strokeWidth="1.7" />
          </>
        )}
      </svg>
    </span>
  );
}
