import { useState } from "react";
import { Link, Outlet } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ExternalLink, KeyRound } from "lucide-react";
import { getAuthSession } from "../../api/auth";
import { AiChatFloatingPanel } from "../ai/AiChatFloatingPanel";
import { projectAccessTokenUrl, serviceAccountCreateUrl } from "../../utils/gitlabLinks";
import { Sidebar } from "./Sidebar";

export function AppShell() {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const session = useQuery({ queryKey: ["auth-session"], queryFn: getAuthSession, refetchInterval: 30_000 });
  const project = session.data?.project;
  const credentialMode = project?.automation_credential_mode ?? "project_access_token";
  const credentialMissing = project?.automation_credential_status === "missing" || (!project?.automation_credential_status && project?.project_access_token_status === "missing");
  const serviceAccountConfigured = project?.service_account_token_status === "configured";
  const projectTokenUrl = projectAccessTokenUrl(project?.web_url);
  const serviceAccountUrl = serviceAccountCreateUrl(project?.web_url);
  const bannerMessage =
    credentialMode === "service_account"
      ? "Service Account mode is selected, but no global Service Account token is saved for this GitLab host."
      : serviceAccountConfigured
        ? "Create a Project Access Token in GitLab, or switch this repository to the saved global Service Account."
        : "Create a Project Access Token in GitLab, or create a Service Account in GitLab and save its token in settings.";

  return (
    <div className={`app-grid${sidebarCollapsed ? " is-sidebar-collapsed" : ""}`}>
      <Sidebar collapsed={sidebarCollapsed} onToggleCollapsed={() => setSidebarCollapsed((value) => !value)} />
      <section className="main-region">
        <main className="content">
          {credentialMissing && (
            <div className="token-banner">
              <KeyRound size={15} />
              <span className="token-banner-message">
                {bannerMessage}
              </span>
              <span className="token-banner-actions">
                {credentialMode === "project_access_token" && projectTokenUrl && (
                  <a href={projectTokenUrl} target="_blank" rel="noreferrer">
                    Create PAT
                    <ExternalLink size={13} />
                  </a>
                )}
                {serviceAccountConfigured ? (
                  <Link to="/settings/gitlab">Use Service Account</Link>
                ) : serviceAccountUrl ? (
                  <a href={serviceAccountUrl} target="_blank" rel="noreferrer">
                    Create Service Account
                    <ExternalLink size={13} />
                  </a>
                ) : (
                  <Link to="/settings/gitlab">Set up Service Account</Link>
                )}
                <Link to="/settings/gitlab">Open settings</Link>
              </span>
            </div>
          )}
          <Outlet />
        </main>
      </section>
      <AiChatFloatingPanel />
    </div>
  );
}
