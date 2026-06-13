import { NavLink } from "react-router-dom";
import { Bot, Columns3, GitBranch, History, LayoutDashboard, MonitorDot, Settings } from "lucide-react";
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

export function Sidebar() {
  return (
    <aside className="sidebar">
      <ProjectSwitcher />
      <nav className="sidebar-nav">
        {links.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              `sidebar-link${isActive ? " is-active" : ""}`
            }
          >
            <Icon size={14} />
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
