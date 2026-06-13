export interface AuthUser {
  provider: "gitlab";
  issuer?: string;
  gitlab_user_id?: string;
  username: string;
  name: string;
  email?: string | null;
  avatar_url?: string | null;
  profile_url?: string | null;
  access_level: number;
  role: string;
}

export interface AuthSession {
  auth: {
    mode: string;
    loginUrl: string;
    logoutUrl: string;
  };
  user: AuthUser | null;
  permissions: {
    read: boolean;
    write: boolean;
    admin: boolean;
    requiredAccessLevel?: number;
    writeAccessLevel?: number;
    adminAccessLevel?: number;
  };
  project: {
    id?: string;
    project_id?: number | null;
    name?: string;
    path_with_namespace?: string;
    web_url?: string;
    project_access_token_status?: "configured" | "missing";
  } | null;
}

export interface GitLabProject {
  id: number;
  name: string;
  path_with_namespace: string;
  web_url?: string | null;
  visibility?: string | null;
  last_activity_at?: string | null;
  selected: boolean;
  project_setting_id?: string | null;
  project_access_token_status: "configured" | "missing";
}
