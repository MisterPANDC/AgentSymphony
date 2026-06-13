import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Filter, RefreshCcw } from "lucide-react";
import { listIssues } from "../../api/issues";
import { refreshSync } from "../../api/sync";
import { issueStatusFilters, type IssueDTO, type IssueStatusFilter } from "../../types/issue";
import { IssueDetailDrawer } from "./IssueDetailDrawer";
import { IssueRow } from "./IssueRow";

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

  return (
    <>
      <section className="panel">
        <div className="panel-header panel-header-stack">
          <div>
            <h1 className="text-sm font-semibold">Issues</h1>
            <p className="text-[12px] text-[#6b7280]">{issues.length} visible</p>
          </div>
          <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2 sm:flex-none sm:flex-nowrap">
            <div className="text-button flex-1 sm:flex-none">
              <Filter size={14} />
              <select className="min-w-0 flex-1 bg-transparent outline-none" value={status} onChange={(event) => setStatus(event.target.value as IssueStatusFilter)}>
                {issueStatusFilters.map((item) => (
                  <option key={item} value={item}>
                    {item.replace("_", " ")}
                  </option>
                ))}
              </select>
            </div>
            <input
              className="h-8 min-w-0 flex-[1_1_180px] rounded-md border border-[#d7dce3] bg-[#ffffff] px-2 text-sm outline-none sm:w-64 sm:flex-none"
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
        <div className="overflow-auto">
          <table className="dense-table issue-table">
            <thead>
              <tr>
                <th>Issue</th>
                <th>Title</th>
                <th>Status</th>
                <th>GitLab</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                <tr>
                  <td colSpan={5}>Loading issues</td>
                </tr>
              ) : (
                issues.map((issue) => <IssueRow key={issue.id} issue={issue} onOpen={setSelected} />)
              )}
            </tbody>
          </table>
        </div>
      </section>
      <IssueDetailDrawer issue={selected} onClose={() => setSelected(null)} />
    </>
  );
}
