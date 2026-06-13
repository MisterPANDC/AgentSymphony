import type { IssueDTO, IssueRelationRef } from "../../types/issue";

export function BlockerEditor({ issue }: { issue: IssueDTO }) {
  return (
    <section>
      <h3 className="mb-2 text-xs font-semibold uppercase text-[#6b7280]">Relations</h3>
      <div className="grid gap-3 sm:grid-cols-3">
        <RelationGroup title="Related" empty="No related issues" items={issue.relations?.related ?? []} />
        <RelationGroup title="Blocks" empty="No blocked issues" items={issue.relations?.blocks ?? []} />
        <RelationGroup title="Blocked by" empty="No blockers" items={issue.relations?.blockedBy ?? issue.blockers ?? []} />
      </div>
    </section>
  );
}

function RelationGroup({ title, empty, items }: { title: string; empty: string; items: IssueRelationRef[] }) {
  return (
    <div className="min-w-0">
      <div className="mb-1 text-[11px] font-medium uppercase text-[#64748b]">{title}</div>
      <div className="space-y-1">
        {items.length === 0 ? (
          <div className="text-sm text-[#6b7280]">{empty}</div>
        ) : (
          items.map((item) => (
            <div key={`${title}-${item.issueId}`} className="min-w-0 rounded-md border border-[#e5e7eb] px-2 py-1 text-sm">
              <div className="flex min-w-0 items-center justify-between gap-2">
                <span className="mono min-w-0 truncate text-[12px] text-[#334155]">{item.identifier}</span>
                <span className={`status-pill ${item.status}`}>{item.status}</span>
              </div>
              <div className="mt-1 truncate text-xs text-[#64748b]">{item.title}</div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
