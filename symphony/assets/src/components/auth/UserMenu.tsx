import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { LogOut, UserCircle } from "lucide-react";
import { getAuthSession } from "../../api/auth";

export function UserMenu() {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const { data } = useQuery({
    queryKey: ["auth-session"],
    queryFn: getAuthSession,
    refetchInterval: 30_000
  });

  const user = data?.user;
  const displayName = user?.name || user?.username;

  useEffect(() => {
    if (!open) {
      return;
    }

    function onPointerDown(event: PointerEvent) {
      if (!wrapperRef.current?.contains(event.target as Node)) {
        setOpen(false);
      }
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setOpen(false);
      }
    }

    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  if (!user) {
    return null;
  }

  return (
    <div className="user-menu" ref={wrapperRef}>
      <button
        className={`user-chip${open ? " is-open" : ""}`}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        title={`${displayName} (${user.role})`}
        onClick={() => setOpen((value) => !value)}
      >
        {user.avatar_url ? (
          <img className="user-chip-avatar" src={user.avatar_url} alt="" />
        ) : (
          <UserCircle size={16} className="user-chip-icon" />
        )}
        <span className="user-chip-name">
          {displayName}
          <span className="user-chip-role">({user.role})</span>
        </span>
      </button>

      {open && (
        <div className="user-menu-popover" role="menu">
          <div className="user-menu-header">
            {user.avatar_url ? (
              <img className="user-menu-avatar" src={user.avatar_url} alt="" />
            ) : (
              <UserCircle size={34} className="user-menu-avatar-icon" />
            )}
            <span className="user-menu-heading">
              <span className="user-menu-name">{displayName}</span>
              <span className="user-menu-username">@{user.username}</span>
            </span>
          </div>

          <dl className="user-menu-details">
            <div>
              <dt>Role</dt>
              <dd>{user.role}</dd>
            </div>
            {user.email && (
              <div>
                <dt>Email</dt>
                <dd>{user.email}</dd>
              </div>
            )}
            {user.gitlab_user_id && (
              <div>
                <dt>GitLab ID</dt>
                <dd>{user.gitlab_user_id}</dd>
              </div>
            )}
            <div>
              <dt>Provider</dt>
              <dd>{user.provider}</dd>
            </div>
            {user.profile_url && (
              <div>
                <dt>Profile</dt>
                <dd>
                  <a href={user.profile_url} target="_blank" rel="noreferrer">
                    Open in GitLab
                  </a>
                </dd>
              </div>
            )}
          </dl>

          <a className="user-menu-logout" href={data.auth.logoutUrl} role="menuitem">
            <LogOut size={14} />
            <span>Sign out</span>
          </a>
        </div>
      )}
    </div>
  );
}
