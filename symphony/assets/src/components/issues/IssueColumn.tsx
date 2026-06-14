import { Plus } from "lucide-react";
import type { IssueDTO, WorkflowStatus } from "../../types/issue";
import { CreateIssueDialog } from "./CreateIssueDialog";
import { formatStatusLabel, StatusIcon } from "./StatusIcon";

export function IssueColumn({
  status,
  issues,
  onIssueCreated
}: {
  status: WorkflowStatus;
  issues: IssueDTO[];
  onIssueCreated?: (issue: IssueDTO) => void;
}) {
  return (
    <section className="panel board-column min-h-[320px]">
      <div className="panel-header">
        <h2 className="flex items-center gap-2 text-xs font-semibold capitalize text-[#4f535c]">
          <StatusIcon status={status} size={14} />
          {formatStatusLabel(status)}
        </h2>
        <span className="board-count">{issues.length}</span>
      </div>
      <div className="board-column-body">
        {issues.map((issue) => (
          <article key={issue.id} className="issue-card">
            <div className="mb-1 flex min-w-0 items-center gap-1.5">
              <span className="mono min-w-0 truncate text-[11px] text-[#686b73]">{issue.identifier}</span>
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
