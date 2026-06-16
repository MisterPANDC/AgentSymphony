export type AutomationCredentialMode = "project_access_token" | "service_account";
export type CredentialStatus = "configured" | "missing";

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
    automation_credential_mode: AutomationCredentialMode;
    automation_credential_status: CredentialStatus;
    project_access_token_status: CredentialStatus;
    project_access_token_set_at?: string | null;
    service_account_token_status: CredentialStatus;
  } | null;
  serviceAccount: {
    id: string;
    api_root: string;
    service_account_token_status: CredentialStatus;
    service_account_token_set_at?: string | null;
    last_validated_at?: string | null;
    gitlab_user_id?: string | null;
    username?: string | null;
    name?: string | null;
    web_url?: string | null;
  } | null;
}
