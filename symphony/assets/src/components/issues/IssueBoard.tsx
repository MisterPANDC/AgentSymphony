import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { listIssues } from "../../api/issues";
import { workflowStatuses, type IssueDTO } from "../../types/issue";
import { IssueDetailDrawer } from "./IssueDetailDrawer";
import { IssueColumn } from "./IssueColumn";

export function IssueBoard() {
  const [selected, setSelected] = useState<IssueDTO | null>(null);
  const { data } = useQuery({ queryKey: ["issues"], queryFn: () => listIssues() });

  return (
    <>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
        {workflowStatuses.map((status) => (
          <IssueColumn
            key={status}
            status={status}
            issues={(data?.issues ?? []).filter((issue) => issue.workflowStatus === status)}
            onIssueCreated={setSelected}
          />
        ))}
      </div>
      <IssueDetailDrawer issue={selected} onClose={() => setSelected(null)} />
    </>
  );
}
