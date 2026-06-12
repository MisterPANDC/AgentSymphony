import { useQuery } from "@tanstack/react-query";
import { listIssues } from "../../api/issues";
import type { WorkflowStatus } from "../../types/issue";
import { IssueColumn } from "./IssueColumn";

const columns: WorkflowStatus[] = ["triage", "todo", "in_progress", "blocked", "review", "done", "canceled"];

export function IssueBoard() {
  const { data } = useQuery({ queryKey: ["issues"], queryFn: () => listIssues() });

  return (
    <div className="grid gap-3 lg:grid-cols-4 xl:grid-cols-7">
      {columns.map((status) => (
        <IssueColumn key={status} status={status} issues={(data?.issues ?? []).filter((issue) => issue.workflowStatus === status)} />
      ))}
    </div>
  );
}
