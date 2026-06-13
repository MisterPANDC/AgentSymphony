import type { IssueDTO, IssueRelationRef } from "../../types/issue";

export function BlockerEditor({ issue }: { issue: IssueDTO }) {
  return (
    <section>
      <h3 className="mb-2 text-xs font-semibold uppercase text-[#686b73]">Relations</h3>
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
      <div className="mb-1 text-[11px] font-medium uppercase text-[#686b73]">{title}</div>
      <div className="space-y-1">
        {items.length === 0 ? (
          <div className="text-sm text-[#686b73]">{empty}</div>
        ) : (
          items.map((item) => (
            <div key={`${title}-${item.issueId}`} className="issue-card min-w-0 px-2 py-1 text-sm">
              <div className="flex min-w-0 items-center justify-between gap-2">
                <span className="mono min-w-0 truncate text-[12px] text-[#4f535c]">{item.identifier}</span>
                <span className={`status-pill ${item.status}`}>{item.status}</span>
              </div>
              <div className="mt-1 truncate text-xs text-[#686b73]">{item.title}</div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
