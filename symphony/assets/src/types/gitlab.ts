export interface GitLabSettingsDTO {
  gitlab: {
    gitlab_api_root?: string;
    gitlab_project_ref?: string;
    token_status: "configured" | "missing" | "redacted";
  };
  project: {
    id: string;
    project_id: number | null;
    path_with_namespace: string | null;
    name: string | null;
    web_url: string | null;
    read_only: boolean;
    local_repo_path?: string | null;
    project_access_token_status: "configured" | "missing";
    project_access_token_set_at?: string | null;
  } | null;
}

export interface LocalRepoCandidateDTO {
  path: string;
  git_root: string;
  remote_url: string | null;
  reason: string;
  score: number;
}
