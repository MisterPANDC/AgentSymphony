import type { IssueDTO } from "../../types/issue";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelList } from "./IssueLabelEditor";
import { MergeRequestIcon } from "./MergeRequestIcon";
import { formatStatusLabel, StatusIcon } from "./StatusIcon";

export function IssueRow({ issue, onOpen }: { issue: IssueDTO; onOpen: (issue: IssueDTO) => void }) {
  const previewDescription = issue.descriptionPreview || issue.description || "No description provided.";

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
        <MergeRequestListIcon count={issue.mergeRequestCount} />
        <GitLabMeta issue={issue} />
      </div>
      <div className="issue-row-preview" aria-hidden="true">
        <div className="issue-row-preview-header">
          <span className="issue-row-preview-id">#{issue.iid}</span>
          <span className="issue-row-preview-status">
            <StatusIcon status={issue.workflowStatus} size={13} />
            {formatStatusLabel(issue.workflowStatus)}
          </span>
        </div>
        <div className="issue-row-preview-title">{issue.title}</div>
        <p>{previewDescription}</p>
        <div className="issue-row-preview-footer">
          <IssueLabelList labels={issue.labels} limit={3} emptyLabel="No labels" />
          <span className="issue-row-preview-flags">
            <MergeRequestListIcon count={issue.mergeRequestCount} />
            {issue.isBlocked && "Blocked"}
          </span>
        </div>
      </div>
    </article>
  );
}

function MergeRequestListIcon({ count }: { count?: number | null }) {
  if (!count || count < 1) return null;

  return (
    <span className="issue-row-merge-request-icon" title={`${count} linked merge ${count === 1 ? "request" : "requests"}`} aria-label={`${count} linked merge ${count === 1 ? "request" : "requests"}`}>
      <MergeRequestIcon size={18} />
    </span>
  );
}
