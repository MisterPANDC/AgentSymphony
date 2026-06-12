import { Outlet } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, CircleDot } from "lucide-react";
import { getMonitorState } from "../../api/monitor";
import { CommandPalette } from "../command/CommandPalette";
import { SyncStatusBadge } from "../sync/SyncStatusBadge";
import { Sidebar } from "./Sidebar";

export function AppShell() {
  const { data } = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });
  const active = data?.agents.running ?? 0;
  const blocked = data?.blocked.length ?? 0;

  return (
    <div className="app-grid">
      <Sidebar />
      <section className="main-region">
        <header className="topbar">
          <CommandPalette />
          <div className="ml-auto flex items-center gap-2">
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
          </div>
        </header>
        <main className="content">
          <Outlet />
        </main>
      </section>
    </div>
  );
}
