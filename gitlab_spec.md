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

Symphony currently treats Linear as the tracker integration described by upstream `SPEC.md`. The migration changes Symphony into a GitLab-native service that continuously tracks issues from one GitLab project, stores GitLab issue snapshots locally, maintains Symphony-owned workflow state separately from GitLab, and exposes a high-density dashboard for controlling agents and issue workflow.

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

3. **Track exactly one GitLab project by default**
   - The default deployment mode is local single-user mode.
   - The application MUST track one configured GitLab project.
   - The implementation MUST NOT require a multi-user login system, OAuth login, organization membership, RBAC, or team permission model in the default mode.
   - Multi-project and multi-user features are outside the default scope.

4. **Use GitLab REST API as the external issue source**
   - GitLab project issues are the external work item source.
   - GitLab issue title, description, labels, assignees, milestone, due date, open/closed state, and notes/comments are external GitLab facts.
   - Symphony MUST call GitLab REST API under `/api/v4`.
   - Symphony MUST authenticate to GitLab from the server side only.

5. **Maintain Symphony workflow state internally**
   - Symphony workflow statuses such as `triage`, `todo`, `in_progress`, `blocked`, `review`, `done`, and `canceled` MUST be stored in the Symphony database.
   - Blocker/dependency relationships MUST be stored in the Symphony database.
   - Dashboard ordering, run state, dispatch state, blocked/operator-input state, and sync cursors MUST be stored in the Symphony database.
   - GitLab paid workflow/blocker/status features MUST NOT be required for the core workflow.

6. **Provide a Linear-like control frontend**
   - The frontend MUST be implemented with TypeScript + React.
   - The frontend MUST provide a high-density issue dashboard, issue detail drawer, internal status controls, blocker editor, Agent control panel, run history, settings, and a dedicated runtime monitoring area.
   - The frontend MUST replicate the control efficiency of Linear-style dashboards without copying Linear trademarks, proprietary icons, brand assets, or protected visual details.

7. **Provide a dedicated Run Monitor area**
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
- A complete user login system in default local mode.
- OAuth login in default local mode.
- Team RBAC in default local mode.
- Multi-tenant project switching in default local mode.
- GitLab GraphQL as the primary tracker integration.
- GitLab Premium/Ultimate-only issue blocking as a required feature.
- GitLab issue boards as the workflow source of truth.
- GitLab labels as the workflow source of truth.
- Browser-side GitLab API calls.
- Browser-side GitLab token storage.
- A separate legacy LiveView dashboard as the primary UI.

---

## 3. Default deployment mode

### 3.1 Local single-user mode

The default runtime mode is `local_single_user`.

In this mode:

- One local operator controls Symphony.
- One GitLab project is configured.
- One GitLab API token is configured on the server.
- The Phoenix HTTP server binds to `127.0.0.1` by default.
- The browser frontend is served by the Phoenix backend or by a local dev Vite server proxying to Phoenix.
- No account table is required.
- No password login is required.
- No user invitation, organization, role, team, or membership feature is required.
- All actions are attributed internally to `local_operator` unless GitLab returns a different external author for synced notes.

### 3.2 Exposure guard

The implementation MUST set the default bind host to loopback:

```env
SYMPHONY_BIND_HOST=127.0.0.1
```

If the bind host is changed to `0.0.0.0` or another non-loopback interface, the implementation MUST require a simple shared secret:

```env
SYMPHONY_SHARED_SECRET=change-me
```

The shared secret is not a full login system. It is a local deployment exposure guard. The browser MUST send it through a server-issued session cookie or an `X-Symphony-Secret` header during local development. The GitLab token MUST never be sent to the browser.

### 3.3 Default command

The main runtime command MUST keep the original local-run ergonomics:

```bash
./bin/symphony ./WORKFLOW.md --port 4000
```

When `--port` is present, Symphony MUST start the Phoenix HTTP service, serve the React control frontend, expose the JSON API, and expose Run Monitor.

---

## 4. Configuration

### 4.1 Required GitLab configuration

The implementation MUST support the following fastest setup path:

```env
GITLAB_PROJECT_API_URL=http://gitlab.local/api/v4/projects/123
GITLAB_TOKEN=glpat_xxxxxxxxxxxxxxxxxxxx
```

`GITLAB_PROJECT_API_URL` is the preferred local single-project configuration. It MUST be parsed into:

- `gitlab_base_url`: `http://gitlab.local`
- `gitlab_api_root`: `http://gitlab.local/api/v4`
- `gitlab_project_ref`: `123`

The project reference MAY be either:

```env
GITLAB_PROJECT_API_URL=http://gitlab.local/api/v4/projects/123
```

or a URL-encoded namespace path:

```env
GITLAB_PROJECT_API_URL=http://gitlab.local/api/v4/projects/my-group%2Fmy-project
```

The implementation MUST also support explicit split configuration for scripted deployment:

```env
GITLAB_BASE_URL=http://gitlab.local
GITLAB_PROJECT_ID=123
GITLAB_TOKEN=glpat_xxxxxxxxxxxxxxxxxxxx
```

or:

```env
GITLAB_BASE_URL=http://gitlab.local
GITLAB_PROJECT_PATH=my-group/my-project
GITLAB_TOKEN=glpat_xxxxxxxxxxxxxxxxxxxx
```

If both `GITLAB_PROJECT_API_URL` and split configuration are present, `GITLAB_PROJECT_API_URL` MUST take precedence unless `GITLAB_PROJECT_API_URL` is invalid.

### 4.2 Token source

The implementation MUST read the GitLab token only from server-side configuration:

```env
GITLAB_TOKEN=...
```

The implementation MUST NOT store `GITLAB_TOKEN` in frontend source, frontend build output, browser local storage, browser session storage, IndexedDB, URL query parameters, or rendered HTML.

The implementation SHOULD use a GitLab project access token for self-managed GitLab installations because it is scoped to one project. A personal access token MAY be used when project access tokens are unavailable. For full operation, the token MUST have permission to:

- Read the configured project.
- Read project issues.
- Read project issue notes.
- Create issue notes.
- Update issue title/description/labels/state when Symphony exposes such actions.
- Close and reopen issues when Symphony exposes such actions.

A token with read-only API permissions MUST put Symphony in read-only tracker mode. In read-only tracker mode:

- Sync MUST work.
- Dashboard viewing MUST work.
- Internal workflow state changes MAY still work because they only update the Symphony database.
- GitLab note creation, GitLab issue update, GitLab close, and GitLab reopen actions MUST be disabled with a clear UI error.

### 4.3 Local env file

The implementation MUST support `.env.local` at the Elixir app root.

Required behavior:

- `.env.local` MUST be loaded in development and local runtime mode.
- `.env.local` MUST be listed in `.gitignore`.
- `mix symphony.gitlab.setup` MUST create or update `.env.local`.
- `mix symphony.gitlab.setup` MUST prompt for `GITLAB_PROJECT_API_URL`.
- `mix symphony.gitlab.setup` MUST read `GITLAB_TOKEN` from a hidden terminal prompt.
- `mix symphony.gitlab.setup` MUST NOT echo the token.
- `mix symphony.gitlab.setup` MUST print the detected host, API root, and project ref, but MUST redact the token.

Example setup interaction:

```text
$ mix symphony.gitlab.setup
GitLab project API URL: http://gitlab.local/api/v4/projects/123
GitLab token: ********
Wrote .env.local
Detected API root: http://gitlab.local/api/v4
Detected project: 123
Run: mix symphony.gitlab.test
```

### 4.4 Validation task

The implementation MUST provide:

```bash
mix symphony.gitlab.test
```

This task MUST:

1. Load `.env.local` and process environment.
2. Parse GitLab configuration.
3. Validate that the API root contains `/api/v4`.
4. Call `GET /projects/:id` for the configured project.
5. Call `GET /projects/:id/issues?per_page=1&state=all`.
6. Print project name, project web URL, default branch if present, token permission mode, and issue API reachability.
7. Redact token values from all output.
8. Exit non-zero on auth failure, project not found, invalid API URL, network failure, or missing config.

### 4.5 Runtime configuration keys

The implementation MUST support these keys:

```env
# GitLab
GITLAB_PROJECT_API_URL=http://gitlab.local/api/v4/projects/123
GITLAB_BASE_URL=http://gitlab.local
GITLAB_PROJECT_ID=123
GITLAB_PROJECT_PATH=my-group/my-project
GITLAB_TOKEN=glpat_xxx

# Symphony local HTTP
SYMPHONY_BIND_HOST=127.0.0.1
SYMPHONY_PORT=4000
SYMPHONY_SHARED_SECRET=

# Sync
SYMPHONY_SYNC_INTERVAL_MS=60000
SYMPHONY_SYNC_PAGE_SIZE=100
SYMPHONY_SYNC_CURSOR_OVERLAP_SECONDS=120

# Workspace / Agent
SYMPHONY_WORKSPACE_ROOT=~/code/workspaces
SYMPHONY_LOGS_ROOT=./log
CODEX_COMMAND="codex app-server"
```

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
│  Symphony.GitLab.Config       -> local project/token config    │
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
│  gitlab_project_settings / gitlab_issues / gitlab_issue_notes  │
│  issue_workflow_states / issue_dependencies / issue_events     │
│  agent_runs / agent_run_events / runtime_blocks / sync_cursors │
└──────────────────────────────┬─────────────────────────────────┘
                               │ HTTPS or local HTTP
┌──────────────────────────────▼─────────────────────────────────┐
│                         GitLab REST API                        │
│                                                                │
│  /api/v4/projects/:id                                          │
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
| Project identity | GitLab | Store GitLab project `id`, `path_with_namespace`, `web_url`, and API root after validation. |
| Issue identity | GitLab | Store GitLab global `id` and project-local `iid`; use `iid` for issue endpoint calls. |
| Title / description | GitLab | Sync into read model; update through GitLab API when edited from Symphony. |
| Labels / assignees / milestone / due date | GitLab | Sync and display; do not use as workflow truth. |
| Open / closed state | GitLab | Sync and display; closed issues are not dispatch candidates. |
| Notes/comments | GitLab | Sync issue notes; Agent comments are posted through backend GitLab client. |
| Workflow status | Symphony DB | Store and mutate internally. |
| Blocker/dependency | Symphony DB | Store and mutate internally. |
| Agent run state | Symphony DB | Store current and historical runs internally. |
| Runtime blocked/operator-input state | Symphony DB + runtime process state | Persist enough to survive restart; expose in Run Monitor. |
| Dashboard rank/order/views | Symphony DB | Store locally. |
| Sync cursors/errors | Symphony DB | Store locally and expose in Settings + Run Monitor. |

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
list_project_issues(config, params)
get_project_issue(config, issue_iid)
update_project_issue(config, issue_iid, attrs)
list_issue_notes(config, issue_iid, params)
create_issue_note(config, issue_iid, body)
```

Raw GitLab payload handling MUST be contained inside GitLab modules and mapper modules. Other contexts MUST consume internal structs or schemas.

### 6.2 API root and project ref

The client MUST build URLs under:

```text
{gitlab_base_url}/api/v4
```

The project identifier in path parameters MUST be either:

- Numeric project ID, or
- URL-encoded namespace/project path.

When `GITLAB_PROJECT_PATH=my-group/my-project` is used, the client MUST URL-encode `/` as `%2F` before building project API paths.

### 6.3 Authentication

The client MUST send access tokens with the `PRIVATE-TOKEN` header by default:

```text
PRIVATE-TOKEN: <redacted>
```

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
POST /projects/:id/issues/:issue_iid/notes
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

Stores the single configured GitLab project.

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
inserted_at utc_datetime_usec
updated_at utc_datetime_usec
```

The GitLab token MUST NOT be stored in this table. Token storage is environment/local secret configuration only for this migration.

### 7.2 `gitlab_issues`

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

### 7.3 `gitlab_issue_notes`

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid not null
note_id bigint not null
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

### 7.4 `issue_workflow_states`

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
triage
todo
in_progress
blocked
review
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

### 7.5 `issue_dependencies`

Required fields:

```text
id uuid primary key
blocked_issue_id uuid not null
blocking_issue_id uuid not null
created_by text not null default 'local_operator'
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

### 7.6 `issue_events`

Stores local state changes and GitLab sync observations.

Required fields:

```text
id uuid primary key
gitlab_issue_id uuid
event_type text not null
source text not null
actor text
payload jsonb not null default '{}'
inserted_at utc_datetime_usec
```

Allowed `source` values:

```text
gitlab_sync
local_ui
agent
system
```

### 7.7 `sync_cursors`

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
gitlab_issues_updated_after
gitlab_notes_last_full_sync_at
```

### 7.8 `agent_runs`

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

### 7.9 `agent_run_events`

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

### 7.10 `runtime_blocks`

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

1. Load and validate GitLab config.
2. Validate the configured project.
3. Upsert `gitlab_project_settings`.
4. Fetch project issues with `state=all`.
5. Page through all results.
6. Upsert `gitlab_issues`.
7. Create missing `issue_workflow_states` with default status `triage`.
8. Record sync events.
9. Update `sync_cursors`.
10. Broadcast UI updates through PubSub.

### 8.2 Incremental issue sync

The sync process MUST run at `SYMPHONY_SYNC_INTERVAL_MS`.

Incremental sync MUST use `updated_after` with cursor overlap:

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

### 8.3 Notes sync

Notes sync MUST support two paths:

1. Issue detail sync: when the user opens an issue detail drawer, fetch notes for that issue.
2. Periodic recent sync: on a configurable cadence, fetch notes for recently changed issues.

The implementation MUST use:

```text
GET /projects/:id/issues/:issue_iid/notes
POST /projects/:id/issues/:issue_iid/notes
```

Agent-created comments MUST be posted through `create_issue_note/3` and then inserted into local `gitlab_issue_notes` after GitLab returns the created note.

### 8.4 Manual refresh

The backend MUST expose a manual refresh endpoint used by Run Monitor and Settings:

```text
POST /api/sync/refresh
```

Manual refresh MUST enqueue or execute a sync job. It MUST NOT require or simulate external GitLab events.

### 8.5 Conflict behavior

When GitLab fields change externally:

- GitLab title/description/labels/assignees/milestone/due date/open-closed state MUST update local read model.
- Internal workflow status MUST remain unchanged unless an explicit Symphony rule changes it.
- If a GitLab issue is closed externally, the issue MUST stop being an Agent dispatch candidate.
- If a GitLab issue is reopened externally, the issue MAY re-enter dispatch only if its internal workflow status is an active candidate status.

---

## 9. Internal workflow model

### 9.1 Status meanings

| Status | Meaning | Dispatch candidate |
|---|---|---|
| `triage` | Synced from GitLab and not yet accepted into work queue. | No |
| `todo` | Ready for Agent work. | Yes |
| `in_progress` | Claimed by an active or recently active Agent run. | No |
| `blocked` | Cannot proceed because dependency or operator input is required. | No |
| `review` | Agent believes implementation is ready for human review or merge. | No |
| `done` | Work is complete. | No |
| `canceled` | Work is intentionally stopped. | No |

### 9.2 Status transitions

The implementation MUST centralize transitions in `Symphony.Workflow`.

Required transitions:

```text
triage -> todo
todo -> in_progress
todo -> blocked
in_progress -> blocked
in_progress -> review
in_progress -> done
in_progress -> todo
blocked -> todo
blocked -> canceled
review -> todo
review -> done
any non-terminal -> canceled
```

Terminal statuses:

```text
done
canceled
```

The implementation MUST record each transition in `issue_events`.

### 9.3 Blocker logic

An issue is blocked when either condition is true:

1. Its workflow status is `blocked`.
2. It has unresolved dependencies where at least one blocking issue is not in `done`.

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

---

## 10. Agent runner migration

### 10.1 Issue dispatch query

The dispatcher MUST select work from the internal database.

A dispatch candidate MUST satisfy:

```text
gitlab_issues.gitlab_state = "opened"
issue_workflow_states.status in ["todo"]
no unresolved dependency blocker
no active agent run for the same issue
required labels satisfied when configured
max_concurrent_agents not exceeded
```

The dispatcher MUST NOT query Linear.

### 10.2 Claiming

When an issue is claimed:

1. `issue_workflow_states.status` MUST transition to `in_progress`.
2. `claimed_by` MUST be set to the runner identity.
3. A new `agent_runs` row MUST be created.
4. An `agent_run_events` row with `queued` or `starting` MUST be created.
5. Run Monitor MUST update through PubSub.

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
```

The tool MUST be scoped to the current configured project and current issue. It MUST NOT expose arbitrary GitLab REST calls to the agent by default.

### 10.5 Blocked and operator-input handling

When Codex reports that operator input, approval, MCP elicitation, or sandbox rejection is required:

1. The active `agent_runs.status` MUST become `blocked`.
2. A `runtime_blocks` row MUST be created.
3. `issue_workflow_states.status` MUST transition to `blocked` unless the issue is already terminal.
4. Run Monitor MUST show the block.
5. The issue MUST remain claimed until the operator resolves the block, cancels the run, or resets the issue to `todo`.

Unlike the original prototype, blocked state MUST survive orchestrator restart.

### 10.6 Completion

When the Agent completes successfully:

- `agent_runs.status` MUST become `succeeded`.
- The issue workflow status SHOULD transition to `review` unless the workflow explicitly closes the issue as `done`.
- A GitLab issue note SHOULD be posted with a concise run summary when write permission is available.
- Run Monitor MUST show the final status and run summary.

When the Agent fails:

- `agent_runs.status` MUST become `failed`.
- The issue workflow status SHOULD transition to `todo` or `blocked` based on failure type.
- Failure details MUST be visible in Run Monitor.

---

## 11. Backend HTTP API

### 11.1 API shape

The new React frontend MUST consume Symphony backend APIs, not GitLab APIs.

Required API groups:

```text
/api/issues/*
/api/workflow/*
/api/agents/*
/api/runs/*
/api/monitor/*
/api/sync/*
/api/settings/*
/api/v1/*              # operational compatibility/debug surface
```

### 11.2 Issue APIs

Required endpoints:

```text
GET    /api/issues
GET    /api/issues/:id
GET    /api/issues/:id/notes
POST   /api/issues/:id/notes
PATCH  /api/issues/:id/gitlab
PATCH  /api/issues/:id/workflow
GET    /api/issues/:id/events
```

`PATCH /api/issues/:id/workflow` MUST update internal workflow state only.

`PATCH /api/issues/:id/gitlab` MUST update GitLab fields through the server-side GitLab client and then update the local read model.

### 11.3 Workflow APIs

Required endpoints:

```text
GET    /api/workflow/statuses
POST   /api/workflow/transitions
GET    /api/issues/:id/blockers
POST   /api/issues/:id/blockers
DELETE /api/issues/:id/blockers/:blocking_issue_id
```

### 11.4 Agent APIs

Required endpoints:

```text
POST   /api/agents/dispatch
POST   /api/issues/:id/run
POST   /api/runs/:id/cancel
POST   /api/runs/:id/retry
GET    /api/runs
GET    /api/runs/:id
GET    /api/runs/:id/events
```

### 11.5 Sync APIs

Required endpoints:

```text
GET    /api/sync/status
POST   /api/sync/refresh
```

### 11.6 Settings APIs

Required endpoints:

```text
GET    /api/settings/gitlab
POST   /api/settings/gitlab/test
GET    /api/settings/workflow
PATCH  /api/settings/workflow
```

Settings APIs MUST redact secrets.

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
   - Local mode.
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
   - Configured project ref.
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
    mode: "local_single_user";
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
    apiRoot: string;
    projectRef: string;
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
3. `/monitor` shows runtime status, workflow file status, GitLab sync status, active runs, blocked items, and recent events.
4. `/monitor` provides a manual refresh action.
5. `/api/v1/state` returns JSON with active runs and blocked items.
6. `/api/v1/refresh` triggers refresh.
7. A blocked Codex run appears in Run Monitor and persists after orchestrator restart.
8. A run row links to the GitLab issue `web_url`.
9. No GitLab token appears in page HTML, DTOs, logs, or browser storage.

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
Radix UI or shadcn/ui primitives
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
- Active run indicator.
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
    layout/AppShell.tsx
    layout/Sidebar.tsx
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
  | "triage"
  | "todo"
  | "in_progress"
  | "blocked"
  | "review"
  | "done"
  | "canceled";

export interface IssueDTO {
  id: string;
  iid: number;
  identifier: string;
  gitlabIssueId: number;
  gitlabProjectId: number;
  webUrl: string;
  title: string;
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
  blockers: Array<{
    issueId: string;
    iid: number;
    identifier: string;
    title: string;
    status: WorkflowStatus;
  }>;
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
- Start Agent on issue.
- Cancel active run.
- Retry failed run.
- Change internal workflow status.
- Add/remove blockers.
- View notes/comments.
- Post note when GitLab token has write permission.
- See read-only mode when GitLab token lacks write permission.
- Jump from issue to run history.
- Jump from run history to issue.
- Jump from blocked Run Monitor row to issue and run detail.

---

## 14. Settings UI

### 14.1 GitLab settings page

`/settings/gitlab` MUST display:

- Configured API root.
- Configured project ref.
- Validated project ID.
- Project path with namespace.
- Project web URL.
- Token status as `configured` or `missing`, never the token value.
- Token mode as `read_write`, `read_only`, or `invalid` when detectable.
- Last validation time.
- Last validation error.
- Test connection button.
- Manual sync button.

The page MUST instruct the local operator to use `.env.local` or `mix symphony.gitlab.setup` to change secrets. It MUST NOT provide a browser form that stores the GitLab token through the frontend in this migration.

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
| Linear blocked state | `runtime_blocks` + `issue_dependencies` |
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

Target layout:

```text
elixir/
  lib/
    symphony/
      gitlab/
        client.ex
        config.ex
        issue_mapper.ex
        note_mapper.ex
      tracker/
        gitlab_tracker.ex
        issue_read_model.ex
      workflow/
        state_machine.ex
        blockers.ex
      sync/
        poller.ex
        issue_sync.ex
        note_sync.ex
        cursor.ex
      agent/
        dispatcher.ex
        runner.ex
        run_store.ex
      monitor/
        state.ex
        runtime_blocks.ex
        dto.ex
      web/
        controllers/
          issue_controller.ex
          workflow_controller.ex
          agent_controller.ex
          run_controller.ex
          monitor_controller.ex
          sync_controller.ex
          settings_controller.ex
          v1_debug_controller.ex
        endpoint.ex
        router.ex
  assets/
    package.json
    vite.config.ts
    src/
      app/
      components/
      api/
      types/
  priv/
    repo/
      migrations/
    static/
  test/
    symphony/
      gitlab/
      sync/
      workflow/
      agent/
      monitor/
    symphony_web/
```

---

## 17. Implementation phases

### Phase 1 — Runtime boundary and configuration

Required work:

1. Add GitLab config parser.
2. Add `.env.local` loading.
3. Add `mix symphony.gitlab.setup`.
4. Add `mix symphony.gitlab.test`.
5. Add local single-user mode defaults.
6. Add exposure guard for non-loopback bind host.

Acceptance:

- A local operator can configure `GITLAB_PROJECT_API_URL` and `GITLAB_TOKEN` in less than two minutes.
- `mix symphony.gitlab.test` validates the project and issue API.
- Token values are redacted.

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

### Phase 3 — GitLab REST client and persistence

Required work:

1. Implement GitLab REST client.
2. Implement project validation.
3. Implement issue list/get/update.
4. Implement issue notes list/create.
5. Add Ecto schemas and migrations.
6. Add mappers and fixtures.

Acceptance:

- Project issue sync works against a fake GitLab server.
- Notes sync works against a fake GitLab server.
- Pagination is tested.
- `id` vs `iid` behavior is tested.

### Phase 4 — Polling sync

Required work:

1. Implement startup full sync.
2. Implement incremental sync using `updated_after`.
3. Implement cursor overlap.
4. Implement manual refresh.
5. Implement sync status reporting.

Acceptance:

- New GitLab issues appear in the dashboard after polling or manual refresh.
- Updated GitLab issues update local read model.
- Sync errors appear in Settings and Run Monitor.

### Phase 5 — Internal workflow and blockers

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

### Phase 6 — Agent runner migration

Required work:

1. Replace Linear candidate query with GitLab/internal DB query.
2. Update prompt variables.
3. Persist agent runs and run events.
4. Persist runtime blocked/operator-input state.
5. Post GitLab notes for run summaries when write permission exists.
6. Remove Linear tool assumptions from repo skills.

Acceptance:

- A `todo` GitLab issue can be claimed and run.
- Agent run history persists.
- Operator-input blocked state appears after restart.
- No Linear prompt fields remain.

### Phase 7 — React control frontend

Required work:

1. Add Vite + React + TypeScript frontend.
2. Implement issue dashboard.
3. Implement board view.
4. Implement issue detail drawer.
5. Implement Agent control panel.
6. Implement run history.
7. Implement settings pages.
8. Implement GitLab linkouts.

Acceptance:

- Operator can browse GitLab project issues locally.
- Operator can change internal workflow status.
- Operator can start/cancel/retry runs.
- Operator can open GitLab issue links.

### Phase 8 — Run Monitor

Required work:

1. Implement `Symphony.Monitor` context.
2. Implement `runtime_blocks` persistence.
3. Implement `/api/monitor/*` endpoints.
4. Preserve `/api/v1/state`, `/api/v1/:issue_identifier`, and `/api/v1/refresh`.
5. Implement React Run Monitor pages and panels.
6. Add PubSub/WebSocket/SSE live updates or polling fallback.
7. Link active/blocked runs to GitLab issue URLs.

Acceptance:

- `--port` starts React UI and JSON operational APIs.
- `/monitor` shows runtime, sync, agent, block, workspace, and debug API status.
- `/api/v1/state` is usable from curl.
- Blocked runs persist and appear after restart.

### Phase 9 — Hardening and tests

Required work:

1. Add integration tests with fake GitLab server.
2. Add LiveView removal/static guard tests where applicable.
3. Add frontend component tests for Run Monitor and issue dashboard.
4. Add token redaction tests.
5. Add local setup task tests.
6. Add documentation for self-managed GitLab local setup.

Acceptance:

- `make all` passes.
- Token redaction tests pass.
- GitLab fake-server e2e passes.
- No runtime Linear dependency remains.

---

## 18. Testing requirements

### 18.1 Unit tests

Required coverage:

- GitLab config parsing.
- Project API URL parsing.
- URL encoding for project paths.
- Token redaction.
- GitLab client error normalization.
- GitLab issue mapper.
- GitLab note mapper.
- Workflow transitions.
- Dependency cycle detection.
- Dispatch candidate selection.
- Monitor DTO generation.

### 18.2 Integration tests

Required coverage with fake GitLab server:

- `GET /projects/:id` validation.
- `GET /projects/:id/issues` pagination.
- `updated_after` incremental sync.
- `GET /projects/:id/issues/:issue_iid/notes`.
- `POST /projects/:id/issues/:issue_iid/notes`.
- Auth failure.
- Rate limit failure.
- Network failure.

### 18.3 Frontend tests

Required coverage:

- Issue list renders workflow status from Symphony DTO.
- Status change calls Symphony workflow API, not GitLab API.
- Run Monitor renders active runs.
- Run Monitor renders blocked queue.
- Run Monitor renders sync errors.
- Run Monitor links to GitLab issue URLs.
- Settings page redacts token.

### 18.4 End-to-end local test

The local e2e test SHOULD start:

- Fake GitLab server.
- PostgreSQL test database.
- Symphony backend.
- React frontend build or dev server.
- Stub Codex app-server runner.

The test MUST prove:

1. Setup config validates.
2. Issue sync imports a GitLab issue.
3. The issue appears in dashboard.
4. Internal status changes to `todo`.
5. Agent run starts.
6. Run appears in Run Monitor.
7. Stub runner blocks for operator input.
8. Block appears in Run Monitor and `/api/v1/state`.
9. Restart preserves block.
10. Operator cancels or resolves block.

---

## 19. Documentation requirements

The repository MUST include local setup docs with these sections:

```text
Self-managed GitLab local setup
Create project access token
Configure .env.local
Run mix symphony.gitlab.test
Start Symphony with --port
Open dashboard
Use Run Monitor
Troubleshooting auth errors
Troubleshooting project path encoding
Troubleshooting read-only token mode
```

The docs MUST include this minimal quickstart:

```bash
cd elixir
mix setup
mix symphony.gitlab.setup
mix symphony.gitlab.test
./bin/symphony ./WORKFLOW.md --port 4000
open http://127.0.0.1:4000
```

---

## 20. Conformance checklist

A migration is conforming only when every item below is true:

1. Symphony boots without Linear configuration.
2. Runtime code does not call Linear.
3. `GITLAB_PROJECT_API_URL` + `GITLAB_TOKEN` is enough to configure a local single-project deployment.
4. `mix symphony.gitlab.setup` creates `.env.local` with token redaction.
5. `mix symphony.gitlab.test` validates the configured GitLab project and issue API.
6. GitLab REST API is called only from Elixir backend modules.
7. Browser frontend never receives the GitLab token.
8. GitLab issues sync through polling.
9. GitLab notes sync and note creation work through the backend.
10. No GitLab event receiver or project hook is required.
11. Internal workflow states are stored in Symphony DB.
12. Blocker/dependency relationships are stored in Symphony DB.
13. Closed GitLab issues are not dispatch candidates.
14. Agent dispatch uses GitLab issue read model plus internal workflow state.
15. Agent runs are persisted.
16. Runtime blocked/operator-input state is persisted.
17. TypeScript + React dashboard exists.
18. Issue list, board, detail drawer, Agent panel, run history, and settings exist.
19. Run Monitor exists as a top-level frontend area.
20. Run Monitor includes runtime overview, sync health, active runs, blocked queue, workspace/log info, manual refresh, and operational JSON debug info.
21. `/api/v1/state`, `/api/v1/:issue_identifier`, and `/api/v1/refresh` exist for local operational debugging.
22. Run Monitor issue identifiers link to GitLab `web_url` when the URL is `http` or `https`.
23. Token redaction tests pass.
24. Fake GitLab integration tests pass.
25. No runtime Linear dependency remains.

---

## 21. Reference links

These links are implementation references and do not override the normative requirements above.

- Symphony Elixir README, Web dashboard section: `https://github.com/openai/symphony/tree/main/elixir#web-dashboard`
- GitLab REST API: `https://docs.gitlab.com/api/rest/`
- GitLab REST authentication: `https://docs.gitlab.com/api/rest/authentication/`
- GitLab Issues API: `https://docs.gitlab.com/api/issues/`
- GitLab Notes API: `https://docs.gitlab.com/api/notes/`
- GitLab Project Access Tokens: `https://docs.gitlab.com/user/project/settings/project_access_tokens/`
