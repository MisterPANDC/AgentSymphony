import { useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Navigate, Route, Routes } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertCircle, CheckCircle2, ExternalLink, Globe2, KeyRound, RefreshCcw, Save, TestTube2, X, type LucideIcon } from "lucide-react";
import {
  getGitLabSettings,
  getWorkflowSettings,
  testGitLabSettings,
  updateAutomationCredentialMode,
  updateProjectAccessToken,
  updateServiceAccountToken
} from "../api/settings";
import { refreshSync } from "../api/sync";
import { listRuns } from "../api/runs";
import { getMonitorState } from "../api/monitor";
import type { AutomationCredentialMode, CredentialStatus } from "../types/gitlab";
import { serviceAccountCreateUrl } from "../utils/gitlabLinks";
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
  const [serviceAccountToken, setServiceAccountToken] = useState("");
  const [serviceAccountConfirmOpen, setServiceAccountConfirmOpen] = useState(false);
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
  const serviceAccountMutation = useMutation({
    mutationFn: updateServiceAccountToken,
    onSuccess: () => {
      setServiceAccountToken("");
      setServiceAccountConfirmOpen(false);
      queryClient.invalidateQueries({ queryKey: ["settings", "gitlab"] });
      queryClient.invalidateQueries({ queryKey: ["auth-session"] });
      queryClient.invalidateQueries({ queryKey: ["gitlab-projects"] });
    }
  });
  const modeMutation = useMutation({
    mutationFn: updateAutomationCredentialMode,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "gitlab"] });
      queryClient.invalidateQueries({ queryKey: ["auth-session"] });
      queryClient.invalidateQueries({ queryKey: ["gitlab-projects"] });
    }
  });
  const syncMutation = useMutation({
    mutationFn: refreshSync,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "gitlab"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
    }
  });
  const project = data?.project;
  const serviceAccount = data?.serviceAccount;
  const credentialMode = project?.automation_credential_mode ?? "project_access_token";
  const legacyPatStatus = data?.gitlab.token_status === "configured" || data?.gitlab.token_status === "redacted" ? "configured" : "missing";
  const patStatus = project?.project_access_token_status ?? legacyPatStatus;
  const serviceAccountStatus = project?.service_account_token_status ?? serviceAccount?.service_account_token_status ?? "missing";
  const activeStatus = credentialMode === "service_account" ? serviceAccountStatus : patStatus;
  const credentialLabel = credentialMode === "service_account" ? "Service Account" : "Project Access Token";
  const serviceAccountIdentity = serviceAccount?.username || serviceAccount?.name || serviceAccount?.gitlab_user_id;
  const serviceAccountSavedAt = serviceAccount?.service_account_token_set_at ? new Date(serviceAccount.service_account_token_set_at).toLocaleString() : null;
  const patSavedAt = project?.project_access_token_set_at ? new Date(project.project_access_token_set_at).toLocaleString() : null;
  const activeIcon = activeStatus === "configured" ? CheckCircle2 : AlertCircle;
  const serviceAccountUrl = serviceAccountCreateUrl(project?.web_url);

  return (
    <section className="settings-page">
      <div className="panel settings-overview-panel">
        <div className="panel-header">
          <div className="settings-title-block">
            <h1>GitLab Settings</h1>
            <span>{project?.path_with_namespace ?? "No repository selected"}</span>
          </div>
          <div className="flex gap-2">
            <button className="text-button" type="button" disabled={testMutation.isPending || !project} onClick={() => testMutation.mutate()}><TestTube2 size={14} /> Test</button>
            <button className="text-button" type="button" disabled={syncMutation.isPending || !project} onClick={() => syncMutation.mutate()}><RefreshCcw size={14} /> Sync</button>
          </div>
        </div>
        <dl className="settings-meta-grid">
          <SettingMeta label="API root" value={data?.gitlab.gitlab_api_root ?? "missing"} mono />
          <SettingMeta label="Project ref" value={data?.gitlab.gitlab_project_ref ?? "missing"} />
          <SettingMeta label="Project" value={project?.name ?? "unvalidated"} />
          <SettingMeta label="Web URL" value={project?.web_url ?? "n/a"} />
          <SettingMeta label="Active credential" value={`${credentialLabel} / ${activeStatus}`} icon={activeIcon} />
          <SettingMeta label="Service Account" value={serviceAccountIdentity ? `${serviceAccountIdentity}${serviceAccountSavedAt ? `, saved ${serviceAccountSavedAt}` : ""}` : "not saved"} />
        </dl>
        {testMutation.data && <pre className="settings-test-result">{JSON.stringify(testMutation.data, null, 2)}</pre>}
        {testMutation.isError && <div className="repo-error">{testMutation.error.message}</div>}
        {syncMutation.isError && <div className="repo-error">{syncMutation.error.message}</div>}
      </div>

      <div className="panel settings-mode-panel">
        <div className="panel-header">
          <h2 className="text-sm font-semibold">Repository Automation Credential</h2>
          <StatusBadge status={activeStatus} label={activeStatus === "configured" ? "ready" : "missing"} />
        </div>
        <div className="settings-mode-options">
          <CredentialModeButton
            mode="project_access_token"
            activeMode={credentialMode}
            status={patStatus}
            icon={KeyRound}
            title="Project Access Token"
            description={patStatus === "configured" ? "Scoped to this repository." : "Selected by default. Add a token to enable automation."}
            disabled={!project || modeMutation.isPending}
            onSelect={(mode) => modeMutation.mutate(mode)}
          />
          <CredentialModeButton
            mode="service_account"
            activeMode={credentialMode}
            status={serviceAccountStatus}
            icon={Globe2}
            title="Global Service Account"
            description={serviceAccountStatus === "configured" ? "Shared on this GitLab host. Opt in per repository." : "Create once in GitLab, save the token, then opt in per repository."}
            disabled={!project || modeMutation.isPending}
            onSelect={(mode) => modeMutation.mutate(mode)}
          />
        </div>
        {modeMutation.isError && <div className="repo-error">{modeMutation.error.message}</div>}
      </div>

      <div className="settings-credential-grid">
        <section className="panel">
          <div className="panel-header">
            <h2 className="text-sm font-semibold">Project Access Token</h2>
            <StatusBadge status={patStatus} label={patStatus === "configured" ? "saved" : "missing"} />
          </div>
          <div className={`settings-token-summary ${patStatus}`}>
            <KeyRound size={16} />
            <div>
              <strong>{patStatus === "configured" ? "Token saved" : "No project token"}</strong>
              <p>{patSavedAt ? `Saved ${patSavedAt}.` : "Used only by this repository."}</p>
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
                <button className="text-button settings-token-save-button" type="button" disabled={!projectAccessToken.trim() || tokenMutation.isPending || !project} onClick={() => tokenMutation.mutate(projectAccessToken)}>
                  {tokenMutation.isPending ? <RefreshCcw size={14} /> : <Save size={14} />}
                  Save and use
                </button>
              </div>
            </div>
            <p className="settings-hint">Encrypted at rest and never returned to the browser.</p>
            {tokenMutation.isError && <div className="repo-error">{tokenMutation.error.message}</div>}
          </div>
        </section>

        <section className="panel">
          <div className="panel-header">
            <h2 className="text-sm font-semibold">Service Account</h2>
            <StatusBadge status={serviceAccountStatus} label={serviceAccountStatus === "configured" ? "saved globally" : "missing"} />
          </div>
          <div className={`settings-token-summary ${serviceAccountStatus}`}>
            <Globe2 size={16} />
            <div>
              <div className="settings-summary-title-row">
                <strong>{serviceAccountIdentity ?? "No Service Account token"}</strong>
                {serviceAccountStatus === "missing" && serviceAccountUrl && (
                  <a className="settings-inline-link" href={serviceAccountUrl} target="_blank" rel="noreferrer">
                    Create in GitLab
                    <ExternalLink size={12} />
                  </a>
                )}
              </div>
              <p>{serviceAccountSavedAt ? `Saved ${serviceAccountSavedAt} for ${data?.gitlab.gitlab_api_root ?? "this GitLab host"}.` : "Available to any repository on this GitLab host after saving."}</p>
            </div>
          </div>
          <div className="settings-form">
            <div className="settings-field">
              <label htmlFor="service-account-token">Token</label>
              <div className="settings-token-action-row">
                <input
                  id="service-account-token"
                  className="field-input"
                  type="password"
                  value={serviceAccountToken}
                  onChange={(event) => setServiceAccountToken(event.target.value)}
                  placeholder="Paste a GitLab Service Account token"
                  autoComplete="off"
                />
                <button className="text-button settings-token-save-button" type="button" disabled={!serviceAccountToken.trim() || serviceAccountMutation.isPending || !project} onClick={() => setServiceAccountConfirmOpen(true)}>
                  {serviceAccountMutation.isPending ? <RefreshCcw size={14} /> : <Save size={14} />}
                  Save globally
                </button>
              </div>
            </div>
            <p className="settings-hint">Saved once per GitLab API root; repositories opt in individually.</p>
            {serviceAccountMutation.isError && <div className="repo-error">{serviceAccountMutation.error.message}</div>}
          </div>
        </section>
      </div>

      <Dialog.Root open={serviceAccountConfirmOpen} onOpenChange={setServiceAccountConfirmOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="confirm-dialog-overlay" />
          <Dialog.Content className="confirm-dialog-content settings-service-dialog">
            <div className="confirm-dialog-icon">
              <Globe2 size={18} />
            </div>
            <div className="confirm-dialog-body">
              <Dialog.Title className="confirm-dialog-title">Save global Service Account?</Dialog.Title>
              <Dialog.Description className="confirm-dialog-description">
                This token will be stored for {data?.gitlab.gitlab_api_root ?? "this GitLab host"} and can be selected by other repositories in Symphony.
              </Dialog.Description>
              <div className="confirm-dialog-actions">
                <Dialog.Close className="text-button" type="button" disabled={serviceAccountMutation.isPending}>
                  <X size={14} />
                  Cancel
                </Dialog.Close>
                <button className="text-button" type="button" disabled={serviceAccountMutation.isPending} onClick={() => serviceAccountMutation.mutate(serviceAccountToken)}>
                  {serviceAccountMutation.isPending ? <RefreshCcw size={14} /> : <Save size={14} />}
                  Save and use
                </button>
              </div>
            </div>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </section>
  );
}

function SettingMeta({ label, value, mono = false, icon: Icon }: { label: string; value: string; mono?: boolean; icon?: LucideIcon }) {
  return (
    <>
      <dt>{label}</dt>
      <dd className={mono ? "mono" : undefined}>
        {Icon && <Icon size={13} />}
        <span>{value}</span>
      </dd>
    </>
  );
}

function StatusBadge({ status, label }: { status: CredentialStatus; label: string }) {
  return <span className={`repo-token-state ${status}`}>{label}</span>;
}

function CredentialModeButton({
  mode,
  activeMode,
  status,
  icon: Icon,
  title,
  description,
  disabled,
  onSelect
}: {
  mode: AutomationCredentialMode;
  activeMode: AutomationCredentialMode;
  status: CredentialStatus;
  icon: LucideIcon;
  title: string;
  description: string;
  disabled: boolean;
  onSelect: (mode: AutomationCredentialMode) => void;
}) {
  const active = mode === activeMode;

  return (
    <button className={`settings-mode-option is-${status}${active ? " is-active" : ""}`} type="button" disabled={disabled} onClick={() => onSelect(mode)}>
      <Icon size={16} />
      <div>
        <strong>{title}</strong>
        <span>{description}</span>
      </div>
      <span className="settings-mode-state">{active ? "Active" : status === "configured" ? "Available" : "Set up"}</span>
    </button>
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
