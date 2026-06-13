import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, GitBranch, RefreshCcw, Search } from "lucide-react";
import { activateGitLabProject, getAuthSession, listGitLabProjects } from "../../api/auth";
import type { AuthSession, GitLabProject } from "../../types/auth";

const projectScopedQueryKeys = ["monitor-state", "issues", "runs", "settings"];

function projectNameFromPath(path?: string) {
  const parts = path?.split("/").filter(Boolean) ?? [];
  const name = parts[parts.length - 1];
  return name ? name.charAt(0).toUpperCase() + name.slice(1) : undefined;
}

function projectInitial(name: string) {
  return Array.from(name.trim())[0]?.toUpperCase() ?? "?";
}

function isCurrentProject(project: GitLabProject, currentProject: AuthSession["project"] | undefined) {
  if (!currentProject) {
    return project.selected;
  }

  return Boolean(
    (project.project_setting_id && project.project_setting_id === currentProject.id) ||
      (project.id && project.id === currentProject.project_id) ||
      (project.path_with_namespace && project.path_with_namespace === currentProject.path_with_namespace)
  );
}

interface ProjectSwitcherProps {
  collapsed?: boolean;
  syncUnsynced?: boolean;
  syncTitle?: string;
}

export function ProjectSwitcher({ collapsed = false, syncUnsynced = false, syncTitle }: ProjectSwitcherProps) {
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
    queryFn: () => listGitLabProjects(),
    enabled: open,
    staleTime: 60_000
  });

  const refreshProjects = useMutation({
    mutationFn: () => listGitLabProjects(true),
    onSuccess: (payload) => {
      queryClient.setQueryData(["gitlab-projects"], payload);
    }
  });

  const activate = useMutation({
    mutationFn: activateGitLabProject,
    onSuccess: (payload) => {
      queryClient.setQueryData<AuthSession>(["auth-session"], (previous) =>
        previous ? { ...previous, ...payload } : previous
      );
      queryClient.setQueryData<{ projects: GitLabProject[] }>(["gitlab-projects"], (previous) => {
        if (!previous?.projects || !payload.project) {
          return previous;
        }

        return {
          projects: previous.projects.map((project) => {
            const selected = isCurrentProject(project, payload.project);

            return {
              ...project,
              selected,
              project_setting_id: selected ? payload.project?.id ?? project.project_setting_id : project.project_setting_id,
              project_access_token_status: selected
                ? payload.project?.project_access_token_status ?? project.project_access_token_status
                : project.project_access_token_status
            };
          })
        };
      });

      projectScopedQueryKeys.forEach((queryKey) => {
        queryClient.invalidateQueries({ queryKey: [queryKey] });
      });

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
  const selectedProjectFromList = projects.data?.projects.find((project) => isCurrentProject(project, currentProject));
  const currentProjectName =
    selectedProjectFromList?.name ||
    projectNameFromPath(currentProject?.path_with_namespace) ||
    currentProject?.name ||
    "Select repository";
  const currentProjectPath = selectedProjectFromList?.path_with_namespace || currentProject?.path_with_namespace || currentProjectName;
  const currentProjectInitial = projectInitial(currentProjectName);
  const triggerTitle = collapsed
    ? `${currentProjectName}${syncUnsynced ? " - 未同步" : ""}`
    : syncUnsynced
      ? syncTitle
      : undefined;

  function selectProject(project: GitLabProject) {
    if (isCurrentProject(project, currentProject)) {
      setOpen(false);
      return;
    }

    activate.mutate(project.id);
  }

  return (
    <div className="project-switcher" ref={wrapperRef}>
      <button
        className={`project-switcher-trigger${open ? " is-open" : ""}${syncUnsynced ? " is-unsynced" : ""}`}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        title={triggerTitle}
        onClick={() => setOpen((value) => !value)}
      >
        <div className="sidebar-logo" aria-hidden="true">{currentProjectInitial}</div>
        <span className="project-switcher-copy">
          <span className="project-switcher-title-row">
            <span className="sidebar-title">{currentProjectName}</span>
            {syncUnsynced && <span className="project-sync-warning" title={syncTitle}>未同步</span>}
          </span>
          <span className="project-switcher-current">{currentProjectPath}</span>
        </span>
      </button>

      {open && (
        <div className="project-switcher-menu" role="menu">
          <div className="project-switcher-menu-header">
            <span>Repositories</span>
            <button
              className="icon-button"
              type="button"
              onClick={() => refreshProjects.mutate()}
              disabled={projects.isFetching || refreshProjects.isPending}
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
            {filteredProjects.map((project) => {
              const selected = isCurrentProject(project, currentProject);
              const tokenStatus = project.project_access_token_status;

              return (
                <button
                  key={project.id}
                  className={`project-switcher-row${selected ? " is-selected" : ""}`}
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
                    {selected && <Check size={14} />}
                    <span className={`repo-token-state ${tokenStatus}`}>
                      {tokenStatus === "configured" ? "PAT set" : "PAT missing"}
                    </span>
                  </span>
                </button>
              );
            })}
          </div>

          {activate.isError && <div className="repo-error">{activate.error.message}</div>}
        </div>
      )}
    </div>
  );
}
