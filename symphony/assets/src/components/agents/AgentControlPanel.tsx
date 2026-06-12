import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, Play } from "lucide-react";
import { dispatchAgents } from "../../api/agents";
import { listRuns } from "../../api/runs";
import { getMonitorState } from "../../api/monitor";
import { RunTimeline } from "./RunTimeline";

export function AgentControlPanel() {
  const queryClient = useQueryClient();
  const monitor = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });
  const runs = useQuery({ queryKey: ["runs"], queryFn: listRuns });
  const dispatch = useMutation({
    mutationFn: dispatchAgents,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["monitor-state"] })
  });

  return (
    <div className="space-y-4">
      <section className="panel">
        <div className="panel-header">
          <h1 className="flex items-center gap-2 text-sm font-semibold"><Bot size={15} /> Agent Control</h1>
          <button className="text-button" onClick={() => dispatch.mutate()}><Play size={14} /> Dispatch</button>
        </div>
        <div className="grid grid-cols-4 gap-px bg-[#e5e7eb]">
          {[
            ["Max", monitor.data?.agents.maxConcurrent ?? 0],
            ["Queued", monitor.data?.agents.queued ?? 0],
            ["Running", monitor.data?.agents.running ?? 0],
            ["Blocked", monitor.data?.agents.blocked ?? 0]
          ].map(([label, value]) => (
            <div key={label} className="bg-[#ffffff] p-3">
              <div className="text-[11px] text-[#6b7280]">{label}</div>
              <div className="text-xl font-semibold">{value}</div>
            </div>
          ))}
        </div>
      </section>
      <RunTimeline runs={runs.data?.runs ?? []} />
    </div>
  );
}
