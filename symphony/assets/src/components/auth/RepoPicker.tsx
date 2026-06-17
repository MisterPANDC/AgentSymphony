import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { GitBranch, RefreshCcw, Search } from "lucide-react";
import { activateGitLabProject, listGitLabProjects } from "../../api/auth";

export function RepoPicker() {
  const queryClient = useQueryClient();
  const [query, setQuery] = useState("");
  const projects = useQuery({ queryKey: ["gitlab-projects"], queryFn: () => listGitLabProjects(), staleTime: 60_000 });
  const refreshProjects = useMutation({
    mutationFn: () => listGitLabProjects(true),
    onSuccess: (payload) => {
      queryClient.setQueryData(["gitlab-projects"], payload);
    }
  });
  const activate = useMutation({
    mutationFn: activateGitLabProject,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["auth-session"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      queryClient.invalidateQueries({ queryKey: ["issues"] });
    }
  });

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const rows = projects.data?.projects ?? [];

    if (!needle) {
      return rows;
    }

    return rows.filter((project) => `${project.name} ${project.path_with_namespace}`.toLowerCase().includes(needle));
  }, [projects.data?.projects, query]);

  return (
    <main className="repo-screen">
      <section className="repo-picker">
        <div className="repo-picker-header">
          <div>
            <div className="auth-kicker">Symphony</div>
            <h1>Choose a GitLab repository</h1>
          </div>
          <button
            className="icon-button"
            onClick={() => refreshProjects.mutate()}
            disabled={projects.isFetching || refreshProjects.isPending}
            title="Refresh repositories"
          >
            <RefreshCcw size={15} />
          </button>
        </div>

        <label className="repo-search">
          <Search size={15} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search repositories" />
        </label>

        <div className="repo-list">
          {projects.isLoading && <div className="empty-state">Loading repositories...</div>}
          {projects.isError && <div className="empty-state">Unable to load repositories.</div>}
          {!projects.isLoading && filtered.length === 0 && <div className="empty-state">No repositories found.</div>}
          {filtered.map((project) => {
            const credentialStatus = project.automation_credential_status ?? project.project_access_token_status;
            const credentialMode = project.automation_credential_mode ?? "project_access_token";
            const credentialLabel =
              credentialStatus === "configured"
                ? credentialMode === "service_account"
                  ? "SA set"
                  : "PAT set"
                : credentialMode === "service_account"
                  ? "SA missing"
                  : "PAT missing";

            return (
              <button
                key={project.id}
                className="repo-row"
                onClick={() => activate.mutate(project.id)}
                disabled={activate.isPending}
              >
                <GitBranch size={15} />
                <span className="repo-row-main">
                  <span className="repo-row-name">{project.name}</span>
                  <span className="repo-row-path">{project.path_with_namespace}</span>
                </span>
                <span className={`repo-token-state ${credentialStatus}`}>
                  {credentialLabel}
                </span>
              </button>
            );
          })}
        </div>

        {activate.isError && <div className="repo-error">{activate.error.message}</div>}
      </section>
    </main>
  );
}
