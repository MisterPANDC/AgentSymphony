import { useMutation, useQueryClient } from "@tanstack/react-query";
import { updateIssueWorkflow } from "../../api/issues";
import { workflowStatuses, type WorkflowStatus } from "../../types/issue";

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
      className={`status-pill status-select ${value}`}
      value={value}
      disabled={mutation.isPending}
      onChange={(event) => mutation.mutate(event.target.value as WorkflowStatus)}
    >
      {workflowStatuses.map((status) => (
        <option key={status} value={status}>
          {status.replace("_", " ")}
        </option>
      ))}
    </select>
  );
}
