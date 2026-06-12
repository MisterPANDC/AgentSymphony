import { Square } from "lucide-react";
import type { AgentRunDTO } from "../../types/run";

export function ActiveRunsTable({ runs }: { runs: AgentRunDTO[] }) {
  return (
    <section className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">Active Runs</h2>
        <span className="status-pill">{runs.length}</span>
      </div>
      <table className="dense-table">
        <thead>
          <tr>
            <th>Issue</th>
            <th>Status</th>
            <th>Workspace</th>
            <th>Heartbeat</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {runs.length === 0 ? (
            <tr><td colSpan={5}>No active runs</td></tr>
          ) : runs.map((run) => (
            <tr key={run.id}>
              <td><a href={run.issueWebUrl} target="_blank" rel="noreferrer">{run.issueIdentifier}</a></td>
              <td><span className={`status-pill ${run.status}`}>{run.status}</span></td>
              <td className="mono max-w-[280px] truncate">{run.workspacePath ?? "pending"}</td>
              <td>{run.lastHeartbeatAt ?? run.startedAt ?? "n/a"}</td>
              <td><button className="icon-button" title="Cancel run"><Square size={13} /></button></td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
