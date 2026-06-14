import { ExternalLink } from "lucide-react";
import type { IssueDTO } from "../../types/issue";
import { formatGitLabState } from "./issueDisplay";

export function GitLabMeta({ issue, showLink = true }: { issue: IssueDTO; showLink?: boolean }) {
  const stateLabel = formatGitLabState(issue.gitlabState);

  return (
    <div className="gitlab-meta text-[12px] text-[#4f535c]">
      <span className={`issue-state-badge issue-state-badge--${stateLabel}`} aria-label={`GitLab issue is ${stateLabel}`}>
        <GitLabStateIcon state={stateLabel} />
        {stateLabel}
      </span>
      {showLink && (
        <a className="icon-button" href={issue.webUrl} target="_blank" rel="noreferrer" title="Open in GitLab">
          <ExternalLink size={13} />
        </a>
      )}
    </div>
  );
}

function GitLabStateIcon({ state }: { state: "open" | "closed" }) {
  return (
    <span className={`gitlab-state-icon gitlab-state-icon--${state}`} aria-hidden="true">
      <svg viewBox="0 0 16 16" focusable="false">
        <circle cx="8" cy="8" r="5.25" fill="none" stroke="currentColor" strokeWidth="1.8" />
        {state === "open" ? (
          <circle cx="8" cy="8" r="1.65" fill="currentColor" />
        ) : (
          <path d="m5.35 8.2 1.75 1.7 3.55-3.85" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.7" />
        )}
      </svg>
    </span>
  );
}
