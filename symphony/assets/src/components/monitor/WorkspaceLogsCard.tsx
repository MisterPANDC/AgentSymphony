import type { MonitorStateDTO } from "../../types/monitor";

export function WorkspaceLogsCard({ state }: { state: MonitorStateDTO }) {
  const workspaces = state.activeRuns.map((run) => run.workspacePath).filter(Boolean);

  return (
    <section className="panel">
      <div className="panel-header"><h2 className="text-sm font-semibold">Workspace and Logs</h2></div>
      <div className="p-3 text-sm">
        <div className="mb-2 text-[#6b7280]">Active workspace paths</div>
        <div className="space-y-1">
          {workspaces.length === 0 ? <div>No active workspaces</div> : workspaces.map((path) => <div key={path} className="mono truncate">{path}</div>)}
        </div>
      </div>
    </section>
  );
}
