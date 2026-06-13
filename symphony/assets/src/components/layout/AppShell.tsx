import { Link, Outlet } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, CircleDot, KeyRound } from "lucide-react";
import { getAuthSession } from "../../api/auth";
import { getMonitorState } from "../../api/monitor";
import { UserMenu } from "../auth/UserMenu";
import { CommandPalette } from "../command/CommandPalette";
import { SyncStatusBadge } from "../sync/SyncStatusBadge";
import { Sidebar } from "./Sidebar";

export function AppShell() {
  const { data } = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });
  const session = useQuery({ queryKey: ["auth-session"], queryFn: getAuthSession, refetchInterval: 30_000 });
  const active = data?.agents.running ?? 0;
  const blocked = data?.blocked.length ?? 0;
  const tokenMissing = session.data?.project?.project_access_token_status === "missing";

  return (
    <div className="app-grid">
      <header className="topbar">
        <div className="topbar-search">
          <CommandPalette />
        </div>
        <div className="topbar-status flex shrink-0 items-center gap-2">
          <SyncStatusBadge />
          <span className="status-pill" title="Active runs">
            <CircleDot size={12} className="mr-1" />
            {active} active
          </span>
          {blocked > 0 && (
            <span className="status-pill blocked" title="Run Monitor needs attention">
              <AlertTriangle size={12} className="mr-1" />
              {blocked} blocked
            </span>
          )}
          <UserMenu />
        </div>
      </header>
      <Sidebar />
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
