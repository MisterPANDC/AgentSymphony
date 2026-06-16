# Symphony GitLab Migration Specification

## 0. Normative Language

The key words `MUST`, `MUST NOT`, `REQUIRED`, `SHOULD`, `SHOULD NOT`, `RECOMMENDED`, `MAY`, and `OPTIONAL` are interpreted as described in RFC 2119.

This document is a normative migration extension. It is not a patch to upstream `SPEC.md`. An implementation MUST read upstream `SPEC.md` for Symphony's scheduler, workspace, workflow-loader, agent-runner, retry, reconciliation, and observability contracts. This document overrides upstream tracker, tracker-state, Linear integration, status surface, and dashboard requirements.

Conflict rule:

1. If upstream `SPEC.md` describes Linear, the implementation MUST replace that requirement with the GitLab requirements in this document.
2. If upstream `SPEC.md` defines orchestration behavior that is independent of Linear, the implementation MUST preserve that behavior.
3. If this document defines a stricter tracker, workflow-state, dashboard, API, persistence, or security rule, the implementation MUST follow this document.


---

## 1. Problem Statement

Symphony currently treats Linear as the tracker integration described by upstream `SPEC.md`. The migration changes Symphony into a GitLab-native service where users sign in with GitLab OAuth/OIDC, choose GitLab projects they can access, store GitLab issue snapshots locally, maintain Symphony-owned workflow state separately from GitLab, and use a high-density dashboard for controlling agents and issue workflow.

A conforming implementation MUST satisfy all of the following goals:

1. **Completely remove Linear at runtime**
   - The runtime MUST NOT call Linear API.
   - The runtime MUST NOT require `LINEAR_API_KEY`.
   - The runtime MUST NOT keep Linear workspace, Linear team, Linear workflow state, Linear project slug, or Linear issue identifiers as live domain concepts.
   - The runtime MUST NOT provide a `LinearAdapter -> GitLabAdapter` compatibility layer as the primary implementation.
   - One-time migration scripts MAY read old Linear-shaped local data, but the final runtime schema and code path MUST be GitLab-native.

2. **Keep the backend in Elixir**
   - The backend MUST remain Elixir/Phoenix/OTP-based.
   - GitLab access MUST be implemented as first-class Elixir modules.
   - The browser frontend MUST NOT receive, store, or call with a GitLab access token.

3. **Use GitLab OAuth/OIDC for multi-user access**
   - The default runtime mode MUST be `gitlab_oidc`.
   - Users MUST sign in through the configured GitLab OAuth/OIDC provider.
   - Symphony MUST list and activate projects from the signed-in user's GitLab project membership.
   - The active project MUST be stored in the user's Symphony session, and read/write/admin API access MUST be scoped to that active project.
   - Symphony MUST NOT implement an independent organization, invitation, password, or team RBAC system for this migration.

4. **Support multiple GitLab projects safely**
   - Symphony MAY persist many GitLab project settings for one GitLab instance.
   - A user MAY switch between GitLab projects they can access without signing out.
   - Per-project data such as automation credential mode, Project Access Token status, issue sync state, unsynced issues, and issue cursors MUST NOT leak across projects.
   - The global Service Account credential MAY be shared by projects on the same configured GitLab API root, but a project MUST opt in by selecting Service Account mode.
   - GitLab issue sync cursors MUST be scoped per `gitlab_project_settings.id`.

5. **Use GitLab REST API as the external issue source**
   - GitLab project issues are the external work item source.
   - GitLab issue title, description, labels, assignees, milestone, due date, open/closed state, and notes/comments are external GitLab facts.
   - Symphony MUST call GitLab REST API under `/api/v4`.
   - Symphony MUST authenticate to GitLab from the server side only.
   - User-initiated GitLab writes MUST use the signed-in user's OAuth access token.
   - Background sync and Agent GitLab writes MUST use the selected project's configured automation credential.

6. **Maintain Symphony workflow state internally**
   - Symphony workflow statuses such as `backlog`, `todo`, `in_progress`, `review`, `merging`, `rework`, `done`, and `canceled` MUST be stored in the Symphony database.
   - Blocker/dependency relationships and issue-level blocked state MUST be stored or derived in the Symphony database separately from workflow status.
   - Dashboard ordering, run state, dispatch state, blocked/operator-input state, project memberships, encrypted token records, and sync cursors MUST be stored in the Symphony database.
   - GitLab paid workflow/blocker/status features MUST NOT be required for the core workflow.

7. **Provide a Linear-like control frontend**
   - The frontend MUST be implemented with TypeScript + React.
   - The frontend MUST provide a high-density issue dashboard, issue detail drawer, internal status controls, blocker editor, Agent control panel, run history, settings, and a dedicated runtime monitoring area.
   - The frontend MUST replicate the control efficiency of Linear-style dashboards without copying Linear trademarks, proprietary icons, brand assets, or protected visual details.

8. **Provide a dedicated Run Monitor area**
   - The new frontend MUST contain a top-level running/observability area named **Run Monitor**.
   - Run Monitor MUST include the information exposed by the original Elixir prototype Web dashboard: runtime state, blocked/operator-input state, JSON operational debugging, HTTP observability entrypoint, tracker-provided issue links, and manual refresh.
   - Run Monitor MUST be part of the new TypeScript + React frontend, not a separate legacy LiveView dashboard.

---

## 2. Non-goals

A conforming implementation MUST NOT implement the following in this migration:

- Linear runtime compatibility mode.
- Linear API client.
- Linear webhook receiver.
- GitLab webhook receiver.
- GitLab project hook installer.
- A generic issue-tracker abstraction that keeps both Linear and GitLab providers alive.
- Local single-project runtime configured only by `GITLAB_TOKEN`.
- Password login, user invitations, organizations, or team RBAC separate from GitLab.
- Fine-grained issue or note visibility rules beyond selected-project GitLab membership.
- Cross-GitLab-instance tenancy in one running Symphony process.
- GitLab GraphQL as the primary tracker integration.
- GitLab Premium/Ultimate-only issue blocking as a required feature.
- GitLab issue boards as the workflow source of truth.
- GitLab labels as the workflow source of truth.
- Browser-side GitLab API calls.
- Browser-side raw OAuth token, Project Access Token, or Service Account token storage.
- A separate legacy LiveView dashboard as the primary UI.

---

## 3. Authentication and Project Access

### 3.1 GitLab OAuth/OIDC mode

The default runtime mode is `gitlab_oidc`. Unsupported auth modes MUST fail explicitly.

Required behavior:

- Symphony MUST use GitLab OAuth/OIDC authorization-code login.
- The redirect URI MUST be `${SYMPHONY_PUBLIC_URL}/auth/gitlab/callback`.
- The configured issuer/public URL MUST be normalized without trailing slashes.
- Default OAuth/OIDC scopes MUST be `openid profile email api`.
- The session MUST identify the GitLab identity, selected project, effective access level, and last membership check time.
- GitLab identity records MUST be unique by `(issuer, gitlab_user_id)` and `(issuer, sub)`.
- OAuth access and refresh tokens MUST be encrypted at rest.
- OAuth access tokens MUST be refreshed before expiry when a refresh token is available.

### 3.2 Project selection and membership

After login, Symphony MUST list projects through GitLab REST using the signed-in user's OAuth token:

```text
GET /projects?membership=true&simple=true&order_by=last_activity_at&sort=desc
```

When a user activates a project, Symphony MUST:

1. Upsert a `gitlab_project_settings` row for the GitLab project.
2. Validate the user's membership with `GET /projects/:id/members/all/:user_id`.
3. Persist the membership in `gitlab_project_memberships`.
4. Store the active `project_setting_id` and effective `access_level` in the session.
5. Reset that project's issue sync cursor so newly selected project data can be fetched.

The permission model MUST use GitLab numeric `access_level` as the durable authorization signal. Role names such as Reporter, Developer, and Maintainer are display labels derived from that number.

Default thresholds:

```env
SYMPHONY_AUTH_MIN_ACCESS_LEVEL=20
SYMPHONY_AUTH_WRITE_ACCESS_LEVEL=30
SYMPHONY_AUTH_ADMIN_ACCESS_LEVEL=40
```

Meaning:

- `read`: GitLab Reporter (`20`) or above.
- `write`: GitLab Developer (`30`) or above.
- `admin`: GitLab Maintainer (`40`) or above.

Membership checks MAY be cached briefly, but protected API requests MUST refresh stale membership and drop the session if the user no longer has enough GitLab access.

### 3.3 Automation Credentials

Each selected project needs an automation credential for background and Agent operations. The default mode is `project_access_token`.

Required behavior:

- Admin users MAY set the selected project's Project Access Token from `/settings/gitlab`.
- Admin users MAY set one global Service Account token for the configured GitLab API root from `/settings/gitlab`.
- Each project MUST store its active automation credential mode as either `project_access_token` or `service_account`.
- A newly selected project MUST default to `project_access_token`.
- Saving a Service Account token from one project MUST store it globally for the GitLab API root and warn the admin that other projects on that host may opt in.
- The backend MUST validate the token before saving it.
- Tokens MUST be encrypted at rest.
- Tokens MUST be returned to the frontend only as `configured` or `missing`.
- Background issue/note sync MUST use the selected automation credential.
- Agent-created GitLab notes, issue note attachments, issue close/reopen, and follow-up issue creation MUST use the selected automation credential.
- User-initiated issue edits, comments, and comment attachments from the UI MUST use the signed-in user's OAuth token.
- If a selected project has no configured credential for its selected mode, project browsing MAY work from already synced data, but sync and Agent GitLab writes MUST fail clearly with `project_access_token_missing` or `service_account_token_missing`.

This boundary is intentional: automation credentials give background sync and Agents a stable non-user credential without borrowing one user's OAuth token. Project Access Tokens SHOULD be scoped to the minimum GitLab permissions the project needs. Service Account tokens SHOULD be owned by a dedicated GitLab Service Account, limited to only the projects that need Symphony automation, and rotated independently from user OAuth credentials.

### 3.4 HTTP runtime

The main runtime command MUST keep the original local-run ergonomics:

```bash
./bin/symphony ./WORKFLOW.md --port 4000
```

When `--port` is present, Symphony MUST start the Phoenix HTTP service, serve the React control frontend, expose the JSON API, and expose Run Monitor.

The implementation SHOULD bind to loopback by default:

```env
SYMPHONY_BIND_HOST=127.0.0.1
```

If the service is exposed beyond loopback, `SYMPHONY_PUBLIC_URL`, `SYMPHONY_SESSION_SECRET`, `SYMPHONY_TOKEN_ENCRYPTION_SECRET`, and GitLab OAuth redirect URI configuration MUST match the externally reachable URL.

---

## 4. Configuration

### 4.1 Required OAuth/OIDC configuration

The implementation MUST support `.env.local` at the Elixir app root and load it in development and local runtime mode. `.env.local` MUST be listed in `.gitignore`.

Minimum configuration:

```env
SYMPHONY_BIND_HOST=127.0.0.1
SYMPHONY_PORT=4000
SYMPHONY_PUBLIC_URL=http://127.0.0.1:4000
SYMPHONY_SESSION_SECRET=replace-with-a-stable-random-secret-at-least-64-bytes
SYMPHONY_TOKEN_ENCRYPTION_SECRET=replace-with-a-stable-random-secret

SYMPHONY_AUTH_MODE=gitlab_oidc
GITLAB_BASE_URL=https://gitlab.example.com
GITLAB_OIDC_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITLAB_OIDC_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SYMPHONY_DATABASE_URL=postgres://postgres:postgres@localhost:5432/symphony_dev
```

`GITLAB_OIDC_ISSUER` MAY be used instead of `GITLAB_BASE_URL` when the OAuth/OIDC issuer differs from the public GitLab base URL. If both are present, `GITLAB_OIDC_ISSUER` is the issuer used for discovery and ID token validation.

### 4.2 Permission configuration

Permission thresholds MUST be configurable:

```env
SYMPHONY_AUTH_MIN_ACCESS_LEVEL=20
SYMPHONY_AUTH_WRITE_ACCESS_LEVEL=30
SYMPHONY_AUTH_ADMIN_ACCESS_LEVEL=40
```

Defaults MUST mean Reporter can read, Developer can write, and Maintainer can administer Symphony project settings.

### 4.3 Token source and storage

The implementation MUST NOT require or use `GITLAB_TOKEN` for the normal runtime.

Token rules:

- OAuth access/refresh tokens are obtained through GitLab OAuth/OIDC and encrypted in `gitlab_oauth_tokens`.
- Project Access Tokens are entered per selected project in Settings and encrypted in `gitlab_project_settings`.
- Service Account tokens are entered once per GitLab API root in Settings and encrypted in `gitlab_service_account_credentials`.
- Each project stores its selected automation credential mode in `gitlab_project_settings.automation_credential_mode`.
- The browser frontend MUST NOT receive raw OAuth tokens, Project Access Tokens, or Service Account tokens.
- Tokens MUST NOT appear in frontend source, frontend build output, browser local storage, browser session storage, IndexedDB, URL query parameters, rendered HTML, logs, Run Monitor DTOs, or error responses.
- Token DTOs MUST expose only status values such as `configured`, `missing`, or validation errors.

### 4.4 Runtime configuration keys

The implementation MUST support these keys:

```env
# Auth
SYMPHONY_AUTH_MODE=gitlab_oidc
GITLAB_BASE_URL=https://gitlab.example.com
GITLAB_OIDC_ISSUER=https://gitlab.example.com
GITLAB_OIDC_CLIENT_ID=...
GITLAB_OIDC_CLIENT_SECRET=...
GITLAB_OIDC_SCOPES=openid profile email api
SYMPHONY_PUBLIC_URL=http://127.0.0.1:4000
SYMPHONY_SESSION_SECRET=...
SYMPHONY_TOKEN_ENCRYPTION_SECRET=...

# Authorization thresholds
SYMPHONY_AUTH_MIN_ACCESS_LEVEL=20
SYMPHONY_AUTH_WRITE_ACCESS_LEVEL=30
SYMPHONY_AUTH_ADMIN_ACCESS_LEVEL=40

# Persistence
SYMPHONY_DATABASE_URL=postgres://postgres:postgres@localhost:5432/symphony_dev

# Symphony local HTTP
SYMPHONY_BIND_HOST=127.0.0.1
SYMPHONY_PORT=4000

# Sync
SYMPHONY_SYNC_INTERVAL_MS=60000
SYMPHONY_SYNC_PAGE_SIZE=100
SYMPHONY_SYNC_CURSOR_OVERLAP_SECONDS=120

# Workspace / Agent
SYMPHONY_WORKSPACE_ROOT=~/code/workspaces
SYMPHONY_LOGS_ROOT=./log
CODEX_COMMAND="codex app-server"
```

PostgreSQL MUST be the default persistence backend. The JSON store MAY remain available only when explicitly selected for tests or one-off local tooling.

### 4.5 Settings validation

The backend MUST expose GitLab settings validation for the selected project:

- `GET /api/settings/gitlab` MUST return selected project metadata and token status.
- `POST /api/settings/gitlab/test` MUST validate the selected project's active automation credential.
- `PUT /api/settings/gitlab/project-token` MUST validate, encrypt, and save a new Project Access Token.
- `PUT /api/settings/gitlab/service-account-token` MUST validate, encrypt, and save a GitLab API root-scoped Service Account token.
- `PUT /api/settings/gitlab/credential-mode` MUST set the selected project's active automation credential mode.
- All settings responses MUST redact secrets.

---

## 5. Architecture

### 5.1 Target architecture

```text
┌────────────────────────────────────────────────────────────────┐
│                   TypeScript + React Frontend                  │
│                                                                │
│  Issues / Board / Detail Drawer / Agent Panel / Run Monitor    │
│  Settings / Command Palette / Sync Status / GitLab Linkouts    │
└──────────────────────────────┬─────────────────────────────────┘
                               │ Symphony JSON API + WS/SSE
┌──────────────────────────────▼─────────────────────────────────┐
│                    Elixir / Phoenix Backend                    │
│                                                                │
│  Symphony.GitLab.Client       -> GitLab REST API               │
│  Symphony.GitLab.Config       -> selected project config       │
│  Symphony.Auth                -> GitLab OIDC, sessions, tokens │
│  Symphony.Tracker             -> GitLab issue read model       │
│  Symphony.Workflow            -> internal status/blockers      │
│  Symphony.Sync.Poller         -> polling-only GitLab sync      │
│  Symphony.Agent               -> existing agent execution      │
│  Symphony.Monitor             -> runtime observability state   │
│  Phoenix.PubSub               -> UI live updates               │
│  Bandit                       -> local HTTP server             │
└──────────────────────────────┬─────────────────────────────────┘
                               │ Ecto
┌──────────────────────────────▼─────────────────────────────────┐
│                           PostgreSQL                           │
│                                                                │
│  gitlab_identities / gitlab_oauth_tokens / memberships         │
│  gitlab_project_settings / gitlab_issues / gitlab_issue_notes  │
│  issue_workflow_states / issue_dependencies / issue_events     │
│  agent_runs / agent_run_events / runtime_blocks / sync_cursors │
└──────────────────────────────┬─────────────────────────────────┘
                               │ HTTPS or local HTTP
┌──────────────────────────────▼─────────────────────────────────┐
│                         GitLab REST API                        │
│                                                                │
│  /.well-known/openid-configuration and /oauth/token            │
│  /api/v4/projects                                              │
│  /api/v4/projects/:id                                          │
│  /api/v4/projects/:id/members/all/:user_id                     │
│  /api/v4/projects/:id/issues                                   │
│  /api/v4/projects/:id/issues/:issue_iid                        │
│  /api/v4/projects/:id/issues/:issue_iid/notes                  │
└────────────────────────────────────────────────────────────────┘
```

### 5.2 Polling-only sync

GitLab ingestion MUST be polling-only in this migration.

The implementation MUST NOT:

- Create GitLab project hooks.
- Expose a GitLab event receiver.
- Accept signed GitLab event callbacks.
- Store GitLab event delivery records.
- Depend on external network reachability from GitLab to the local Symphony process.

The sync system MUST support:

- Startup full sync.
- Periodic incremental sync.
- Manual sync from Run Monitor and Settings.
- Cursor overlap to avoid missing updates around clock boundaries.
- Retry with backoff on network or rate-limit failures.

### 5.3 Fact source boundaries

| Data type | Source of truth | Required behavior |
|---|---|---|
| User identity | GitLab OIDC | Store issuer, GitLab user id, username, profile fields, and raw claims. |
| User project access | GitLab membership | Store effective `access_level`; derive display role names from GitLab's numeric value. |
| Project identity | GitLab | Store GitLab project `id`, `path_with_namespace`, `web_url`, and API root after activation or validation. |
| Issue identity | GitLab | Store GitLab global `id` and project-local `iid`; use `iid` for issue endpoint calls. |
| Title / description | GitLab | Sync into read model; update through GitLab API when edited from Symphony. |
| Labels / assignees / milestone / due date | GitLab | Sync and display; do not use as workflow truth. |
| Open / closed state | GitLab | Sync and display; closed issues are not dispatch candidates. |
| Notes/comments | GitLab | Sync issue notes; user comments use user OAuth, Agent comments use the selected automation credential. |
| Workflow status | Symphony DB | Store and mutate internally. |
| Blocker/dependency | Symphony DB | Store and mutate internally. |
| Agent run state | Symphony DB | Store current and historical runs internally. |
| Runtime blocked/operator-input state | Symphony DB + runtime process state | Persist enough to survive restart; expose in Run Monitor. |
| Dashboard rank/order/views | Symphony DB | Store locally. |
| Sync cursors/errors | Symphony DB | Store locally; issue cursors are per project and exposed in Settings + Run Monitor. |
| OAuth and automation tokens | Symphony DB encrypted fields | Never expose raw token values to browser DTOs, logs, or monitor APIs. |

---

## 6. GitLab REST client

### 6.1 Module

The implementation MUST provide:

```text
lib/symphony/gitlab/client.ex
lib/symphony/gitlab/config.ex
lib/symphony/gitlab/issue_mapper.ex
lib/symphony/gitlab/note_mapper.ex
```

The client MUST expose typed Elixir functions for required operations:

```elixir
get_project(config)
get_project_by_id(config, project_id)
list_user_projects(config, params)
list_project_issues(config, params)
get_project_issue(config, issue_iid)
create_project_issue(config, attrs)
update_project_issue(config, issue_iid, attrs)
list_issue_notes(config, issue_iid, params)
list_issue_discussions(config, issue_iid, params)
create_issue_note(config, issue_iid, body)
create_issue_discussion_note(config, issue_iid, discussion_id, body)
```

Raw GitLab payload handling MUST be contained inside GitLab modules and mapper modules. Other contexts MUST consume internal structs or schemas.

### 6.2 API root and project ref

The client MUST build URLs under:

```text
{gitlab_base_url}/api/v4
```

For selected-project operations, the project identifier in path parameters MUST be either:

- Numeric project ID, or
- URL-encoded namespace/project path.

When a namespace path such as `my-group/my-project` is used, the client MUST URL-encode `/` as `%2F` before building project API paths.

### 6.3 Authentication

The client MUST support both GitLab auth styles used by Symphony:

```text
PRIVATE-TOKEN: <redacted>
Authorization: Bearer <redacted>
```

Automation credential calls MUST use `PRIVATE-TOKEN`. Signed-in user calls MUST use `Authorization: Bearer`.

The client MUST redact token values from:

- Logs.
- Error messages.
- Run Monitor API responses.
- Frontend DTOs.
- Exception reports.
- Test snapshots.

### 6.4 `id` vs `iid`

The client and database MUST distinguish:

- GitLab issue global `id`.
- GitLab project-local issue `iid`.

Issue endpoints MUST use `issue_iid`, not global issue `id`:

```text
GET /projects/:id/issues/:issue_iid
GET /projects/:id/issues/:issue_iid/notes
GET /projects/:id/issues/:issue_iid/discussions
POST /projects/:id/issues/:issue_iid/notes
POST /projects/:id/issues/:issue_iid/discussions/:discussion_id/notes
```

### 6.5 Pagination

The client MUST handle GitLab pagination.

Required behavior:

- Default `per_page` MUST be configurable and default to `100`.
- The client MUST follow pagination response headers when present.
- The client MUST stop only after the final page.
- The client MUST return accumulated results or stream page results to the sync process.
- Pagination behavior MUST be covered by tests using fake Link headers.

### 6.6 Error handling

The client MUST normalize errors into tagged results:

```elixir
{:ok, value}
{:error, %Symphony.GitLab.Error{type: type, status: status, message: message, retry_after: retry_after}}
```

Required error types:

```elixir
:unauthorized
:forbidden
:not_found
:rate_limited
:validation_error
:network_error
:server_error
:invalid_config
:unexpected_response
```

The client MUST treat `401` and `403` as configuration/auth failures visible in Settings and Run Monitor. The sync worker MUST not spin aggressively on these failures.

---

## 7. Database schema

### 7.1 `gitlab_project_settings`

Stores GitLab projects that have been activated in Symphony.

Required fields:

```text
id uuid primary key
api_root text not null
project_ref text not null
project_id bigint
path_with_namespace text
name text
web_url text
visibility text
last_validated_at utc_datetime_usec
last_validation_error text
read_only boolean not null default false
automation_credential_mode text not null default 'project_access_token'
encrypted_project_access_token text
project_access_token_set_by_identity_id uuid
project_access_token_set_at utc_datetime_usec
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraints:

```text
unique(api_root, project_id) where project_id is not null
unique(api_root, project_ref)
```

Project Access Tokens MAY be stored in this table only as encrypted values. API responses MUST expose only `project_access_token_status`, `service_account_token_status`, `automation_credential_mode`, and `automation_credential_status`.

### 7.1.1 GitLab Service Account credentials

`gitlab_service_account_credentials` stores one encrypted Service Account token per GitLab API root.

```text
id uuid primary key
api_root text not null
encrypted_service_account_token text
service_account_token_set_by_identity_id uuid
service_account_token_set_at utc_datetime_usec
last_validated_at utc_datetime_usec
last_validation_error text
gitlab_user_id text
username text
name text
web_url text
scopes text[] not null default []
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraints:

```text
unique(api_root)
```

Service Account tokens MAY be stored in this table only as encrypted values. API responses MUST expose only status and public Service Account identity metadata.

### 7.2 GitLab auth tables

`gitlab_identities` stores signed-in GitLab users.

Required fields:

```text
id uuid primary key
issuer text not null
gitlab_user_id text not null
sub text not null
username text not null
name text
email text
avatar_url text
profile_url text
raw_claims jsonb not null default '{}'
last_login_at utc_datetime_usec not null
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraints:

```text
unique(issuer, gitlab_user_id)
unique(issuer, sub)
```

`gitlab_oauth_tokens` stores encrypted OAuth tokens per identity.

Required fields:

```text
id uuid primary key
identity_id uuid not null
encrypted_access_token text not null
encrypted_refresh_token text
scopes text[] not null default '{}'
token_type text
expires_at utc_datetime_usec
last_refreshed_at utc_datetime_usec
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraint:

```text
unique(identity_id)
```

`gitlab_project_memberships` stores the latest GitLab membership check per identity/project.

Required fields:

```text
id uuid primary key
identity_id uuid not null
gitlab_project_setting_id uuid not null
gitlab_user_id text not null
username text not null
name text
access_level integer not null
expires_at date
state text
last_checked_at utc_datetime_usec not null
raw_gitlab jsonb not null default '{}'
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraint:

```text
unique(identity_id, gitlab_project_setting_id)
```

The schema MUST NOT persist role strings as the authorization source; role names are derived from `access_level`.

### 7.3 `gitlab_issues`

Required fields:

```text
id uuid primary key
gitlab_project_setting_id uuid not null
gitlab_issue_id bigint not null
gitlab_project_id bigint not null
iid integer not null
web_url text not null
title text not null
description text
description_preview text
gitlab_state text not null
labels jsonb not null default '[]'
assignees jsonb not null default '[]'
author jsonb
milestone jsonb
due_date date
confidential boolean not null default false
gitlab_created_at utc_datetime_usec
gitlab_updated_at utc_datetime_usec
closed_at utc_datetime_usec
last_synced_at utc_datetime_usec
raw_gitlab jsonb
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraints:

```text
unique(gitlab_project_setting_id, iid)
unique(gitlab_project_setting_id, gitlab_issue_id)
```

### 7.4 `gitlab_issue_notes`

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid not null
note_id bigint not null
discussion_id text
discussion_reply boolean not null default false
discussion_individual_note boolean not null default false
discussion_position integer
body text not null
author jsonb
system boolean not null default false
internal boolean not null default false
resolvable boolean not null default false
gitlab_created_at utc_datetime_usec
gitlab_updated_at utc_datetime_usec
raw_gitlab jsonb
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraint:

```text
unique(gitlab_issue_id, note_id)
```

### 7.5 `issue_workflow_states`

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid not null unique
status text not null
priority text not null default 'none'
rank numeric
claimed_by text
claimed_at utc_datetime_usec
last_transition_at utc_datetime_usec
last_transition_reason text
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Allowed `status` values:

```text
backlog
todo
in_progress
review
merging
rework
done
canceled
```

Allowed `priority` values:

```text
none
low
medium
high
urgent
```

### 7.6 `issue_dependencies`

Required fields:

```text
id uuid primary key
blocked_issue_id uuid not null
blocking_issue_id uuid not null
created_by text not null default 'system'
reason text
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraints:

```text
unique(blocked_issue_id, blocking_issue_id)
check(blocked_issue_id != blocking_issue_id)
```

The implementation MUST reject dependency cycles.

### 7.7 `issue_events`

Stores local state changes and GitLab sync observations.

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid
event_type text not null
source text not null
actor text
payload jsonb not null default '{}'
run_id uuid
inserted_at utc_datetime_usec
```

Allowed `source` values:

```text
gitlab_sync
user_ui
agent
system
```

### 7.8 `sync_cursors`

Required fields:

```text
id uuid primary key
source text not null
cursor_name text not null
cursor_value text
last_success_at utc_datetime_usec
last_attempt_at utc_datetime_usec
last_error text
last_error_at utc_datetime_usec
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Required constraint:

```text
unique(source, cursor_name)
```

Required cursor names:

```text
gitlab_issues_updated_after:<gitlab_project_setting_id>
gitlab_notes_last_full_sync_at
```

The legacy/global `gitlab_issues_updated_after` cursor MAY exist only for aggregate errors or migration/reset compatibility. Incremental issue sync MUST read and update the project-scoped cursor.

### 7.9 `agent_runs`

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid not null
run_number integer not null
status text not null
mode text not null default 'workflow'
workspace_path text
codex_thread_id text
started_at utc_datetime_usec
finished_at utc_datetime_usec
last_heartbeat_at utc_datetime_usec
exit_reason text
error_message text
blocked_reason text
needs_operator_input boolean not null default false
summary text
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Allowed `status` values:

```text
queued
starting
running
blocked
succeeded
failed
canceled
stale
```

Required constraint:

```text
unique(gitlab_issue_id, run_number)
```

### 7.10 `agent_run_events`

Required fields:

```text
id uuid primary key
agent_run_id uuid not null
event_type text not null
message text
payload jsonb not null default '{}'
inserted_at utc_datetime_usec
```

Required event types:

```text
queued
workspace_created
codex_started
turn_started
turn_finished
comment_posted
status_changed
blocked
operator_input_required
succeeded
failed
canceled
heartbeat
```

### 7.11 `runtime_blocks`

Persists runtime blocked/operator-input state that the original Elixir prototype exposed only as runtime state.

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid not null
agent_run_id uuid
block_type text not null
message text
payload jsonb not null default '{}'
resolved_at utc_datetime_usec
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

Allowed `block_type` values:

```text
operator_input
approval_required
mcp_elicitation
sandbox_rejection
external_failure
blocked_by_dependency
```

A block with `resolved_at is null` MUST appear in Run Monitor.

---

## 8. Sync behavior

### 8.1 Startup sync

On startup, the sync process MUST:

1. Load persisted GitLab project settings.
2. Select projects whose active automation credential status is `configured`.
3. For each configured project, decrypt the selected Project Access Token or Service Account token server-side.
4. Validate the GitLab API root and project with the selected automation credential.
5. Upsert refreshed `gitlab_project_settings` metadata.
6. Backfill old issue records that are missing `gitlab_project_setting_id` when the project can be identified.
7. Fetch project issues with `state=all`.
8. Page through all results.
9. Upsert `gitlab_issues`.
10. Create missing `issue_workflow_states` with default status `backlog`.
11. Record sync events.
12. Update that project's `sync_cursors` entry.
13. Broadcast UI updates through PubSub.

If no project has a configured active automation credential, sync MUST fail clearly with `project_access_token_missing` or `service_account_token_missing` and MUST NOT attempt GitLab issue sync with a user OAuth token.

### 8.2 Incremental issue sync

The sync process MUST run at `SYMPHONY_SYNC_INTERVAL_MS` and iterate over all projects with configured active automation credentials.

Incremental sync MUST use each project's own issue cursor with `updated_after` and cursor overlap:

```text
updated_after = last_success_at - SYMPHONY_SYNC_CURSOR_OVERLAP_SECONDS
```

The query MUST include:

```text
state=all
order_by=updated_at
sort=asc
per_page=<configured page size>
updated_after=<iso8601 datetime>
```

The upsert logic MUST be idempotent.

When a project is activated, its Project Access Token is updated, its Service Account token is updated, or its credential mode changes, Symphony MUST reset that project's issue cursor to avoid hiding local records whose previous incremental cursor moved past GitLab's `updated_at`.

### 8.3 Notes sync

Notes sync MUST support these paths:

1. Issue detail sync: when the user opens an issue detail drawer, fetch notes for that issue using the signed-in user's OAuth token.
2. Agent/tool sync: when an Agent needs current notes, fetch notes for the issue using the selected project's active automation credential.
3. Periodic recent sync MAY fetch notes for recently changed issues if implemented.

The implementation MUST use GitLab discussions for read/reply semantics and notes for top-level note creation:

```text
GET /projects/:id/issues/:issue_iid/discussions
POST /projects/:id/issues/:issue_iid/notes
POST /projects/:id/issues/:issue_iid/discussions/:discussion_id/notes
POST /projects/:id/uploads
GET /projects/:id/uploads/:secret/:filename
DELETE /projects/:id/uploads/:secret/:filename
```

User-created comments MUST use the signed-in user's OAuth token. User-created replies MUST be posted to the existing GitLab discussion id so they remain threaded in GitLab and Symphony. Agent-created top-level comments MUST be posted through `create_issue_note/3` with the selected project's active automation credential and then inserted into local `gitlab_issue_notes` after GitLab returns the created note.

Comment attachments MUST follow GitLab's Markdown upload model:

1. Symphony MUST upload files to GitLab project Markdown uploads only as part of a comment submission, not when the user merely selects or drags files into the composer.
2. Symphony MUST append the Markdown returned by GitLab to the note body before creating the GitLab note.
3. Symphony MUST rewrite GitLab upload Markdown to a Symphony-authenticated proxy URL before storing or returning user-created note bodies.
4. If upload succeeds but GitLab deterministically rejects note creation with a 4xx response, Symphony MUST best-effort delete the just-created upload to avoid orphan files.
5. If note creation fails with an ambiguous network, rate-limit, or server error, Symphony MUST NOT delete the upload automatically because the note may have been created even though Symphony did not receive the response.

Attachment download MUST use a Symphony-authenticated proxy. The proxy MUST require normal issue read access, use the signed-in user's OAuth token to fetch the GitLab upload, and only serve uploads referenced by the issue description or notes already visible through Symphony. Symphony SHOULD NOT maintain a separate long-lived attachment object store unless a later archival requirement explicitly needs it.

### 8.4 User-created issues from UI

The frontend MUST allow users with write access to create GitLab issues from:

1. The Issues view.
2. Each workflow status column in the Board view.

The backend MUST expose:

```text
POST /api/issues
```

User-created issues MUST use the signed-in user's OAuth token and MUST be
scoped to the current selected GitLab project. The browser frontend MUST NOT
call GitLab directly.

The UI creation request MUST require:

```text
title
workflow_status
```

The request MAY include:

```text
description
labels
assignee_ids
milestone_id
due_date
confidential
```

The requested `workflow_status` MUST be one of the user-creatable initial statuses:

```text
backlog
todo
```

When the user creates from the Issues view, the dialog MUST include a workflow
status selector restricted to the user-creatable initial statuses. When the user
creates from a Board column whose status is user-creatable, the new issue MUST be
initialized to that column's workflow status. Board columns for terminal or
workflow-controlled statuses, including `canceled`, MUST NOT offer direct
creation into that column. The backend MAY reach the requested workflow status by
applying valid user dashboard transitions after GitLab returns the created issue,
and it MUST record those transitions in `issue_events`.

User-created issues MUST NOT create follow-up source links, dependency edges, or
current-issue notes unless the user explicitly performs those actions later.

### 8.5 Agent-created follow-up issues

The GitLab migration MUST preserve the upstream workflow behavior where an
Agent can capture out-of-scope follow-up work without expanding the current
issue scope.

Agent-created follow-up issues MUST be created through
`create_project_issue/2`, not through arbitrary GitLab REST calls. The
operation MUST be scoped to the current selected GitLab project.

The implementation MUST use:

```text
POST /projects/:id/issues
```

The follow-up creation request MUST require:

```text
title
description
acceptance_criteria
```

The request MAY include:

```text
labels
assignee_ids
milestone_id
due_date
confidential
related_to_current_issue
blocked_by_current_issue
```

`blocked_by_current_issue` implies `related_to_current_issue`.

After GitLab returns the created issue, Symphony MUST:

1. Upsert the returned issue into `gitlab_issues`.
2. Create its `issue_workflow_states` row with default status `backlog`.
3. Record an `issue_events` row with source `agent`, actor `agent`, and a
   payload containing the current issue id, created issue iid, and relationship
   flags.
4. Ensure the created issue description contains a link back to the current
   GitLab issue when `related_to_current_issue` is true.
5. Post a note on the current issue linking to the follow-up issue when
   `related_to_current_issue` is true.
6. Create local `issue_dependencies` when `blocked_by_current_issue` is true.
7. Return the created issue DTO to the Agent tool caller.

If GitLab issue creation succeeds but local persistence fails, the
implementation MUST record the persistence error in Run Monitor and retry local
upsert on the next sync. It MUST NOT silently drop the created issue.

### 8.6 Manual refresh

The backend MUST expose a manual refresh endpoint used by Run Monitor and Settings:

```text
POST /api/sync/refresh
```

Manual refresh MUST enqueue or execute a sync job. It MUST NOT require or simulate external GitLab events.

### 8.7 Conflict behavior

When GitLab fields change externally:

- GitLab title/description/labels/assignees/milestone/due date/open-closed state MUST update local read model.
- Internal workflow status MUST remain unchanged unless an explicit Symphony rule changes it.
- If a GitLab issue is closed externally, the issue MUST stop being an Agent dispatch candidate.
- If a GitLab issue is reopened externally while its internal workflow status is
  `canceled`, Symphony MUST move the issue back to `backlog` and add the
  `reopen` label.
- If a GitLab issue is reopened externally from any other internal workflow
  status, the issue MAY re-enter dispatch only if its internal workflow status is
  an active candidate status.

---

## 9. Internal workflow model

### 9.1 Status meanings

| Status | Meaning | Dispatch candidate |
|---|---|---|
| `backlog` | Needs human analysis, scoping, decomposition, or acceptance before Agent dispatch. This includes newly synced issues and work returned for re-analysis. | No |
| `todo` | Ready for Agent work. | Yes |
| `in_progress` | Implementation actively underway. | Yes |
| `review` | Implementation is validated and waiting for human review or merge approval. | No |
| `merging` | Human approved the change; Agent should run the merge/land flow. | Yes |
| `rework` | Reviewer requested changes; Agent should restart the implementation/review loop. | Yes |
| `done` | Merge is complete and work is terminal. | No |
| `canceled` | Work is intentionally stopped. It may be returned to `backlog` for re-analysis or `todo` when a human explicitly restores it as ready. | No |

### 9.2 Status transitions

The implementation MUST centralize transitions in `Symphony.Workflow`.

Required transitions:

```text
backlog -> todo
todo -> backlog
todo -> in_progress
in_progress -> review
in_progress -> todo
in_progress -> backlog
review -> todo
review -> merging
review -> rework
review -> backlog
merging -> done
merging -> review
rework -> in_progress
rework -> review
rework -> backlog
canceled -> backlog
canceled -> todo
any non-terminal -> canceled
```

User-initiated dashboard transitions MUST be a restricted subset of the full workflow graph:

```text
backlog -> todo
todo -> backlog
todo -> canceled
in_progress -> backlog
in_progress -> canceled
review -> backlog
review -> merging
review -> rework
review -> canceled
rework -> backlog
rework -> canceled
canceled -> backlog
canceled -> todo
any non-terminal -> canceled
```

Transitions such as `todo -> in_progress`, `in_progress -> review`, and
`merging -> done` are controlled by Symphony, Agent tools, or workflow rules, not
by ordinary dashboard status selection.

If a dashboard transition moves an issue with a running agent into a
non-dispatch-candidate status such as `backlog`, `review`, or `canceled`, the UI
MUST ask for explicit confirmation and the server MUST stop or release the
running agent run.

Terminal statuses:

```text
done
```

`canceled` is a stopped state, not a dispatch candidate. When an issue enters
`canceled`, Symphony SHOULD close the GitLab issue. A canceled issue may be
restored through `canceled -> backlog` for re-analysis or `canceled -> todo` when
a human explicitly marks it ready again. If the corresponding GitLab issue is
closed, either restore path MUST reopen it and add the `reopen` label.

The implementation MUST record each transition in `issue_events`.

### 9.3 Blocker logic

An issue is blocked when either condition is true:

1. It has unresolved dependencies where at least one blocking issue is not in `done`.
2. It has an unresolved `runtime_blocks` row, or its active `agent_runs.status` is `blocked`.

Blocked is issue/run state, not a workflow stage. A blocked issue MUST keep its
current `issue_workflow_states.status` such as `todo`, `in_progress`,
`merging`, or `rework`, and the dashboard MUST render the block as a
badge/filter or Run Monitor row rather than moving the issue into a separate
workflow column.

Blocked issues MUST NOT be dispatched.

The blocker editor MUST:

- Add dependency edges.
- Remove dependency edges.
- Show blocking issue status.
- Reject self-dependencies.
- Reject cycles.
- Record changes in `issue_events`.

### 9.4 GitLab labels and internal status

GitLab labels MUST NOT be the workflow source of truth.

The implementation MAY mirror internal status to a GitLab label only when explicitly enabled in settings. If mirroring is enabled, local database status remains authoritative and label sync is best-effort. Label sync failures MUST NOT corrupt workflow status.

`reopen` is a lightweight GitLab-visible marker for issues restored
after cancellation. It MUST NOT be treated as a workflow status and MUST NOT be
used as an Agent dispatch condition. The marker SHOULD be added when GitLab
externally reopens a canceled issue or when Symphony restores a canceled issue to
`backlog` or `todo`.

---

## 10. Agent runner migration

### 10.1 Issue dispatch query

The dispatcher MUST select work from the internal database.

A dispatch candidate MUST satisfy:

```text
gitlab_issues.gitlab_state = "opened"
issue_workflow_states.status in ["todo", "in_progress", "merging", "rework"]
no unresolved dependency blocker
no unresolved runtime block for the same issue
no active agent run for the same issue
required labels satisfied when configured
max_concurrent_agents not exceeded
```

The dispatcher MUST NOT query Linear.

### 10.2 Claiming

When an issue is claimed:

1. If the issue is in `todo`, `issue_workflow_states.status` MUST transition to
   `in_progress`.
2. If the issue is already in a dispatchable execution state such as
   `in_progress`, `merging`, or `rework`, the claim MUST preserve the current
   workflow status unless an explicit workflow rule or Agent tool transition
   changes it.
3. `claimed_by` MUST be set to the runner identity.
4. A new `agent_runs` row MUST be created.
5. An `agent_run_events` row with `queued` or `starting` MUST be created.
6. Run Monitor MUST update through PubSub.

The implementation MUST NOT expose a per-issue manual run path that creates a
queued run outside the scheduler's dispatch selection. Ready work enters
execution by becoming a dispatch candidate and then being claimed by the
periodic scheduler or an immediate scheduler refresh.

### 10.3 Workflow prompt context

The workflow prompt MUST use GitLab issue fields and Symphony internal fields.

Required prompt variables:

```text
issue.identifier        # e.g. GL-123 or project_path#123
issue.iid               # GitLab project-local iid
issue.title
issue.description
issue.web_url
issue.gitlab_state
issue.labels
issue.assignees
issue.workflow_status
issue.is_blocked
issue.blockers
issue.notes_summary
workspace.path
```

Prompt templates MUST NOT mention Linear identifiers or Linear workflow state.

### 10.4 App-server tools

The `linear_graphql` app-server tool MUST be removed.

If repo skills need tracker operations, the implementation MUST provide a GitLab-scoped tool with a narrow surface:

```text
gitlab_current_issue
get_current_issue_notes
create_current_issue_note
update_current_issue_state
create_followup_issue
```

The tools MUST be scoped to the current selected project and current issue.
`create_followup_issue` MAY create a new issue in the current selected
project through that project's Project Access Token, but it MUST require
explicit title, description, and acceptance criteria, and it MUST initialize
the new issue as internal status `backlog`.
The tool surface MUST NOT expose arbitrary GitLab REST calls to the agent by
default.

`create_followup_issue` MUST be used when repo workflow instructions require an
Agent to capture out-of-scope improvements as a separate future task. It MUST
return the created GitLab issue identity, web URL, internal workflow status, and
relationship flags or dependency records created by Symphony.

### 10.5 Blocked and operator-input handling

When Codex reports that operator input, approval, MCP elicitation, or sandbox rejection is required:

1. The active `agent_runs.status` MUST become `blocked`.
2. A `runtime_blocks` row MUST be created.
3. `issue_workflow_states.status` MUST remain unchanged; `blocked` MUST NOT be written as an issue workflow status.
4. The issue DTO MUST expose derived blocked state so the issue can show a blocked badge/filter while staying in its current workflow stage.
5. Run Monitor MUST show the block.
6. The issue MUST remain claimed until the operator resolves the block, cancels the run, or explicitly resets the issue/run to a dispatchable state.

Unlike the original prototype, blocked state MUST survive orchestrator restart.

### 10.6 Completion

When the Agent completes successfully:

- `agent_runs.status` MUST become `succeeded`.
- The issue workflow status MUST be re-read after completion.
- A GitLab issue note SHOULD be posted with a concise run summary when write permission is available.
- Run Monitor MUST show the final status and run summary.

For GitLab-backed internal workflow state, this completion rule is the GitLab
mapping of upstream Symphony's tracker-state handoff semantics:

- Agent tools are the preferred way to move an issue between `in_progress`,
  `review`, `merging`, `rework`, and `done`.
- If the Agent exits normally and the current internal workflow status is still
  an active status (`todo`, `in_progress`, `merging`, or `rework`), the
  orchestrator MUST keep the upstream continuation behavior and schedule a
  short continuation retry.
- If the Agent exits normally and the current internal workflow status is
  `review`, the orchestrator MUST release its claim and wait for human review
  or approval.
- If the Agent exits normally and the current internal workflow status is
  `done`, the orchestrator MUST preserve `done`.
Internal `review` MUST NOT automatically close the GitLab issue. Internal
`done` means the merge/land flow has completed; when an issue enters `done`,
Symphony SHOULD close the GitLab issue through the server-side GitLab client.
Internal `canceled` means the work is intentionally stopped; when an issue enters
`canceled`, Symphony SHOULD also close the GitLab issue. GitLab close failures
MUST be recorded as events and MUST NOT corrupt the internal workflow status.

When the Agent fails:

- `agent_runs.status` MUST become `failed`.
- The issue workflow status SHOULD remain unchanged for retryable active-state failures.
- When the failure is caused by missing permissions, secrets, required tools, approval, or operator input, the run SHOULD become `blocked`, a `runtime_blocks` row SHOULD be created, and the issue workflow status SHOULD remain unchanged.
- Failure details MUST be visible in Run Monitor.

---

## 11. Backend HTTP API

### 11.1 API shape

The new React frontend MUST consume Symphony backend APIs, not GitLab APIs.

Required API groups:

```text
/auth/*
/api/auth/*
/api/projects/*
/api/issues/*
/api/workflow/*
/api/agents/*
/api/runs/*
/api/monitor/*
/api/sync/*
/api/settings/*
/api/v1/*              # operational compatibility/debug surface
```

The API MUST enforce selected-project access through the session:

- Unauthenticated API calls MUST return `authentication_required` and a GitLab login URL.
- Read endpoints MUST require GitLab access level `SYMPHONY_AUTH_MIN_ACCESS_LEVEL`.
- User write endpoints MUST require `SYMPHONY_AUTH_WRITE_ACCESS_LEVEL`.
- Administrative settings, sync refresh, and operational refresh endpoints MUST require `SYMPHONY_AUTH_ADMIN_ACCESS_LEVEL`.

User-initiated GitLab writes from these APIs MUST use the user's OAuth token, not the automation credential.

### 11.2 Auth and project APIs

Required endpoints:

```text
GET    /auth/gitlab
GET    /auth/gitlab/callback
GET    /auth/logout
GET    /api/auth/session
GET    /api/projects
POST   /api/projects/:id/activate
```

`GET /api/projects` MUST list projects visible through the signed-in user's GitLab membership. `POST /api/projects/:id/activate` MUST validate membership, persist the membership, update the session, and reset that project's issue cursor.

`GET /api/auth/session` MUST return auth mode, login/logout URLs, public GitLab user fields, derived permissions, and the active project. Project DTOs MUST include GitLab `id`, `name`, `path_with_namespace`, `web_url`, selection state, `project_setting_id`, `project_access_token_status`, `service_account_token_status`, `automation_credential_mode`, and `automation_credential_status`.

### 11.3 Issue APIs

Required endpoints:

```text
GET    /api/issues
GET    /api/issues/:id
GET    /api/issues/:id/notes
GET    /api/issues/:id/uploads/:secret/:filename
POST   /api/issues/:id/notes
PATCH  /api/issues/:id/gitlab
PATCH  /api/issues/:id/workflow
GET    /api/issues/:id/events
```

`PATCH /api/issues/:id/workflow` MUST update internal workflow state only.

`PATCH /api/issues/:id/gitlab` MUST update GitLab fields through the server-side GitLab client and then update the local read model.

### 11.4 Workflow APIs

Required endpoints:

```text
GET    /api/workflow/statuses
POST   /api/workflow/transitions
GET    /api/issues/:id/blockers
POST   /api/issues/:id/blockers
DELETE /api/issues/:id/blockers/:blocking_issue_id
```

### 11.5 Agent APIs

Required endpoints:

```text
POST   /api/agents/dispatch
POST   /api/runs/:id/cancel
POST   /api/runs/:id/retry
GET    /api/runs
GET    /api/runs/:id
GET    /api/runs/:id/events
```

`POST /api/agents/dispatch` MUST request an immediate scheduler refresh using
the same dispatch path as the periodic poller. It MUST NOT create a per-issue
manual run by itself.

### 11.6 Sync APIs

Required endpoints:

```text
GET    /api/sync/status
POST   /api/sync/refresh
```

### 11.7 Settings APIs

Required endpoints:

```text
GET    /api/settings/gitlab
POST   /api/settings/gitlab/test
PUT    /api/settings/gitlab/project-token
PUT    /api/settings/gitlab/service-account-token
PUT    /api/settings/gitlab/credential-mode
GET    /api/settings/workflow
PATCH  /api/settings/workflow
```

Settings APIs MUST redact secrets. Project-token updates MUST validate the token before encrypting and saving it for the selected project. Service Account token updates MUST validate the token against the selected project, encrypt and save it for the GitLab API root, and return only configured/missing status plus public account metadata. Credential-mode updates MUST apply only to the selected project.

---

## 12. Run Monitor

### 12.1 Purpose

The new frontend MUST include a top-level **Run Monitor** area. This area replaces the prototype Phoenix LiveView Web dashboard as the operator-facing observability UI.

Run Monitor is not the issue tracker dashboard. It is the runtime control and debugging area for the local Symphony process.

Run Monitor MUST answer these questions:

- Is Symphony running?
- Which workflow file is loaded?
- Is the GitLab sync healthy?
- Which issues are active, queued, blocked, or recently completed?
- Which Agent runs are consuming concurrency?
- Which runs need operator input, approval, or MCP elicitation?
- Which workspaces exist and where are their logs?
- What was the last error?
- Can the operator manually refresh runtime state?
- Can the operator jump from a runtime row to the GitLab issue URL?

### 12.2 Relationship to the original Elixir Web dashboard

The original Elixir prototype documented the Web dashboard as an observability UI enabled by `--port`. It used a minimal Phoenix stack with:

- A dashboard at `/`.
- JSON operational debugging under `/api/v1/*`.
- Bandit as the HTTP server.
- Static assets needed for the client bootstrap.
- Tracker issue identifiers linking to the tracker-provided URL when the URL uses `http` or `https`.

The GitLab migration MUST preserve these capabilities in the new architecture:

- `--port` MUST still enable the Phoenix HTTP observability/control service.
- Bandit SHOULD remain the default HTTP server unless the Elixir app already standardized on another Phoenix-compatible server.
- The React app MUST provide the operator dashboard instead of a legacy LiveView page.
- The React app MUST include a Run Monitor route.
- Runtime rows MUST link issue identifiers to GitLab `web_url` when the URL starts with `http://` or `https://`.
- JSON operational debugging MUST remain available under `/api/v1/*`.
- Manual refresh MUST remain available from both the UI and JSON API.

### 12.3 Routes

The frontend MUST include:

```text
/monitor                 Run Monitor overview
/monitor/runs            Active and historical runs
/monitor/runs/:runId     Run detail, event stream, logs
/monitor/blocks          Operator-input and blocked-state queue
/monitor/sync            GitLab sync health and cursor detail
```

The sidebar MUST include a persistent `Run Monitor` entry.

### 12.4 Required Run Monitor panels

Run Monitor overview MUST include the following panels:

1. **Runtime Overview**
   - App version or git SHA when available.
   - Uptime.
   - Auth/runtime mode.
   - Bind host and port.
   - Workflow file path.
   - Workflow file load status.
   - Last workflow reload error.

2. **Agent Capacity**
   - `max_concurrent_agents`.
   - Active run count.
   - Queued run count.
   - Blocked run count.
   - Succeeded/failed run counts for the current process lifetime and persisted history.

3. **Active Runs**
   - Issue identifier.
   - Issue title.
   - GitLab link.
   - Current run status.
   - Workspace path.
   - Current turn number when known.
   - Last heartbeat.
   - Cancel action.

4. **Blocked / Needs Operator Input**
   - Issue identifier.
   - Block type.
   - Message.
   - Created time.
   - Linked run.
   - Resolve/reset/cancel actions.

5. **GitLab Sync Health**
   - Configured GitLab API root.
   - Active project ref.
   - Project name and web URL.
   - Last successful issue sync.
   - Last attempted sync.
   - Last error.
   - Next scheduled sync.
   - Manual refresh action.
   - Read-only mode indicator.

6. **Workspace and Logs**
   - Workspace root.
   - Logs root.
   - Active workspace paths.
   - Links or commands for opening log files locally.
   - Recent run event messages.

7. **Operational Debug API**
   - Show the available `/api/v1/*` endpoints.
   - Provide copyable curl commands with token/secret redacted.
   - Display the current JSON state preview for `/api/v1/state`.

### 12.5 Monitor DTOs

The backend MUST provide a typed monitor DTO.

```ts
export interface MonitorStateDTO {
  runtime: {
    mode: "gitlab_oidc";
    appVersion: string | null;
    uptimeSeconds: number;
    bindHost: string;
    port: number;
    workflowPath: string;
    workflowLoaded: boolean;
    workflowLastLoadedAt: string | null;
    workflowLastError: string | null;
  };
  gitlab: {
    apiRoot: string | null;
    projectRef: string | null;
    projectId: number | null;
    projectName: string | null;
    projectWebUrl: string | null;
    readOnly: boolean;
    lastValidationAt: string | null;
    lastValidationError: string | null;
  };
  sync: {
    issueLastSuccessAt: string | null;
    issueLastAttemptAt: string | null;
    issueLastError: string | null;
    notesLastSuccessAt: string | null;
    pending: boolean;
    nextRunAt: string | null;
  };
  agents: {
    maxConcurrent: number;
    queued: number;
    starting: number;
    running: number;
    blocked: number;
    succeededRecent: number;
    failedRecent: number;
  };
  activeRuns: AgentRunDTO[];
  blocked: RuntimeBlockDTO[];
  recentEvents: MonitorEventDTO[];
}
```

Required supporting DTOs:

```ts
export interface AgentRunDTO {
  id: string;
  issueId: string;
  issueIdentifier: string;
  issueTitle: string;
  issueWebUrl: string;
  runNumber: number;
  status: "queued" | "starting" | "running" | "blocked" | "succeeded" | "failed" | "canceled" | "stale";
  workspacePath: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  lastHeartbeatAt: string | null;
  currentTurn: number | null;
  exitReason: string | null;
  errorMessage: string | null;
}

export interface RuntimeBlockDTO {
  id: string;
  issueId: string;
  issueIdentifier: string;
  issueTitle: string;
  issueWebUrl: string;
  agentRunId: string | null;
  blockType: "operator_input" | "approval_required" | "mcp_elicitation" | "sandbox_rejection" | "external_failure" | "blocked_by_dependency";
  message: string | null;
  insertedAt: string;
}

export interface MonitorEventDTO {
  id: string;
  type: string;
  message: string | null;
  insertedAt: string;
  issueIdentifier: string | null;
  runId: string | null;
}
```

### 12.6 Monitor APIs

Required typed monitor endpoints:

```text
GET    /api/monitor/state
GET    /api/monitor/events
GET    /api/monitor/blocks
POST   /api/monitor/blocks/:id/resolve
POST   /api/monitor/refresh
GET    /api/monitor/runs
GET    /api/monitor/runs/:id
GET    /api/monitor/runs/:id/events
POST   /api/monitor/runs/:id/cancel
```

`POST /api/monitor/refresh` MUST refresh the monitor state and enqueue a GitLab sync refresh. It MUST return the updated monitor DTO or a job acknowledgement with a state URL.

### 12.7 `/api/v1/*` operational compatibility surface

The migration MUST preserve an operational JSON debugging surface under `/api/v1/*`.

Required endpoints:

```text
GET  /api/v1/state
GET  /api/v1/:issue_identifier
POST /api/v1/refresh
```

Compatibility behavior:

- `GET /api/v1/state` MUST return runtime state equivalent to the original dashboard's operational state, enriched with GitLab and persistent blocked/run state.
- `GET /api/v1/:issue_identifier` MUST return the issue runtime/debug view for a GitLab-backed issue identifier.
- `POST /api/v1/refresh` MUST trigger the same refresh behavior as `POST /api/monitor/refresh`.
- Responses MUST be JSON.
- Secrets MUST be redacted.
- The endpoints MUST be useful for curl-based local debugging.

### 12.8 Live updates

Run Monitor SHOULD update through WebSocket or Server-Sent Events.

Required events:

```text
monitor.state.changed
sync.started
sync.finished
sync.failed
agent.run.queued
agent.run.started
agent.run.heartbeat
agent.run.blocked
agent.run.finished
runtime.block.created
runtime.block.resolved
workflow.transitioned
```

The UI MUST remain functional without live updates by polling `/api/monitor/state`.

### 12.9 Acceptance criteria for Run Monitor

A conforming implementation MUST pass these checks:

1. Starting Symphony with `--port` serves the React UI.
2. The sidebar contains `Run Monitor`.
3. `/monitor` shows runtime status, workflow file status, GitLab sync status, running agents, blocked items, and recent events.
4. `/monitor` provides a manual refresh action.
5. `/api/v1/state` returns JSON with running agents and blocked items.
6. `/api/v1/refresh` triggers refresh.
7. A blocked Codex run appears in Run Monitor and persists after orchestrator restart.
8. A run row links to the GitLab issue `web_url`.
9. No raw OAuth token or Project Access Token appears in page HTML, DTOs, logs, or browser storage.

---

## 13. Frontend implementation

### 13.1 Technology

The frontend MUST use:

```text
TypeScript
React
Vite
TanStack Query
React Router
Tailwind CSS
Radix UI primitives where needed
```

Phoenix LiveView MUST NOT be the primary dashboard implementation for the migrated UI.

### 13.2 App routes

Required routes:

```text
/                         Dashboard overview
/issues                   Issue list
/issues/:iid              Issue detail deep link
/board                    Internal status board
/agents                   Agent control panel
/runs                     Run history
/monitor                  Run Monitor overview
/monitor/runs             Run Monitor run list
/monitor/runs/:runId      Run detail
/monitor/blocks           Blocked/operator-input queue
/monitor/sync             Sync health
/settings/gitlab          GitLab setup and validation
/settings/workflow        Internal workflow settings
```

### 13.3 Layout

The app shell MUST include:

- Sidebar.
- Global search / command palette.
- Sync status badge.
- Run Monitor alert indicator when blocks or failures exist.
- Main content region.
- Detail drawer region for issues and runs.

### 13.4 Core components

Required component layout:

```text
src/
  app/
    routes.tsx
    queryClient.ts
  components/
    auth/AuthGate.tsx
    auth/RepoPicker.tsx
    auth/UserMenu.tsx
    layout/AppShell.tsx
    layout/Sidebar.tsx
    layout/ProjectSwitcher.tsx
    command/CommandPalette.tsx
    issues/IssueList.tsx
    issues/IssueRow.tsx
    issues/IssueBoard.tsx
    issues/IssueColumn.tsx
    issues/IssueDetailDrawer.tsx
    issues/StatusSelect.tsx
    issues/BlockerEditor.tsx
    issues/GitLabMeta.tsx
    agents/AgentControlPanel.tsx
    agents/RunTimeline.tsx
    monitor/RunMonitorPage.tsx
    monitor/RuntimeOverviewCard.tsx
    monitor/AgentCapacityCard.tsx
    monitor/ActiveRunsTable.tsx
    monitor/BlockedQueue.tsx
    monitor/SyncHealthCard.tsx
    monitor/WorkspaceLogsCard.tsx
    monitor/OperationalApiCard.tsx
    sync/SyncStatusBadge.tsx
  api/
    auth.ts
    client.ts
    issues.ts
    workflow.ts
    agents.ts
    runs.ts
    monitor.ts
    sync.ts
    settings.ts
  types/
    issue.ts
    workflow.ts
    gitlab.ts
    monitor.ts
    run.ts
```

### 13.5 Issue DTO

The frontend MUST consume backend DTOs, not GitLab raw payloads.

```ts
export type WorkflowStatus =
  | "backlog"
  | "todo"
  | "in_progress"
  | "review"
  | "merging"
  | "rework"
  | "done"
  | "canceled";

export interface IssueRelationRef {
  issueId: string;
  iid: number;
  identifier: string;
  title: string;
  status: WorkflowStatus;
  reason?: string | null;
  relationType?: string | null;
  direction?: string | null;
}

export interface IssueDTO {
  id: string;
  iid: number;
  identifier: string;
  gitlabIssueId: number;
  gitlabProjectId: number;
  webUrl: string;
  title: string;
  description: string | null;
  descriptionPreview: string | null;
  gitlabState: "opened" | "closed";
  workflowStatus: WorkflowStatus;
  priority: "none" | "low" | "medium" | "high" | "urgent";
  labels: string[];
  assignees: Array<{
    id: number;
    username: string;
    name: string;
    avatarUrl: string | null;
  }>;
  blockers: IssueRelationRef[];
  relations: {
    related: IssueRelationRef[];
    blocks: IssueRelationRef[];
    blockedBy: IssueRelationRef[];
  };
  isBlocked: boolean;
  unresolvedBlockerCount: number;
  openRuntimeBlockCount: number;
  blockedByCount: number;
  activeRunId: string | null;
  lastRunStatus: string | null;
  updatedAt: string;
  gitlabUpdatedAt: string;
  lastSyncAt: string | null;
}
```

### 13.6 UX requirements

The frontend MUST support:

- High-density issue list.
- Internal status filters.
- GitLab label filters.
- Search across title and description preview.
- Keyboard navigation.
- `Cmd/Ctrl+K` command palette.
- Open in GitLab action.
- Trigger immediate scheduler dispatch from the Agent/runtime controls.
- Cancel running agent runs.
- Retry failed run.
- Create a GitLab issue from the Issues view with a selectable user-creatable workflow status.
- Create a GitLab issue from a user-creatable Board column initialized to that column's workflow status.
- Change internal workflow status.
- Add/remove blockers.
- View notes/comments.
- Post notes with the signed-in user's OAuth token when the user has GitLab write permission.
- See Project Access Token or Service Account missing/validation errors when background/Agent GitLab access is unavailable.
- Jump from issue to run history.
- Jump from run history to issue.
- Jump from blocked Run Monitor row to issue and run detail.

---

## 14. Settings UI

### 14.1 GitLab settings page

`/settings/gitlab` MUST display:

- Configured API root.
- Active project ref.
- Validated project ID.
- Project path with namespace.
- Project web URL.
- Active automation credential mode and status.
- Project Access Token status as `configured` or `missing`, never the token value.
- Service Account token status and public account identity metadata, never the token value.
- Project Access Token permission mode when detectable, including conservative values such as `read_only_or_read_write`.
- Last validation time.
- Last validation error.
- Test connection button.
- Manual sync button.
- Project Access Token and Service Account token inputs for admin users.

The page MAY accept a Project Access Token for the active project from admin users. The page MAY accept a Service Account token for the configured GitLab API root and MUST warn before saving that the credential is global to that GitLab API root. Raw tokens MUST be sent only to backend validation endpoints, encrypted before persistence, and never returned to the frontend after the request completes.

OAuth/OIDC client secrets, session secrets, token encryption secrets, and database configuration MUST remain server-side `.env.local` or deployment configuration.

### 14.2 Workflow settings page

`/settings/workflow` MUST display:

- Allowed statuses.
- Dispatch candidate statuses.
- Required GitLab labels if configured.
- Max concurrent agents.
- Sync interval.
- Cursor overlap.
- Read-only mode impacts.

Changes that affect secrets MUST remain server-side config changes.

---

## 15. Removal of Linear

### 15.1 Code removal

The migration MUST delete or fully detach runtime references to:

```text
Linear API client
Linear GraphQL queries
linear_graphql app-server tool
Linear webhook controller
Linear schema fields
LINEAR_API_KEY config
Linear test fixtures
Linear e2e tests
Linear team/project/workflow status assumptions
```

### 15.2 Replacement mapping

| Linear-era concept | GitLab migration replacement |
|---|---|
| Linear issue | GitLab project issue read model |
| Linear project slug | Configured GitLab project ref/API URL |
| Linear workflow state | `issue_workflow_states.status` |
| Linear blocked state | derived issue blocked state from `runtime_blocks`, `agent_runs.status`, and `issue_dependencies` |
| Linear comments | GitLab issue notes |
| Linear GraphQL tool | Narrow GitLab current-issue tool |
| LiveView observability dashboard | React Run Monitor + `/api/v1/*` JSON |
| Linear issue URL | GitLab issue `web_url` |

### 15.3 Static guard

The implementation MUST include a test or script that fails when runtime code imports or references removed Linear runtime modules.

Allowed references:

- Historical docs.
- This migration spec.
- One-time migration scripts that do not compile into runtime supervision tree.

---

## 16. Project layout

Required layout shape:

```text
symphony/
  assets/
    package.json
    vite.config.ts
    src/
      api/
      app/
      components/
        auth/
        layout/
        issues/
        agents/
        monitor/
        sync/
      styles/
      types/
  config/
  lib/
    mix/
    symphony/
      gitlab/
        client.ex
        config.ex
        issue_mapper.ex
        note_mapper.ex
        error.ex
    symphony_elixir/
      auth/
      codex/
      monitor/
      persistence/
      store/
      sync/
      tracker/
    symphony_elixir_web/
      controllers/
      auth_plug.ex
      endpoint.ex
      router.ex
  priv/
    repo/
      migrations/
    static/
  scripts/
    setup.sh
  test/
    symphony/
      auth/
      gitlab/
      sync/
      workflow/
      store/
  WORKFLOW.md
```

---

## 17. Implementation phases

### Phase 1 — OAuth/OIDC auth and runtime configuration

Required work:

1. Add GitLab OAuth/OIDC config.
2. Add `.env.local` loading.
3. Add session secret and token encryption secret handling.
4. Add GitLab identity, OAuth token, and membership persistence.
5. Add auth routes and session API.

Acceptance:

- Users can sign in with GitLab OAuth/OIDC.
- OAuth tokens are encrypted at rest.
- Browser DTOs never expose raw token values.

### Phase 2 — Remove Linear runtime dependencies

Required work:

1. Remove Linear API client from runtime supervision tree.
2. Remove `LINEAR_API_KEY` requirement.
3. Remove `linear_graphql` app-server tool.
4. Remove Linear-specific workflow state dependencies.
5. Remove Linear event receiver code.

Acceptance:

- Symphony boots without `LINEAR_API_KEY`.
- Runtime code does not call Linear.
- Tests fail on accidental Linear runtime imports.

### Phase 3 — Project selection, membership, and credentials

Required work:

1. List user projects from GitLab with OAuth bearer auth.
2. Activate a project and persist `gitlab_project_settings`.
3. Validate and persist GitLab project membership.
4. Gate read/write/admin APIs by GitLab `access_level`.
5. Add Project Access Token settings flow.
6. Encrypt Project Access Tokens and expose only status.

Acceptance:

- A user can switch projects without signing out.
- Reporter/Developer/Maintainer thresholds gate APIs correctly.
- A Project Access Token can be saved for one project without leaking into another.

### Phase 4 — GitLab REST client and persistence

Required work:

1. Implement GitLab REST client.
2. Implement project validation.
3. Implement issue list/get/create/update.
4. Implement issue notes list/create.
5. Add Ecto schemas and migrations.
6. Add mappers and fixtures.

Acceptance:

- Project issue sync works against a fake GitLab server.
- Project issue creation works against a fake GitLab server.
- Notes sync works against a fake GitLab server.
- Pagination is tested.
- `id` vs `iid` behavior is tested.

### Phase 5 — Polling sync

Required work:

1. Implement startup sync over projects with configured Project Access Tokens.
2. Implement incremental sync using project-scoped `updated_after` cursors.
3. Implement cursor overlap.
4. Reset a project's cursor after project activation and Project Access Token updates.
5. Implement manual refresh.
6. Implement sync status reporting.

Acceptance:

- New GitLab issues appear in the selected project after polling or manual refresh.
- Updated GitLab issues update local read model.
- One project's cursor, token status, and unsynced state cannot affect another project.
- Sync errors appear in Settings and Run Monitor.

### Phase 6 — Internal workflow and blockers

Required work:

1. Implement internal workflow state machine.
2. Implement blocker/dependency storage.
3. Implement dependency cycle rejection.
4. Implement workflow APIs.
5. Implement issue event log.

Acceptance:

- Internal statuses work without GitLab labels.
- Blocked issues do not dispatch.
- Dependencies survive restart.

### Phase 7 — Agent runner migration

Required work:

1. Replace Linear candidate query with GitLab/internal DB query.
2. Update prompt variables.
3. Persist agent runs and run events.
4. Persist runtime blocked/operator-input state.
5. Post GitLab notes for run summaries through the Project Access Token when available.
6. Provide a narrow `create_followup_issue` tool for Agent-created follow-up work.
7. Remove Linear tool assumptions from repo skills.

Acceptance:

- A `todo` GitLab issue can be claimed and run.
- Agent run history persists.
- Operator-input blocked state appears after restart.
- Agent-created follow-up issues are created in the current selected GitLab project and enter internal `backlog`.
- No Linear prompt fields remain.

### Phase 8 — React control frontend

Required work:

1. Add Vite + React + TypeScript frontend.
2. Implement auth gate, repo picker, user menu, and project switcher.
3. Implement issue dashboard.
4. Implement board view.
5. Implement issue detail drawer.
6. Implement Agent control panel.
7. Implement run history.
8. Implement settings pages.
9. Implement GitLab linkouts.

Acceptance:

- Users must sign in before using protected dashboard APIs.
- Users can browse and switch GitLab projects they can access.
- Users can change internal workflow status when their GitLab access permits it.
- Users can trigger scheduler dispatch and cancel/retry runs when their GitLab access permits it.
- Users can open GitLab issue links.

### Phase 9 — Run Monitor

Required work:

1. Implement `Symphony.Monitor` context.
2. Implement `runtime_blocks` persistence.
3. Implement `/api/monitor/*` endpoints.
4. Preserve `/api/v1/state`, `/api/v1/:issue_identifier`, and `/api/v1/refresh`.
5. Implement React Run Monitor pages and panels.
6. Add PubSub/WebSocket/SSE live updates or polling fallback.
7. Link active/blocked runs to GitLab issue URLs.
8. Scope monitor data to the selected project.

Acceptance:

- `--port` starts React UI and JSON operational APIs.
- `/monitor` shows runtime, sync, agent, block, workspace, and debug API status for the selected project.
- `/api/v1/state` is usable from curl.
- Blocked runs persist and appear after restart.

### Phase 10 — Hardening and tests

Required work:

1. Add integration tests with fake GitLab server.
2. Add LiveView removal/static guard tests where applicable.
3. Add frontend component tests for Run Monitor and issue dashboard.
4. Add token redaction tests.
5. Add auth threshold, project switching, and project-scoped cursor tests.
6. Add documentation for self-managed GitLab OAuth/OIDC setup.

Acceptance:

- `make all` passes.
- Token redaction tests pass.
- GitLab fake-server e2e passes.
- No runtime Linear dependency remains.

---

## 18. Testing requirements

### 18.1 Unit tests

Required coverage:

- GitLab OAuth/OIDC config validation.
- OIDC issuer/public URL trailing-slash normalization.
- JWT ID token validation.
- OAuth token encryption and refresh behavior.
- GitLab project config from selected project settings.
- URL encoding for namespace project paths.
- Token redaction.
- GitLab client error normalization.
- GitLab issue mapper.
- GitLab note mapper.
- GitLab access-level role derivation.
- Project membership persistence.
- Project Access Token encryption/status projection.
- Workflow transitions.
- Dependency cycle detection.
- Dispatch candidate selection.
- Monitor DTO generation.

### 18.2 Integration tests

Required coverage with fake GitLab server:

- OIDC discovery, authorization callback, token exchange, and userinfo handling.
- `GET /projects?membership=true` project listing.
- `GET /projects/:id/members/all/:user_id` membership validation.
- `GET /projects/:id` validation.
- `GET /projects/:id/issues` pagination.
- Project-scoped `updated_after` incremental sync.
- Cursor reset after project activation, Project Access Token updates, Service Account token updates, and credential-mode changes.
- `GET /projects/:id/issues/:issue_iid/notes`.
- `POST /projects/:id/issues/:issue_iid/notes`.
- Auth failure.
- Insufficient project access.
- Rate limit failure.
- Network failure.

### 18.3 Frontend tests

Required coverage:

- Auth gate renders sign-in when unauthenticated.
- Repo picker and project switcher render GitLab projects and activation state.
- Issue list renders workflow status from Symphony DTO.
- Status change calls Symphony workflow API, not GitLab API.
- Run Monitor renders running agents.
- Run Monitor renders blocked queue.
- Run Monitor renders sync errors.
- Run Monitor links to GitLab issue URLs.
- Settings page redacts token.
- Settings page shows Project Access Token status without exposing the token value.

### 18.4 End-to-end local test

The local e2e test SHOULD start:

- Fake GitLab server.
- PostgreSQL test database.
- Symphony backend.
- React frontend build or dev server.
- Stub Codex app-server runner.

The test MUST prove:

1. GitLab OAuth/OIDC login succeeds.
2. The user sees only GitLab projects returned by membership listing.
3. Activating a project validates membership and stores the selected project.
4. Saving a Project Access Token validates and redacts it.
5. Issue sync imports a GitLab issue for that project.
6. Switching to another project uses a separate issue cursor and project token status.
7. The issue appears in dashboard.
8. Internal status changes to `todo`.
9. Agent run starts.
10. Stub runner creates a follow-up issue in the selected project.
11. The follow-up issue appears in the dashboard with internal status `backlog`.
12. Run appears in Run Monitor.
13. Stub runner blocks for operator input.
14. Block appears in Run Monitor and `/api/v1/state`.
15. Restart preserves block.
16. Operator cancels or resolves block.

---

## 19. Documentation requirements

The repository MUST include local setup docs with these sections:

```text
Self-managed GitLab local setup
Create GitLab OAuth application
Configure .env.local
Start Symphony with --port
Open dashboard
Sign in with GitLab
Select a repo
Create and save a Project Access Token
Test GitLab settings
Use Run Monitor
Troubleshooting auth errors
Troubleshooting OIDC issuer/redirect URI mismatch
Troubleshooting Project Access Token permissions
```

The docs MUST include this minimal quickstart:

```bash
cd symphony
cp .env.example .env.local
./scripts/setup.sh
./bin/symphony ./WORKFLOW.md --port 4000
```

The quickstart MUST tell the operator to configure GitLab OAuth/OIDC values in `.env.local`, then sign in, select a repo, and save that repo's Project Access Token from Settings.

---

## 20. Conformance checklist

A migration is conforming only when every item below is true:

1. Symphony boots without Linear configuration.
2. Runtime code does not call Linear.
3. GitLab OAuth/OIDC login is required for normal dashboard access.
4. GitLab identities, OAuth tokens, memberships, and Project Access Tokens are persisted with raw tokens encrypted.
5. Browser frontend never receives raw OAuth tokens or Project Access Tokens.
6. Users can list and activate GitLab projects from their GitLab membership.
7. Read/write/admin APIs are gated by GitLab numeric `access_level`.
8. Project Access Token settings are per project and never leak across projects.
9. GitLab REST API is called only from Elixir backend modules.
10. GitLab issues sync through polling.
11. GitLab issue cursors are scoped per project.
12. GitLab issue creation works through the backend for constrained follow-up issues.
13. GitLab notes sync and note creation work through the backend.
14. No GitLab event receiver or project hook is required.
15. Internal workflow states are stored in Symphony DB.
16. Blocker/dependency relationships are stored in Symphony DB.
17. Closed GitLab issues are not dispatch candidates.
18. Agent dispatch uses GitLab issue read model plus internal workflow state.
19. Agent runs are persisted.
20. Runtime blocked/operator-input state is persisted.
21. TypeScript + React dashboard exists.
22. Auth gate, repo picker, user menu, and project switcher exist.
23. Issue list, board, detail drawer, Agent panel, run history, and settings exist.
24. Run Monitor exists as a top-level frontend area.
25. Run Monitor includes runtime overview, sync health, running agents, blocked queue, workspace/log info, manual refresh, and operational JSON debug info.
26. `/api/v1/state`, `/api/v1/:issue_identifier`, and `/api/v1/refresh` exist for operational debugging.
27. Run Monitor issue identifiers link to GitLab `web_url` when the URL is `http` or `https`.
28. Token redaction tests pass.
29. Fake GitLab integration tests pass.
30. No runtime Linear dependency remains.

---

## 21. Reference links

These links are implementation references and do not override the normative requirements above.

- Symphony Elixir README, Web dashboard section: `https://github.com/openai/symphony/tree/main/elixir#web-dashboard`
- GitLab REST API: `https://docs.gitlab.com/api/rest/`
- GitLab REST authentication: `https://docs.gitlab.com/api/rest/authentication/`
- GitLab Issues API: `https://docs.gitlab.com/api/issues/`
- GitLab Notes API: `https://docs.gitlab.com/api/notes/`
- GitLab Project Access Tokens: `https://docs.gitlab.com/user/project/settings/project_access_tokens/`
