import type { AgentRunDTO } from "../../types/run";

export function RunTimeline({ runs }: { runs: AgentRunDTO[] }) {
  return (
    <section className="panel">
      <div className="panel-header"><h2 className="text-sm font-semibold">Run History</h2></div>
      <table className="dense-table">
        <thead><tr><th>Run</th><th>Issue</th><th>Status</th><th>Started</th><th>Finished</th></tr></thead>
        <tbody>
          {runs.map((run) => (
            <tr key={run.id}>
              <td className="mono">#{run.runNumber}</td>
              <td>{run.issueIdentifier}</td>
              <td><span className={`status-pill ${run.status}`}>{run.status}</span></td>
              <td>{run.startedAt ?? "n/a"}</td>
              <td>{run.finishedAt ?? "n/a"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
