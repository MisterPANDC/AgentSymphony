import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronDown, Filter, RefreshCcw } from "lucide-react";
import { listIssues } from "../../api/issues";
import { refreshSync } from "../../api/sync";
import { issueStatusFilters, workflowStatuses, type IssueDTO, type IssueStatusFilter, type WorkflowStatus } from "../../types/issue";
import { IssueDetailDrawer } from "./IssueDetailDrawer";
import { IssueRow } from "./IssueRow";

function formatStatus(status: string) {
  return status.replace("_", " ");
}

export function IssueList() {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<IssueStatusFilter>("all");
  const [selected, setSelected] = useState<IssueDTO | null>(null);
  const { data, isLoading, refetch } = useQuery({ queryKey: ["issues"], queryFn: () => listIssues() });

  const issues = useMemo(() => {
    return (data?.issues ?? []).filter((issue) => {
      const matchesStatus = status === "all" || (status === "blocked" ? issue.isBlocked : issue.workflowStatus === status);
      const haystack = `${issue.identifier} ${issue.title} ${issue.descriptionPreview ?? ""}`.toLowerCase();
      return matchesStatus && haystack.includes(search.toLowerCase());
    });
  }, [data, search, status]);

  const groupedIssues = useMemo(() => {
    const groups = new Map<WorkflowStatus, IssueDTO[]>();
    workflowStatuses.forEach((item) => groups.set(item, []));
    issues.forEach((issue) => groups.get(issue.workflowStatus)?.push(issue));

    if (status !== "all" && status !== "blocked") {
      return [[status, groups.get(status) ?? []]] as Array<[WorkflowStatus, IssueDTO[]]>;
    }

    return workflowStatuses
      .map((item) => [item, groups.get(item) ?? []] as [WorkflowStatus, IssueDTO[]])
      .filter(([, groupIssues]) => groupIssues.length > 0);
  }, [issues, status]);

  return (
    <>
      <section className="panel">
        <div className="panel-header panel-header-stack">
          <div>
            <h1 className="text-sm font-semibold">Issues</h1>
            <p className="text-[12px] text-[#686b73]">{issues.length} visible</p>
          </div>
          <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2 sm:flex-none sm:flex-nowrap">
            <div className="text-button select-shell flex-1 sm:flex-none">
              <Filter size={14} />
              <select className="min-w-0 flex-1 bg-transparent outline-none" value={status} onChange={(event) => setStatus(event.target.value as IssueStatusFilter)}>
                {issueStatusFilters.map((item) => (
                  <option key={item} value={item}>
                    {formatStatus(item)}
                  </option>
                ))}
              </select>
              <ChevronDown size={13} />
            </div>
            <input
              className="field-input flex-[1_1_190px] sm:w-64 sm:flex-none"
              placeholder="Search title or description"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            <button
              className="icon-button"
              title="Manual sync"
              onClick={async () => {
                await refreshSync();
                refetch();
              }}
            >
              <RefreshCcw size={14} />
            </button>
          </div>
        </div>
        <div className="issue-list">
          {isLoading ? (
            <div className="empty-state">Loading issues</div>
          ) : groupedIssues.length === 0 ? (
            <div className="empty-state">No issues match this view</div>
          ) : (
            groupedIssues.map(([groupStatus, groupItems]) => (
              <div key={groupStatus} className="issue-group">
                <div className="issue-group-header">
                  <ChevronDown size={14} />
                  <span className="capitalize">{formatStatus(groupStatus)}</span>
                  <span className="status-pill">{groupItems.length}</span>
                </div>
                <div role="list">
                  {groupItems.map((issue) => (
                    <IssueRow key={issue.id} issue={issue} onOpen={setSelected} />
                  ))}
                </div>
              </div>
            ))
          )}
        </div>
      </section>
      <IssueDetailDrawer issue={selected} onClose={() => setSelected(null)} />
    </>
  );
}
