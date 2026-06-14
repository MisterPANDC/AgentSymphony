import { Play } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { runIssue } from "../../api/agents";
import type { IssueDTO } from "../../types/issue";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelList } from "./IssueLabelEditor";
import { StatusIcon } from "./StatusIcon";

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
          <StatusIcon status={issue.workflowStatus} size={14} />
          <span className="mono issue-identifier">#{issue.iid}</span>
          <span className="issue-title">{issue.title}</span>
          <IssueLabelList labels={issue.labels} className="issue-row-title-labels" limit={3} />
        </button>
        {(issue.isBlocked || issue.activeRunId) && (
          <div className="issue-row-meta">
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
        )}
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
