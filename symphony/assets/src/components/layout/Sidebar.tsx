import { NavLink } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  Bot,
  Columns3,
  GitBranch,
  History,
  LayoutDashboard,
  MonitorDot,
  PanelLeftClose,
  PanelLeftOpen,
  Settings
} from "lucide-react";
import { getAuthSession } from "../../api/auth";
import { getMonitorState } from "../../api/monitor";
import { UserMenu } from "../auth/UserMenu";
import { CommandPalette } from "../command/CommandPalette";
import { ProjectSwitcher } from "./ProjectSwitcher";

const links = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/issues", label: "Issues", icon: GitBranch },
  { to: "/board", label: "Board", icon: Columns3 },
  { to: "/agents", label: "Agents", icon: Bot },
  { to: "/runs", label: "Runs", icon: History },
  { to: "/monitor", label: "Run Monitor", icon: MonitorDot },
  { to: "/settings/gitlab", label: "Settings", icon: Settings }
];

interface SidebarProps {
  collapsed: boolean;
  onToggleCollapsed: () => void;
}

export function Sidebar({ collapsed, onToggleCollapsed }: SidebarProps) {
  const monitor = useQuery({ queryKey: ["monitor-state"], queryFn: getMonitorState });
  const session = useQuery({ queryKey: ["auth-session"], queryFn: getAuthSession, refetchInterval: 30_000 });
  const sync = monitor.data?.sync;
  const currentProject = session.data?.project;
  const tokenMissing = currentProject?.project_access_token_status === "missing";
  const monitorMatchesCurrentProject =
    Boolean(currentProject && sync) &&
    typeof currentProject?.project_id === "number" &&
    monitor.data?.gitlab.projectId === currentProject.project_id;
  const syncError = monitorMatchesCurrentProject ? sync?.issueLastError : null;
  const syncUnsynced = Boolean(currentProject && (tokenMissing || syncError));
  const syncTitle = tokenMissing
    ? "Project Access Token is missing; GitLab sync has not run."
    : syncError ?? undefined;
  const CollapseIcon = collapsed ? PanelLeftOpen : PanelLeftClose;

  return (
    <aside className="sidebar">
      <UserMenu />
      <ProjectSwitcher collapsed={collapsed} syncUnsynced={syncUnsynced} syncTitle={syncTitle} />
      <nav className="sidebar-nav">
        <CommandPalette />
        {links.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            title={collapsed ? label : undefined}
            aria-label={label}
            className={({ isActive }) =>
              `sidebar-link${isActive ? " is-active" : ""}`
            }
          >
            <span className="sidebar-link-icon"><Icon size={17} /></span>
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>
      <button
        className="sidebar-collapse-button"
        type="button"
        onClick={onToggleCollapsed}
        title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
      >
        <span className="sidebar-link-icon"><CollapseIcon size={17} /></span>
        <span>Collapse sidebar</span>
      </button>
    </aside>
  );
}
