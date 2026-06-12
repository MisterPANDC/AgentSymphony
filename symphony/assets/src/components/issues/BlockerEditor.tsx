import type { IssueDTO } from "../../types/issue";

export function BlockerEditor({ issue }: { issue: IssueDTO }) {
  return (
    <section>
      <h3 className="mb-2 text-xs font-semibold uppercase text-[#6b7280]">Blockers</h3>
      <div className="space-y-1">
        {issue.blockers.length === 0 ? (
          <div className="text-sm text-[#6b7280]">No blockers</div>
        ) : (
          issue.blockers.map((blocker) => (
            <div key={blocker.issueId} className="flex items-center justify-between rounded-md border border-[#e5e7eb] px-2 py-1 text-sm">
              <span>{blocker.identifier}</span>
              <span className={`status-pill ${blocker.status}`}>{blocker.status}</span>
            </div>
          ))
        )}
      </div>
    </section>
  );
}
