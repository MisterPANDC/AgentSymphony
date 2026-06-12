import { Play } from "lucide-react";
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

  return (
    <tr className="hover:bg-[#f8fafc]">
      <td className="w-[108px]">
        <button className="mono text-[#334155]" onClick={() => onOpen(issue)}>
          {issue.identifier}
        </button>
      </td>
      <td>
        <button className="block max-w-[760px] truncate text-left font-medium" onClick={() => onOpen(issue)}>
          {issue.title}
        </button>
        <div className="mt-1 flex flex-wrap gap-1">
          {issue.labels.slice(0, 5).map((label) => (
            <span key={label} className="status-pill">
              {label}
            </span>
          ))}
        </div>
      </td>
      <td className="w-[150px]">
        <StatusSelect issueId={issue.id} value={issue.workflowStatus} />
      </td>
      <td className="w-[160px]">
        <GitLabMeta issue={issue} />
      </td>
      <td className="w-[48px] text-right">
        <button className="icon-button" title="Start agent" onClick={() => runMutation.mutate()}>
          <Play size={14} />
        </button>
      </td>
    </tr>
  );
}
