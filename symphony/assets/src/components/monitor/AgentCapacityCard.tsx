import type { MonitorStateDTO } from "../../types/monitor";

export function AgentCapacityCard({ state }: { state: MonitorStateDTO }) {
  const items = [
    ["Max", state.agents.maxConcurrent],
    ["Queued", state.agents.queued],
    ["Running", state.agents.running],
    ["Blocked", state.agents.blocked],
    ["Succeeded", state.agents.succeededRecent],
    ["Failed", state.agents.failedRecent]
  ];

  return (
    <section className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">Agent Capacity</h2>
      </div>
      <div className="grid grid-cols-3 gap-px bg-[#e5e7eb]">
        {items.map(([label, value]) => (
          <div key={label} className="bg-[#ffffff] p-3">
            <div className="text-[11px] text-[#6b7280]">{label}</div>
            <div className="text-xl font-semibold">{value}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
