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
      <div className="metric-grid">
        {items.map(([label, value]) => (
          <div key={label} className="metric-cell">
            <div className="metric-label">{label}</div>
            <div className="metric-value">{value}</div>
          </div>
        ))}
      </div>
    </section>
  );
}
