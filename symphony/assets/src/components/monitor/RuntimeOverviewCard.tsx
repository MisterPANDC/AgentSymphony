import type { MonitorStateDTO } from "../../types/monitor";

export function RuntimeOverviewCard({ state }: { state: MonitorStateDTO }) {
  return (
    <section className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">Runtime Overview</h2>
        <span className="status-pill done">{state.runtime.mode}</span>
      </div>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 p-3 text-sm">
        <dt className="text-[#6b7280]">Uptime</dt>
        <dd>{state.runtime.uptimeSeconds}s</dd>
        <dt className="text-[#6b7280]">Bind</dt>
        <dd className="mono">{state.runtime.bindHost}:{state.runtime.port}</dd>
        <dt className="text-[#6b7280]">Workflow</dt>
        <dd className="truncate mono">{state.runtime.workflowPath}</dd>
        <dt className="text-[#6b7280]">Loaded</dt>
        <dd>{state.runtime.workflowLoaded ? "yes" : "no"}</dd>
      </dl>
    </section>
  );
}
