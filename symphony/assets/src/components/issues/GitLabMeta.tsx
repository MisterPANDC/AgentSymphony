import { ExternalLink } from "lucide-react";
import type { IssueDTO } from "../../types/issue";

export function GitLabMeta({ issue }: { issue: IssueDTO }) {
  return (
    <div className="gitlab-meta text-[12px] text-[#4f535c]">
      <span className="mono text-[#686b73]">#{issue.iid}</span>
      <span className="status-pill">{issue.gitlabState}</span>
      <a className="icon-button" href={issue.webUrl} target="_blank" rel="noreferrer" title="Open in GitLab">
        <ExternalLink size={13} />
      </a>
    </div>
  );
}
