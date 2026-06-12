import { useQuery } from "@tanstack/react-query";
import { getMonitorState } from "../../api/monitor";
import { ActiveRunsTable } from "./ActiveRunsTable";
import { AgentCapacityCard } from "./AgentCapacityCard";
import { BlockedQueue } from "./BlockedQueue";
import { OperationalApiCard } from "./OperationalApiCard";
import { RuntimeOverviewCard } from "./RuntimeOverviewCard";
import { SyncHealthCard } from "./SyncHealthCard";
import { WorkspaceLogsCard } from "./WorkspaceLogsCard";

export function RunMonitorPage() {
  const { data } = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });

  if (!data) return <div className="panel p-4">Loading Run Monitor</div>;

  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-3">
        <RuntimeOverviewCard state={data} />
        <AgentCapacityCard state={data} />
        <SyncHealthCard state={data} />
      </div>
      <ActiveRunsTable runs={data.activeRuns} />
      <BlockedQueue blocks={data.blocked} />
      <div className="grid gap-4 xl:grid-cols-2">
        <WorkspaceLogsCard state={data} />
        <OperationalApiCard state={data} />
      </div>
    </div>
  );
}
