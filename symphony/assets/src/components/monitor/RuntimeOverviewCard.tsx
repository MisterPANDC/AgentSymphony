import type { MonitorStateDTO } from "../../types/monitor";

export function RuntimeOverviewCard({ state }: { state: MonitorStateDTO }) {
  return (
    <section className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">Runtime Overview</h2>
        <span className="status-pill done max-w-full truncate">{state.runtime.mode}</span>
      </div>
      <dl className="grid grid-cols-[96px_minmax(0,1fr)] gap-x-4 gap-y-2 p-3 text-sm">
        <dt className="text-[#686b73]">Uptime</dt>
        <dd>{state.runtime.uptimeSeconds}s</dd>
        <dt className="text-[#686b73]">Bind</dt>
        <dd className="mono min-w-0 break-words">{state.runtime.bindHost}:{state.runtime.port}</dd>
        <dt className="text-[#686b73]">Workflow</dt>
        <dd className="mono min-w-0 truncate">{state.runtime.workflowPath}</dd>
        <dt className="text-[#686b73]">Loaded</dt>
        <dd>{state.runtime.workflowLoaded ? "yes" : "no"}</dd>
      </dl>
    </section>
  );
}
