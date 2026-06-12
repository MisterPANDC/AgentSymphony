import { useQuery } from "@tanstack/react-query";
import { getMonitorState } from "../../api/monitor";

export function SyncStatusBadge() {
  const { data } = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });
  const pending = data?.sync.pending;
  const error = data?.sync.issueLastError;

  return (
    <span className={`status-pill ${error ? "blocked" : pending ? "in_progress" : "done"}`} title={error ?? "GitLab sync status"}>
      {error ? "Sync error" : pending ? "Syncing" : "Synced"}
    </span>
  );
}
