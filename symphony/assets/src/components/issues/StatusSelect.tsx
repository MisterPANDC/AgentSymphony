import { useMutation, useQueryClient } from "@tanstack/react-query";
import { updateIssueWorkflow } from "../../api/issues";
import type { WorkflowStatus } from "../../types/issue";

const statuses: WorkflowStatus[] = ["triage", "todo", "in_progress", "blocked", "review", "done", "canceled"];

export function StatusSelect({ issueId, value }: { issueId: string; value: WorkflowStatus }) {
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: (status: WorkflowStatus) => updateIssueWorkflow(issueId, status, "changed from dashboard"),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
    }
  });

  return (
    <select
      className={`status-pill ${value} cursor-pointer`}
      value={value}
      onChange={(event) => mutation.mutate(event.target.value as WorkflowStatus)}
    >
      {statuses.map((status) => (
        <option key={status} value={status}>
          {status.replace("_", " ")}
        </option>
      ))}
    </select>
  );
}
