import { RefreshCcw } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { refreshMonitor } from "../../api/monitor";
import type { MonitorStateDTO } from "../../types/monitor";

export function SyncHealthCard({ state }: { state: MonitorStateDTO }) {
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: refreshMonitor,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["monitor-state"] })
  });

  return (
    <section className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">GitLab Sync Health</h2>
        <button className="icon-button" title="Manual refresh" onClick={() => mutation.mutate()}><RefreshCcw size={14} /></button>
      </div>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 p-3 text-sm">
        <dt className="text-[#6b7280]">API root</dt><dd className="mono truncate">{state.gitlab.apiRoot ?? "missing"}</dd>
        <dt className="text-[#6b7280]">Project</dt><dd>{state.gitlab.projectName ?? state.gitlab.projectRef ?? "unvalidated"}</dd>
        <dt className="text-[#6b7280]">Last success</dt><dd>{state.sync.issueLastSuccessAt ?? "n/a"}</dd>
        <dt className="text-[#6b7280]">Last attempt</dt><dd>{state.sync.issueLastAttemptAt ?? "n/a"}</dd>
        <dt className="text-[#6b7280]">Next run</dt><dd>{state.sync.nextRunAt ?? "n/a"}</dd>
        <dt className="text-[#6b7280]">Read-only</dt><dd>{state.gitlab.readOnly ? "yes" : "no"}</dd>
        {state.sync.issueLastError && <><dt className="text-[#6b7280]">Error</dt><dd className="text-[#b42318]">{state.sync.issueLastError}</dd></>}
      </dl>
    </section>
  );
}
