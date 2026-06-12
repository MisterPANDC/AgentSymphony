import { CheckCircle2 } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { resolveBlock } from "../../api/monitor";
import type { RuntimeBlockDTO } from "../../types/monitor";

export function BlockedQueue({ blocks }: { blocks: RuntimeBlockDTO[] }) {
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: resolveBlock,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["monitor-state"] })
  });

  return (
    <section className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">Blocked / Needs Operator Input</h2>
        <span className={`status-pill ${blocks.length ? "blocked" : "done"}`}>{blocks.length}</span>
      </div>
      <table className="dense-table">
        <thead>
          <tr><th>Issue</th><th>Type</th><th>Message</th><th>Created</th><th /></tr>
        </thead>
        <tbody>
          {blocks.length === 0 ? (
            <tr><td colSpan={5}>No open blocks</td></tr>
          ) : blocks.map((block) => (
            <tr key={block.id}>
              <td><a href={block.issueWebUrl} target="_blank" rel="noreferrer">{block.issueIdentifier}</a></td>
              <td><span className="status-pill blocked">{block.blockType}</span></td>
              <td className="max-w-[420px] truncate">{block.message}</td>
              <td>{block.insertedAt}</td>
              <td><button className="icon-button" title="Resolve block" onClick={() => mutation.mutate(block.id)}><CheckCircle2 size={14} /></button></td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
