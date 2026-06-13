import type { ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { GitBranch, LockKeyhole, ShieldCheck } from "lucide-react";
import { getAuthSession } from "../../api/auth";
import { RepoPicker } from "./RepoPicker";

interface AuthGateProps {
  children: ReactNode;
}

export function AuthGate({ children }: AuthGateProps) {
  const session = useQuery({
    queryKey: ["auth-session"],
    queryFn: getAuthSession,
    refetchInterval: 30_000,
    retry: false
  });

  if (session.isLoading) {
    return <div className="auth-screen"><div className="auth-loading" /></div>;
  }

  const data = session.data;

  if (data?.auth.enabled && !data.user) {
    return <LoginPage loginUrl={data.auth.loginUrl} project={data.project?.path_with_namespace ?? data.project?.name} />;
  }

  if (data?.auth.enabled && data.user && !data.project) {
    return <RepoPicker />;
  }

  return <>{children}</>;
}

function LoginPage({ loginUrl, project }: { loginUrl: string; project?: string }) {
  const returnTo = `${loginUrl}?return_to=${encodeURIComponent(window.location.pathname + window.location.search)}`;

  return (
    <main className="auth-screen">
      <section className="auth-panel">
        <div className="auth-mark">
          <GitBranch size={18} />
        </div>
        <div className="auth-copy">
          <div className="auth-kicker">Symphony</div>
          <h1>GitLab sign-in</h1>
          <p>{project ?? "GitLab project"} access is checked against your GitLab project role.</p>
        </div>
        <a className="auth-primary" href={returnTo}>
          <LockKeyhole size={15} />
          Continue with GitLab
        </a>
        <div className="auth-footnote">
          <ShieldCheck size={13} />
          <span>Project membership controls what you can view and change.</span>
        </div>
      </section>
    </main>
  );
}
