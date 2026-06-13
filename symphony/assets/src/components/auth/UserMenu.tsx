import { useQuery } from "@tanstack/react-query";
import { LogOut, ShieldCheck, UserCircle } from "lucide-react";
import { getAuthSession } from "../../api/auth";

export function UserMenu() {
  const { data } = useQuery({
    queryKey: ["auth-session"],
    queryFn: getAuthSession,
    refetchInterval: 30_000
  });

  const user = data?.user;

  if (!user) {
    return null;
  }

  return (
    <div className="user-chip">
      {user.avatar_url ? (
        <img className="user-chip-avatar" src={user.avatar_url} alt="" />
      ) : (
        <UserCircle size={16} className="user-chip-icon" />
      )}
      <span className="user-chip-name">{user.username}</span>
      <span className="user-chip-role">
        <ShieldCheck size={12} />
        {user.role}
      </span>
      <a className="user-chip-logout" href={data.auth.logoutUrl} title="Sign out">
        <LogOut size={13} />
      </a>
    </div>
  );
}
