import { NavLink } from "react-router-dom";
import { Activity, Bot, Columns3, GitBranch, History, LayoutDashboard, MonitorDot, Settings } from "lucide-react";

const links = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/issues", label: "Issues", icon: GitBranch },
  { to: "/board", label: "Board", icon: Columns3 },
  { to: "/agents", label: "Agents", icon: Bot },
  { to: "/runs", label: "Runs", icon: History },
  { to: "/monitor", label: "Run Monitor", icon: MonitorDot },
  { to: "/monitor/blocks", label: "Blocks", icon: Activity },
  { to: "/settings/gitlab", label: "Settings", icon: Settings }
];

export function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="mb-4 flex min-w-[210px] items-center gap-2 px-2">
        <div className="h-7 w-7 rounded-md border border-[#cbd5e1] bg-[#ffffff]" />
        <div>
          <div className="text-sm font-semibold">Symphony</div>
          <div className="text-[11px] text-[#6b7280]">GitLab control</div>
        </div>
      </div>
      <nav className="flex flex-1 flex-col gap-1 sm:min-w-[210px]">
        {links.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              `flex h-8 items-center gap-2 rounded-md px-2 text-sm ${
                isActive ? "bg-[#e5e7eb] text-[#191914]" : "text-[#475569] hover:bg-[#f1f5f9]"
              }`
            }
          >
            <Icon size={15} />
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
