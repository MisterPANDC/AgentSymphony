---
tracker:
  kind: gitlab
  required_labels: []
  active_states:
    - todo
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
3. Do not read or ask for GitLab tokens. Symphony owns GitLab API access on the server side.
4. If blocked by missing permissions, secrets, approval, or external service failure, stop with a concise blocker summary so Symphony can surface it in Run Monitor.
5. When implementation appears ready, summarize the result and set the internal status to `review` unless the workflow explicitly requires `done`.
