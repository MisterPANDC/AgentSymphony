import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronDown, GitBranch, RefreshCcw, Search } from "lucide-react";
import { activateGitLabProject, getAuthSession, listGitLabProjects } from "../../api/auth";
import type { AuthSession, GitLabProject } from "../../types/auth";

const projectScopedQueryKeys = ["monitor-state", "issues", "runs", "settings"];

export function ProjectSwitcher() {
  const queryClient = useQueryClient();
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  const session = useQuery({
    queryKey: ["auth-session"],
    queryFn: getAuthSession,
    refetchInterval: 30_000
  });

  const projects = useQuery({
    queryKey: ["gitlab-projects"],
    queryFn: listGitLabProjects,
    enabled: open
  });

  const activate = useMutation({
    mutationFn: activateGitLabProject,
    onSuccess: (payload) => {
      queryClient.setQueryData<AuthSession>(["auth-session"], (previous) =>
        previous ? { ...previous, ...payload } : previous
      );

      projectScopedQueryKeys.forEach((queryKey) => {
        queryClient.invalidateQueries({ queryKey: [queryKey] });
      });
      queryClient.invalidateQueries({ queryKey: ["gitlab-projects"] });
      queryClient.invalidateQueries({ queryKey: ["auth-session"] });

      setOpen(false);
      setQuery("");
    }
  });

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

  const filteredProjects = useMemo(() => {
    const rows = projects.data?.projects ?? [];
    const needle = query.trim().toLowerCase();

    if (!needle) {
      return rows;
    }

    return rows.filter((project) => `${project.name} ${project.path_with_namespace}`.toLowerCase().includes(needle));
  }, [projects.data?.projects, query]);

  const currentProject = session.data?.project;
  const currentProjectPath = currentProject?.path_with_namespace || currentProject?.name || "Select repository";

  function selectProject(project: GitLabProject) {
    if (project.selected) {
      setOpen(false);
      return;
    }

    activate.mutate(project.id);
  }

  return (
    <div className="project-switcher" ref={wrapperRef}>
      <button
        className={`project-switcher-trigger${open ? " is-open" : ""}`}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <div className="sidebar-logo">S</div>
        <span className="project-switcher-copy">
          <span className="sidebar-title">Symphony</span>
          <span className="project-switcher-current">{currentProjectPath}</span>
        </span>
        <ChevronDown size={14} className="project-switcher-chevron" />
      </button>

      {open && (
        <div className="project-switcher-menu" role="menu">
          <div className="project-switcher-menu-header">
            <span>Repositories</span>
            <button
              className="icon-button"
              type="button"
              onClick={() => projects.refetch()}
              disabled={projects.isFetching}
              title="Refresh repositories"
            >
              <RefreshCcw size={14} />
            </button>
          </div>

          <label className="project-switcher-search">
            <Search size={14} />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search repositories"
              autoFocus
            />
          </label>

          <div className="project-switcher-list">
            {projects.isLoading && <div className="empty-state">Loading repositories...</div>}
            {projects.isError && <div className="empty-state">Unable to load repositories.</div>}
            {!projects.isLoading && !projects.isError && filteredProjects.length === 0 && (
              <div className="empty-state">No repositories found.</div>
            )}
            {filteredProjects.map((project) => (
              <button
                key={project.id}
                className={`project-switcher-row${project.selected ? " is-selected" : ""}`}
                type="button"
                onClick={() => selectProject(project)}
                disabled={activate.isPending}
                role="menuitem"
              >
                <GitBranch size={15} />
                <span className="project-switcher-row-main">
                  <span className="project-switcher-row-name">{project.name}</span>
                  <span className="project-switcher-row-path">{project.path_with_namespace}</span>
                </span>
                <span className="project-switcher-row-meta">
                  {project.selected && <Check size={14} />}
                  <span className={`repo-token-state ${project.project_access_token_status}`}>
                    {project.project_access_token_status === "configured" ? "PAT set" : "PAT missing"}
                  </span>
                </span>
              </button>
            ))}
          </div>

          {activate.isError && <div className="repo-error">{activate.error.message}</div>}
        </div>
      )}
    </div>
  );
}
