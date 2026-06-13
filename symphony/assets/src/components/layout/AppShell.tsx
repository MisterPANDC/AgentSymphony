import { useState } from "react";
import { Link, Outlet } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { KeyRound } from "lucide-react";
import { getAuthSession } from "../../api/auth";
import { Sidebar } from "./Sidebar";

export function AppShell() {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const session = useQuery({ queryKey: ["auth-session"], queryFn: getAuthSession, refetchInterval: 30_000 });
  const tokenMissing = session.data?.project?.project_access_token_status === "missing";

  return (
    <div className={`app-grid${sidebarCollapsed ? " is-sidebar-collapsed" : ""}`}>
      <Sidebar collapsed={sidebarCollapsed} onToggleCollapsed={() => setSidebarCollapsed((value) => !value)} />
      <section className="main-region">
        <main className="content">
          {tokenMissing && (
            <div className="token-banner">
              <KeyRound size={15} />
              <span>Project Access Token is required for background sync and Agent GitLab writes.</span>
              <Link to="/settings/gitlab">Open settings</Link>
            </div>
          )}
          <Outlet />
        </main>
      </section>
    </div>
  );
}
