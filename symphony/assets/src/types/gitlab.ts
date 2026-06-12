export interface GitLabSettingsDTO {
  gitlab: {
    gitlab_api_root?: string;
    gitlab_project_ref?: string;
    token_status: "configured" | "missing" | "redacted";
  };
  project: {
    project_id: number | null;
    path_with_namespace: string | null;
    name: string | null;
    web_url: string | null;
    read_only: boolean;
  } | null;
}
