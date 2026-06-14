import { useQuery } from "@tanstack/react-query";
import { getMonitorState } from "../../api/monitor";
import { StatusIcon } from "../issues/StatusIcon";

export function SyncStatusBadge() {
  const { data } = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });
  const pending = data?.sync.pending;
  const error = data?.sync.issueLastError;
  const status = error ? "blocked" : pending ? "in_progress" : "done";

  return (
    <span className={`status-pill ${status}`} title={error ?? "GitLab sync status"}>
      <StatusIcon status={status} size={12} />
      {error ? "Sync error" : pending ? "Syncing" : "Synced"}
    </span>
  );
}
