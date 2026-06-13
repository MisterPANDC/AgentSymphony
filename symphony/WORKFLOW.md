---
tracker:
  kind: gitlab
  required_labels: []
  active_states:
    - todo
    - in_progress
    - merging
    - rework
  terminal_states:
    - done
    - canceled
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
hooks:
  after_create: |
    git init
agent:
  max_concurrent_agents: 3
  max_turns: 20
codex:
  command: codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
    networkAccess: true
---

You are working on GitLab issue `{{ issue.identifier }}`.

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the issue is still dispatchable.
- Resume from the current workspace state instead of restarting from scratch.
{% endif %}

Issue context:

- Identifier: {{ issue.identifier }}
- GitLab IID: {{ issue.iid }}
- Title: {{ issue.title }}
- GitLab state: {{ issue.gitlab_state }}
- Internal workflow status: {{ issue.workflow_status }}
- Blocked: {{ issue.is_blocked }}
- Labels: {{ issue.labels }}
- Assignees: {{ issue.assignees }}
- URL: {{ issue.web_url }}
- Blockers: {{ issue.blockers }}

Description:

{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Notes summary:

{% if issue.notes_summary %}
{{ issue.notes_summary }}
{% else %}
No synced notes yet.
{% endif %}

Instructions:

1. Work only in the provided workspace path.
2. Use the injected GitLab-scoped tools only for the current issue:
   - `gitlab_current_issue`
   - `get_current_issue_notes`
   - `create_current_issue_note`
   - `update_current_issue_state`
   - `create_followup_issue`
3. Do not read or ask for GitLab tokens. Symphony owns GitLab API access on the server side.
4. If meaningful out-of-scope follow-up work is discovered, use `create_followup_issue` instead of expanding the current issue scope. Set `blocked_by_current_issue` only when the follow-up depends on this issue being completed first.
5. If blocked by missing permissions, secrets, approval, or external service failure, stop with a concise blocker summary so Symphony can surface it in Run Monitor.
6. Follow the internal workflow status:
   - `todo`: move to `in_progress` before active work.
   - `in_progress`: implement, validate, publish/attach merge request evidence, then set status to `review`.
   - `review`: wait for human review or approval; do not continue implementation unless feedback requires it.
   - `merging`: perform the merge/land flow until the merge request is merged, then set status to `done`.
   - `rework`: address reviewer feedback, revalidate, and return to `review`.
7. Set `done` only after the merge/land flow is complete.
