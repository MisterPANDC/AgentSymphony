import { useState } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { KeyRound, RefreshCcw, Save, TestTube2 } from "lucide-react";
import { getGitLabSettings, getWorkflowSettings, testGitLabSettings, updateProjectAccessToken } from "../api/settings";
import { refreshSync } from "../api/sync";
import { listRuns } from "../api/runs";
import { getMonitorState } from "../api/monitor";
import { AuthGate } from "../components/auth/AuthGate";
import { AgentControlPanel } from "../components/agents/AgentControlPanel";
import { RunTimeline } from "../components/agents/RunTimeline";
import { AppShell } from "../components/layout/AppShell";
import { RunMonitorPage } from "../components/monitor/RunMonitorPage";
import { IssueBoard } from "../components/issues/IssueBoard";
import { IssueList } from "../components/issues/IssueList";

export function AppRoutes() {
  return (
    <AuthGate>
      <Routes>
        <Route element={<AppShell />}>
          <Route index element={<DashboardOverview />} />
          <Route path="issues" element={<IssueList />} />
          <Route path="issues/:iid" element={<IssueList />} />
          <Route path="board" element={<IssueBoard />} />
          <Route path="agents" element={<AgentControlPanel />} />
          <Route path="runs" element={<RunsPage />} />
          <Route path="monitor" element={<RunMonitorPage />} />
          <Route path="monitor/runs" element={<RunsPage />} />
          <Route path="monitor/runs/:runId" element={<RunsPage />} />
          <Route path="monitor/blocks" element={<Navigate to="/monitor" replace />} />
          <Route path="monitor/sync" element={<RunMonitorPage />} />
          <Route path="settings/gitlab" element={<GitLabSettingsPage />} />
          <Route path="settings/workflow" element={<WorkflowSettingsPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </AuthGate>
  );
}

function DashboardOverview() {
  const monitor = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] items-start gap-4 xl:grid-cols-[minmax(0,1fr)_420px]">
      <div className="min-w-0">
        <IssueList />
      </div>
      <section className="min-w-0 space-y-4">
        <div className="panel">
          <div className="panel-header">
            <div className="text-xs font-semibold uppercase text-[#686b73]">Runtime</div>
          </div>
          <div className="metric-grid">
            <Metric label="Running" value={monitor.data?.agents.running ?? 0} />
            <Metric label="Blocked" value={monitor.data?.agents.blocked ?? 0} />
            <Metric label="Queued" value={monitor.data?.agents.queued ?? 0} />
          </div>
        </div>
        <RunMonitorPage compact />
      </section>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className="metric-cell">
      <div className="metric-value">{value}</div>
      <div className="metric-label">{label}</div>
    </div>
  );
}

function RunsPage() {
  const { data } = useQuery({ queryKey: ["runs"], queryFn: listRuns });
  return <RunTimeline runs={data?.runs ?? []} />;
}

function GitLabSettingsPage() {
  const queryClient = useQueryClient();
  const [projectAccessToken, setProjectAccessToken] = useState("");
  const { data } = useQuery({ queryKey: ["settings", "gitlab"], queryFn: getGitLabSettings });
  const testMutation = useMutation({ mutationFn: testGitLabSettings });
  const tokenMutation = useMutation({
    mutationFn: updateProjectAccessToken,
    onSuccess: () => {
      setProjectAccessToken("");
      queryClient.invalidateQueries({ queryKey: ["settings", "gitlab"] });
      queryClient.invalidateQueries({ queryKey: ["auth-session"] });
    }
  });
  const syncMutation = useMutation({
    mutationFn: refreshSync,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "gitlab"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
    }
  });
  const tokenStatus = data?.project?.project_access_token_status ?? "missing";
  const tokenMissing = tokenStatus === "missing";
  const tokenSummary = tokenMissing
    ? "Required before background sync and Agent GitLab writes can run for this repository."
    : data?.project?.project_access_token_set_at
      ? `Configured at ${new Date(data.project.project_access_token_set_at).toLocaleString()}. Paste a new token only when rotating credentials.`
      : "Configured for background sync and Agent GitLab writes. Paste a new token only when rotating credentials.";

  return (
    <section className="space-y-4">
      <div className="panel">
        <div className="panel-header">
          <h1 className="text-sm font-semibold">GitLab Settings</h1>
          <div className="flex gap-2">
            <button className="text-button" onClick={() => testMutation.mutate()}><TestTube2 size={14} /> Test</button>
            <button className="text-button" onClick={() => syncMutation.mutate()}><RefreshCcw size={14} /> Sync</button>
          </div>
        </div>
        <dl className="grid grid-cols-1 gap-x-4 gap-y-2 p-4 text-sm sm:grid-cols-[220px_minmax(0,1fr)]">
          <dt className="text-[#686b73]">API root</dt><dd className="mono min-w-0 break-words">{data?.gitlab.gitlab_api_root ?? "missing"}</dd>
          <dt className="text-[#686b73]">Project ref</dt><dd className="min-w-0 break-words">{data?.gitlab.gitlab_project_ref ?? "missing"}</dd>
          <dt className="text-[#686b73]">Project</dt><dd className="min-w-0 break-words">{data?.project?.name ?? "unvalidated"}</dd>
          <dt className="text-[#686b73]">Web URL</dt><dd className="min-w-0 break-words">{data?.project?.web_url ?? "n/a"}</dd>
        </dl>
        {testMutation.data && <pre className="m-4 rounded-lg border border-[#eaebef] bg-[#fbfbfc] p-3 text-xs">{JSON.stringify(testMutation.data, null, 2)}</pre>}
      </div>

      <div className="panel">
        <div className="panel-header">
          <h2 className="text-sm font-semibold">Project Access Token</h2>
          <span className={`repo-token-state ${tokenMissing ? "missing" : "configured"}`}>
            {tokenStatus}
          </span>
        </div>
        <div className={`settings-token-summary ${tokenMissing ? "missing" : "configured"}`}>
          <KeyRound size={16} />
          <div>
            <strong>{tokenMissing ? "Token is not saved" : "Token is saved"}</strong>
            <p>{tokenSummary}</p>
          </div>
        </div>
        <div className="settings-form">
          <label className="settings-field">
            <span>Token</span>
            <input
              className="field-input"
              type="password"
              value={projectAccessToken}
              onChange={(event) => setProjectAccessToken(event.target.value)}
              placeholder="Paste a GitLab Project Access Token"
              autoComplete="off"
            />
          </label>
          <button className="text-button" disabled={!projectAccessToken.trim() || tokenMutation.isPending} onClick={() => tokenMutation.mutate(projectAccessToken)}>
            {tokenMutation.isPending ? <RefreshCcw size={14} /> : <Save size={14} />}
            Save token
          </button>
          <p className="settings-hint"><KeyRound size={13} /> The saved token is encrypted and cannot be viewed again from Symphony.</p>
          {tokenMutation.isError && <div className="repo-error">{tokenMutation.error.message}</div>}
        </div>
      </div>
    </section>
  );
}

function WorkflowSettingsPage() {
  const { data } = useQuery({ queryKey: ["settings", "workflow"], queryFn: getWorkflowSettings });
  const workflow = data?.workflow;

  return (
    <section className="panel">
      <div className="panel-header"><h1 className="text-sm font-semibold">Workflow Settings</h1></div>
      <dl className="grid grid-cols-1 gap-x-4 gap-y-2 p-4 text-sm sm:grid-cols-[220px_minmax(0,1fr)]">
        <dt className="text-[#686b73]">Allowed statuses</dt><dd className="min-w-0 break-words">{workflow?.statuses.join(", ")}</dd>
        <dt className="text-[#686b73]">Dispatch candidates</dt><dd className="min-w-0 break-words">{workflow?.dispatchCandidateStatuses.join(", ")}</dd>
        <dt className="text-[#686b73]">Required labels</dt><dd className="min-w-0 break-words">{workflow?.requiredGitlabLabels.join(", ") || "none"}</dd>
        <dt className="text-[#686b73]">Max agents</dt><dd>{workflow?.maxConcurrentAgents}</dd>
        <dt className="text-[#686b73]">Sync interval</dt><dd>{workflow?.syncIntervalMs}ms</dd>
        <dt className="text-[#686b73]">Cursor overlap</dt><dd>{workflow?.cursorOverlapSeconds}s</dd>
        <dt className="text-[#686b73]">Read-only impact</dt><dd className="min-w-0 break-words">{workflow?.readOnlyImpacts}</dd>
      </dl>
    </section>
  );
}
