import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Check, ChevronDown, Filter, Plus, RefreshCcw } from "lucide-react";
import { listIssues } from "../../api/issues";
import { refreshSync } from "../../api/sync";
import { canUserCreateIssueInStatus, issueStatusFilters, workflowStatuses, type IssueDTO, type IssueStatusFilter, type WorkflowStatus } from "../../types/issue";
import { CreateIssueDialog } from "./CreateIssueDialog";
import { IssueDetailDrawer } from "./IssueDetailDrawer";
import { IssueRow } from "./IssueRow";
import { formatStatusLabel, StatusIcon } from "./StatusIcon";
import { useIssueDetailSelection } from "./useIssueDetailSelection";

export function IssueList() {
  const filterRef = useRef<HTMLDivElement>(null);
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<IssueStatusFilter>("all");
  const [filterOpen, setFilterOpen] = useState(false);
  const [collapsedGroups, setCollapsedGroups] = useState<Set<WorkflowStatus>>(() => new Set());
  const { data, isLoading, refetch } = useQuery({ queryKey: ["issues"], queryFn: () => listIssues() });
  const allIssues = data?.issues ?? [];
  const { selectedIssue, openIssue, closeIssue } = useIssueDetailSelection(allIssues);
  const createDefaultStatus: WorkflowStatus = status !== "all" && status !== "blocked" && canUserCreateIssueInStatus(status) ? status : "backlog";

  useEffect(() => {
    if (!filterOpen) {
      return;
    }

    function onPointerDown(event: PointerEvent) {
      if (!filterRef.current?.contains(event.target as Node)) {
        setFilterOpen(false);
      }
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setFilterOpen(false);
      }
    }

    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [filterOpen]);

  const issues = useMemo(() => {
    return allIssues.filter((issue) => {
      const matchesStatus = status === "all" || (status === "blocked" ? issue.isBlocked : issue.workflowStatus === status);
      const haystack = `${issue.identifier} ${issue.title} ${issue.descriptionPreview ?? ""}`.toLowerCase();
      return matchesStatus && haystack.includes(search.toLowerCase());
    });
  }, [allIssues, search, status]);

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

  function toggleGroup(groupStatus: WorkflowStatus) {
    setCollapsedGroups((current) => {
      const next = new Set(current);
      if (next.has(groupStatus)) {
        next.delete(groupStatus);
      } else {
        next.add(groupStatus);
      }
      return next;
    });
  }

  return (
    <>
      <section className="panel issue-list-panel">
        <div className="panel-header panel-header-stack">
          <div>
            <h1 className="text-sm font-semibold">Issues</h1>
            <p className="text-[12px] text-[#686b73]">{issues.length} visible</p>
          </div>
          <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2 sm:flex-none sm:flex-nowrap">
            <div className="issue-filter flex-1 sm:flex-none" ref={filterRef}>
              <button
                className={`text-button issue-filter-trigger${filterOpen ? " is-open" : ""}`}
                type="button"
                aria-haspopup="menu"
                aria-expanded={filterOpen}
                onClick={() => setFilterOpen((value) => !value)}
              >
                <Filter size={14} />
                <StatusIcon status={status} size={14} />
                <span className="issue-filter-trigger-label">{formatStatusLabel(status)}</span>
                <ChevronDown size={13} />
              </button>
              {filterOpen && (
                <div className="issue-filter-menu" role="menu">
                  <div className="issue-filter-menu-header">Status</div>
                  <div className="issue-filter-list">
                    {issueStatusFilters.map((item) => {
                      const selectedFilter = item === status;

                      return (
                        <button
                          key={item}
                          className={`issue-filter-row${selectedFilter ? " is-selected" : ""}`}
                          type="button"
                          role="menuitemradio"
                          aria-checked={selectedFilter}
                          onClick={() => {
                            setStatus(item);
                            setFilterOpen(false);
                          }}
                        >
                          <span className="issue-filter-row-label">
                            <StatusIcon status={item} size={14} />
                            <span>{formatStatusLabel(item)}</span>
                          </span>
                          {selectedFilter && <Check size={14} />}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
            <input
              className="field-input flex-[1_1_190px] sm:w-64 sm:flex-none"
              placeholder="Search title or description"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            <CreateIssueDialog
              defaultStatus={createDefaultStatus}
              onCreated={openIssue}
              trigger={
                <button className="text-button" type="button">
                  <Plus size={14} />
                  New issue
                </button>
              }
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
            groupedIssues.map(([groupStatus, groupItems]) => {
              const collapsed = collapsedGroups.has(groupStatus);
              const groupId = `issue-group-${groupStatus}`;

              return (
                <div key={groupStatus} className={`issue-group${collapsed ? " is-collapsed" : ""}`}>
                  <button
                    className="issue-group-header"
                    type="button"
                    aria-controls={groupId}
                    aria-expanded={!collapsed}
                    onClick={() => toggleGroup(groupStatus)}
                  >
                    <ChevronDown className="issue-group-chevron" size={14} />
                    <StatusIcon status={groupStatus} size={14} />
                    <span>{formatStatusLabel(groupStatus)}</span>
                    <span className="issue-group-count">{groupItems.length}</span>
                  </button>
                  {!collapsed && (
                    <div id={groupId} role="list">
                      {groupItems.map((issue) => (
                        <IssueRow key={issue.id} issue={issue} onOpen={openIssue} />
                      ))}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </section>
      <IssueDetailDrawer issue={selectedIssue} onClose={closeIssue} />
    </>
  );
}
