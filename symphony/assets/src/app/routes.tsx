import { useEffect, useState } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, FolderGit2, KeyRound, RefreshCcw, Save, Search, TestTube2 } from "lucide-react";
import {
  getGitLabSettings,
  getWorkflowSettings,
  scanLocalRepoCandidates,
  testGitLabSettings,
  updateLocalRepoPath,
  updateProjectAccessToken
} from "../api/settings";
import { refreshSync } from "../api/sync";
import { listRuns } from "../api/runs";
import { getMonitorState } from "../api/monitor";
import type { GitLabSettingsDTO } from "../types/gitlab";
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

function LocalRepositorySettings({ project, onSaved }: { project: GitLabSettingsDTO["project"]; onSaved: () => void }) {
  const [repoPath, setRepoPath] = useState("");
  const [lastSearchScope, setLastSearchScope] = useState<"nearby" | "local">("nearby");
  const savedPath = project?.local_repo_path ?? "";
  const repoConfigured = Boolean(savedPath);
  const saveMutation = useMutation({ mutationFn: updateLocalRepoPath, onSuccess: onSaved });
  const scanMutation = useMutation({ mutationFn: scanLocalRepoCandidates });

  useEffect(() => {
    setRepoPath(savedPath);
  }, [savedPath]);

  const hasChange = repoPath.trim() !== savedPath;
  const saveButtonLabel = repoPath.trim() || !savedPath ? "Save path" : "Clear path";
  const candidates = scanMutation.data?.candidates ?? [];
  const showWiderSearch = scanMutation.isSuccess && lastSearchScope === "nearby" && candidates.length === 0;
  const emptySearchCopy =
    lastSearchScope === "local"
      ? "No matching checkout was found in wider local folders. Paste a path manually."
      : "No nearby checkout was found.";

  const runSearch = (scope: "nearby" | "local") => {
    setLastSearchScope(scope);
    scanMutation.mutate(scope);
  };

  return (
    <div className="panel">
      <div className="panel-header">
        <h2 className="text-sm font-semibold">Local Repository</h2>
        <span className={`repo-token-state ${repoConfigured ? "configured" : "missing"}`}>
          {repoConfigured ? "configured" : "missing"}
        </span>
      </div>
      <div className={`settings-token-summary ${repoConfigured ? "configured" : "missing"}`}>
        <FolderGit2 size={16} />
        <div>
          <strong>{repoConfigured ? "Repository is linked" : "Repository is not linked"}</strong>
          <p>
            {repoConfigured
              ? "Symphony knows which local checkout belongs to this GitLab project. Workspace creation is configured separately."
              : "Choose the local checkout that belongs to this GitLab project before enabling local agent workspaces."}
          </p>
        </div>
      </div>
      <div className="settings-form">
        <div className="settings-field">
          <label htmlFor="local-repo-path">Path</label>
          <div className="local-repo-path-row">
            <input
              id="local-repo-path"
              className="field-input"
              value={repoPath}
              onChange={(event) => setRepoPath(event.target.value)}
              placeholder="Choose or paste a local repository path"
              autoComplete="off"
            />
            {hasChange && (
              <div className="local-repo-pending-actions">
                <button
                  className="text-button settings-token-save-button"
                  type="button"
                  disabled={!project || saveMutation.isPending}
                  onClick={() => saveMutation.mutate(repoPath)}
                >
                  {saveMutation.isPending ? <RefreshCcw size={14} /> : <Save size={14} />}
                  {saveButtonLabel}
                </button>
                <button className="text-button" type="button" disabled={saveMutation.isPending} onClick={() => setRepoPath(savedPath)}>
                  Reset
                </button>
              </div>
            )}
          </div>
        </div>
        <div className="local-repo-search-row">
          <button
            className="text-button local-repo-search-button"
            type="button"
            disabled={!project || scanMutation.isPending}
            onClick={() => runSearch("nearby")}
          >
            {scanMutation.isPending ? <RefreshCcw size={14} /> : <Search size={14} />}
            Search local repo
          </button>
        </div>
        {saveMutation.isSuccess && !hasChange && repoConfigured && (
          <p className="settings-hint local-repo-saved">
            <CheckCircle2 size={13} /> Saved for this GitLab project.
          </p>
        )}
        {saveMutation.isSuccess && !hasChange && !repoConfigured && (
          <p className="settings-hint local-repo-saved">
            <CheckCircle2 size={13} /> Local repository path cleared.
          </p>
        )}
        {scanMutation.isError && <div className="repo-error">{scanMutation.error.message}</div>}
        {saveMutation.isError && <div className="repo-error">{saveMutation.error.message}</div>}
        {scanMutation.isSuccess && candidates.length === 0 && (
          <div className="local-repo-empty">
            <span>{emptySearchCopy}</span>
            {showWiderSearch && (
              <button className="text-button local-repo-wider-search-button" type="button" disabled={!project} onClick={() => runSearch("local")}>
                <Search size={14} />
                Search wider local folders
              </button>
            )}
          </div>
        )}
        {candidates.length > 0 && (
          <div className="local-repo-candidates" aria-label="Local repository suggestions">
            {candidates.map((candidate) => (
              <button className="local-repo-candidate" type="button" key={candidate.path} onClick={() => setRepoPath(candidate.path)}>
                <span className="local-repo-candidate-icon">
                  {candidate.path === repoPath ? <CheckCircle2 size={15} /> : <FolderGit2 size={15} />}
                </span>
                <span className="local-repo-candidate-main">
                  <span className="local-repo-candidate-path">{candidate.path}</span>
                  <span className="local-repo-candidate-reason">{candidate.reason}</span>
                </span>
                <span className="local-repo-candidate-action">{candidate.path === repoPath ? "Selected" : "Select"}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
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

      <LocalRepositorySettings
        project={data?.project ?? null}
        onSaved={() => {
          queryClient.invalidateQueries({ queryKey: ["settings", "gitlab"] });
          queryClient.invalidateQueries({ queryKey: ["auth-session"] });
        }}
      />

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
          <div className="settings-field">
            <label htmlFor="project-access-token">Token</label>
            <div className="settings-token-action-row">
              <input
                id="project-access-token"
                className="field-input"
                type="password"
                value={projectAccessToken}
                onChange={(event) => setProjectAccessToken(event.target.value)}
                placeholder="Paste a GitLab Project Access Token"
                autoComplete="off"
              />
              <button className="text-button settings-token-save-button" type="button" disabled={!projectAccessToken.trim() || tokenMutation.isPending} onClick={() => tokenMutation.mutate(projectAccessToken)}>
                {tokenMutation.isPending ? <RefreshCcw size={14} /> : <Save size={14} />}
                Save token
              </button>
            </div>
          </div>
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
