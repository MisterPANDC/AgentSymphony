import type { IssueDTO, WorkflowStatus } from "../../types/issue";

export function IssueColumn({ status, issues }: { status: WorkflowStatus; issues: IssueDTO[] }) {
  return (
    <section className="panel min-h-[320px]">
      <div className="panel-header">
        <h2 className="text-xs font-semibold uppercase text-[#4b5563]">{status.replace("_", " ")}</h2>
        <span className="status-pill">{issues.length}</span>
      </div>
      <div className="space-y-2 p-2">
        {issues.map((issue) => (
          <article key={issue.id} className="rounded-md border border-[#e5e7eb] bg-[#ffffff] p-2">
            <div className="mono mb-1 text-[11px] text-[#64748b]">{issue.identifier}</div>
            <h3 className="line-clamp-2 text-sm font-medium">{issue.title}</h3>
          </article>
        ))}
      </div>
    </section>
  );
}
