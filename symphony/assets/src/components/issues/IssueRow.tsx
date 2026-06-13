import { Circle, Play } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { runIssue } from "../../api/agents";
import type { IssueDTO } from "../../types/issue";
import { GitLabMeta } from "./GitLabMeta";
import { StatusSelect } from "./StatusSelect";

export function IssueRow({ issue, onOpen }: { issue: IssueDTO; onOpen: (issue: IssueDTO) => void }) {
  const queryClient = useQueryClient();
  const runMutation = useMutation({
    mutationFn: () => runIssue(issue.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      queryClient.invalidateQueries({ queryKey: ["runs"] });
    }
  });
  const runDisabled = issue.isBlocked || runMutation.isPending;

  return (
    <article className="issue-row" role="listitem">
      <div className="issue-row-primary">
        <button className="issue-row-title" onClick={() => onOpen(issue)}>
          <Circle size={12} className="issue-state-dot" />
          <span className="mono issue-identifier">{issue.identifier}</span>
          <span className="issue-title">{issue.title}</span>
        </button>
        {(issue.isBlocked || issue.activeRunId || issue.labels.length > 0) && (
          <div className="issue-row-meta">
            {issue.isBlocked && <span className="status-pill blocked">blocked</span>}
            {issue.activeRunId && <span className="status-pill in_progress">active run</span>}
            {issue.labels.slice(0, 4).map((label) => (
              <span key={label} className="status-pill">
                {label}
              </span>
            ))}
          </div>
        )}
      </div>
      <div className="issue-row-secondary">
        <StatusSelect issueId={issue.id} value={issue.workflowStatus} />
      </div>
      <div className="issue-row-secondary">
        <GitLabMeta issue={issue} />
      </div>
      <div className="issue-row-secondary">
        <button className="icon-button" title={issue.isBlocked ? "Issue is blocked" : "Start agent"} disabled={runDisabled} onClick={() => runMutation.mutate()}>
          <Play size={14} />
        </button>
      </div>
    </article>
  );
}
