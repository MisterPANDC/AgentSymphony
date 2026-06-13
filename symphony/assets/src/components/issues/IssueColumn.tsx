import { Circle } from "lucide-react";
import type { IssueDTO, WorkflowStatus } from "../../types/issue";

export function IssueColumn({ status, issues }: { status: WorkflowStatus; issues: IssueDTO[] }) {
  return (
    <section className="panel min-h-[320px]">
      <div className="panel-header">
        <h2 className="flex items-center gap-2 text-xs font-semibold capitalize text-[#4f535c]">
          <Circle size={11} className="text-[#a8acb5]" />
          {status.replace("_", " ")}
        </h2>
        <span className="status-pill">{issues.length}</span>
      </div>
      <div className="space-y-2 bg-[#fbfbfc] p-2">
        {issues.map((issue) => (
          <article key={issue.id} className="issue-card">
            <div className="mb-1 flex min-w-0 items-center gap-1.5">
              <span className="mono min-w-0 truncate text-[11px] text-[#686b73]">{issue.identifier}</span>
              {issue.isBlocked && <span className="status-pill blocked">blocked</span>}
            </div>
            <h3 className="line-clamp-2 text-sm font-medium leading-5 text-[#1d1d1f]">{issue.title}</h3>
          </article>
        ))}
        {issues.length === 0 && <div className="empty-state py-8">No issues</div>}
      </div>
    </section>
  );
}
