import type { IssueDTO } from "../../types/issue";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelList } from "./IssueLabelEditor";
import { StatusIcon } from "./StatusIcon";

export function IssueRow({ issue, onOpen }: { issue: IssueDTO; onOpen: (issue: IssueDTO) => void }) {
  return (
    <article className="issue-row" role="listitem">
      <div className="issue-row-primary">
        <button className="issue-row-title" onClick={() => onOpen(issue)}>
          <StatusIcon status={issue.workflowStatus} size={14} />
          <span className="mono issue-identifier">#{issue.iid}</span>
          <span className="issue-title">{issue.title}</span>
          <IssueLabelList labels={issue.labels} className="issue-row-title-labels" limit={3} />
        </button>
        {issue.isBlocked && (
          <div className="issue-row-meta">
            <span className="status-pill blocked">
              <StatusIcon status="blocked" size={12} />
              blocked
            </span>
          </div>
        )}
      </div>
      <div className="issue-row-secondary">
        <GitLabMeta issue={issue} />
      </div>
    </article>
  );
}
