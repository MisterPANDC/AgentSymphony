import { useState } from "react";
import { Link, Outlet } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ExternalLink, KeyRound } from "lucide-react";
import { getAuthSession } from "../../api/auth";
import { Sidebar } from "./Sidebar";

export function AppShell() {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const session = useQuery({ queryKey: ["auth-session"], queryFn: getAuthSession, refetchInterval: 30_000 });
  const tokenMissing = session.data?.project?.project_access_token_status === "missing";
  const projectTokenUrl = projectAccessTokenUrl(session.data?.project?.web_url);

  return (
    <div className={`app-grid${sidebarCollapsed ? " is-sidebar-collapsed" : ""}`}>
      <Sidebar collapsed={sidebarCollapsed} onToggleCollapsed={() => setSidebarCollapsed((value) => !value)} />
      <section className="main-region">
        <main className="content">
          {tokenMissing && (
            <div className="token-banner">
              <KeyRound size={15} />
              <span className="token-banner-message">
                Create a Project Access Token in GitLab, then paste it in Symphony settings for background sync and Agent GitLab writes.
              </span>
              <span className="token-banner-actions">
                {projectTokenUrl && (
                  <a href={projectTokenUrl} target="_blank" rel="noreferrer">
                    Create in GitLab
                    <ExternalLink size={13} />
                  </a>
                )}
                <Link to="/settings/gitlab">Open settings</Link>
              </span>
            </div>
          )}
          <Outlet />
        </main>
      </section>
    </div>
  );
}

function projectAccessTokenUrl(projectWebUrl?: string | null) {
  if (!projectWebUrl) return null;

  const trimmedUrl = projectWebUrl.trim();
  if (!trimmedUrl) return null;

  try {
    const url = new URL(trimmedUrl);
    url.pathname = `${url.pathname.replace(/\/+$/, "")}/-/settings/access_tokens`;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}
