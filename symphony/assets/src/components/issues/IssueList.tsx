import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Filter, RefreshCcw } from "lucide-react";
import { listIssues } from "../../api/issues";
import { refreshSync } from "../../api/sync";
import type { IssueDTO, WorkflowStatus } from "../../types/issue";
import { IssueDetailDrawer } from "./IssueDetailDrawer";
import { IssueRow } from "./IssueRow";

export function IssueList() {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<WorkflowStatus | "all">("all");
  const [selected, setSelected] = useState<IssueDTO | null>(null);
  const { data, isLoading, refetch } = useQuery({ queryKey: ["issues"], queryFn: () => listIssues() });

  const issues = useMemo(() => {
    return (data?.issues ?? []).filter((issue) => {
      const matchesStatus = status === "all" || issue.workflowStatus === status;
      const haystack = `${issue.identifier} ${issue.title} ${issue.descriptionPreview ?? ""}`.toLowerCase();
      return matchesStatus && haystack.includes(search.toLowerCase());
    });
  }, [data, search, status]);

  return (
    <>
      <section className="panel">
        <div className="panel-header">
          <div>
            <h1 className="text-sm font-semibold">Issues</h1>
            <p className="text-[12px] text-[#6b7280]">{issues.length} visible</p>
          </div>
          <div className="flex items-center gap-2">
            <div className="text-button">
              <Filter size={14} />
              <select className="bg-transparent outline-none" value={status} onChange={(event) => setStatus(event.target.value as WorkflowStatus | "all")}>
                {["all", "triage", "todo", "in_progress", "blocked", "review", "done", "canceled"].map((item) => (
                  <option key={item} value={item}>
                    {item.replace("_", " ")}
                  </option>
                ))}
              </select>
            </div>
            <input
              className="h-8 w-64 rounded-md border border-[#d7dce3] bg-[#ffffff] px-2 text-sm outline-none"
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
          <table className="dense-table">
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
