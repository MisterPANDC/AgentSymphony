import { ExternalLink } from "lucide-react";
import type { IssueDTO } from "../../types/issue";

export function GitLabMeta({ issue }: { issue: IssueDTO }) {
  return (
    <div className="flex items-center gap-2 text-[12px] text-[#4b5563]">
      <span className="mono">#{issue.iid}</span>
      <span className="status-pill">{issue.gitlabState}</span>
      <a className="icon-button h-7 w-7" href={issue.webUrl} target="_blank" rel="noreferrer" title="Open in GitLab">
        <ExternalLink size={14} />
      </a>
    </div>
  );
}
