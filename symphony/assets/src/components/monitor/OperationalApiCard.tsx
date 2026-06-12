import type { MonitorStateDTO } from "../../types/monitor";

export function OperationalApiCard({ state }: { state: MonitorStateDTO }) {
  const base = `http://${state.runtime.bindHost}:${state.runtime.port}`;
  const commands = [`curl ${base}/api/v1/state`, `curl -X POST ${base}/api/v1/refresh`, `curl ${base}/api/monitor/state`];

  return (
    <section className="panel">
      <div className="panel-header"><h2 className="text-sm font-semibold">Operational Debug API</h2></div>
      <div className="space-y-2 p-3">
        {commands.map((command) => (
          <code key={command} className="block rounded-md border border-[#e5e7eb] bg-[#f8fafc] p-2 text-xs">{command}</code>
        ))}
        <pre className="max-h-48 overflow-auto rounded-md border border-[#e5e7eb] bg-[#f8fafc] p-2 text-xs">
          {JSON.stringify({ runtime: state.runtime, sync: state.sync, agents: state.agents }, null, 2)}
        </pre>
      </div>
    </section>
  );
}
