defmodule SymphonyElixirWeb.Router do
  @moduledoc """
  Router for Symphony's GitLab-native JSON API and React dashboard.
  """

  use Phoenix.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_session do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(SymphonyElixirWeb.AuthPlug, :load_current_user)
  end

  pipeline :api_auth do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(SymphonyElixirWeb.AuthPlug, :load_current_user)
    plug(SymphonyElixirWeb.AuthPlug, {:require_access, :read})
  end

  pipeline :api_write do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(SymphonyElixirWeb.AuthPlug, :load_current_user)
    plug(SymphonyElixirWeb.AuthPlug, {:require_access, :write})
  end

  pipeline :api_admin do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(SymphonyElixirWeb.AuthPlug, :load_current_user)
    plug(SymphonyElixirWeb.AuthPlug, {:require_access, :admin})
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:browser)

    get("/auth/gitlab", AuthController, :login)
    get("/auth/gitlab/callback", AuthController, :callback)
    get("/auth/logout", AuthController, :logout)
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:api_session)

    get("/api/auth/session", AuthController, :session)
    get("/api/projects", ProjectController, :index)
    post("/api/projects/:id/activate", ProjectController, :activate)
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:api_auth)

    get("/api/issues", IssueController, :index)
    get("/api/issues/:id", IssueController, :show)
    get("/api/issues/:id/notes", IssueController, :notes)
    get("/api/issues/:id/merge_requests", IssueController, :merge_requests)
    get("/api/issues/:id/merge_requests/:merge_request_iid/notes", IssueController, :merge_request_notes)
    get("/api/issues/:id/uploads/:secret/:filename", IssueController, :upload)
    get("/api/issues/:id/events", IssueController, :events)

    get("/api/workflow/statuses", WorkflowController, :statuses)
    get("/api/issues/:id/blockers", WorkflowController, :blockers)

    get("/api/runs", RunController, :index)
    get("/api/runs/:id", RunController, :show)
    get("/api/runs/:id/events", RunController, :events)

    get("/api/monitor/state", MonitorController, :state)
    get("/api/monitor/events", MonitorController, :events)
    get("/api/monitor/blocks", MonitorController, :blocks)
    get("/api/monitor/runs", MonitorController, :runs)
    get("/api/monitor/runs/:id", MonitorController, :run)
    get("/api/monitor/runs/:id/events", MonitorController, :run_events)

    get("/api/sync/status", SyncController, :status)

    get("/api/settings/gitlab", SettingsController, :gitlab)
    get("/api/settings/workflow", SettingsController, :workflow)

    get("/api/v1/state", ObservabilityApiController, :state)
    get("/api/v1/:issue_identifier", ObservabilityApiController, :issue)
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:api_write)

    post("/api/issues", IssueController, :create)
    post("/api/issues/:id/notes", IssueController, :create_note)
    post("/api/issues/:id/merge_requests/:merge_request_iid/notes", IssueController, :create_merge_request_note)
    put("/api/issues/:id/notes/:note_id", IssueController, :update_note)
    put("/api/issues/:id/merge_requests/:merge_request_iid/notes/:note_id", IssueController, :update_merge_request_note)
    delete("/api/issues/:id/notes/:note_id", IssueController, :delete_note)
    delete("/api/issues/:id/merge_requests/:merge_request_iid/notes/:note_id", IssueController, :delete_merge_request_note)
    patch("/api/issues/:id/gitlab", IssueController, :update_gitlab)
    patch("/api/issues/:id/merge_requests/:merge_request_iid/gitlab", IssueController, :update_merge_request_gitlab)
    patch("/api/issues/:id/workflow", IssueController, :update_workflow)

    post("/api/workflow/transitions", WorkflowController, :transition)
    post("/api/issues/:id/blockers", WorkflowController, :add_blocker)
    delete("/api/issues/:id/blockers/:blocking_issue_id", WorkflowController, :remove_blocker)

    post("/api/agents/dispatch", AgentController, :dispatch)
    post("/api/runs/:id/cancel", RunController, :cancel)
    post("/api/runs/:id/retry", RunController, :retry)
    post("/api/monitor/blocks/:id/resolve", MonitorController, :resolve_block)
    post("/api/monitor/runs/:id/cancel", MonitorController, :cancel_run)
    patch("/api/settings/workflow", SettingsController, :update_workflow)
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:api_admin)

    post("/api/monitor/refresh", MonitorController, :refresh)
    post("/api/sync/refresh", SyncController, :refresh)
    post("/api/settings/gitlab/test", SettingsController, :test_gitlab)
    get("/api/settings/gitlab/local-repo/candidates", SettingsController, :local_repo_candidates)
    put("/api/settings/gitlab/local-repo", SettingsController, :update_local_repo)
    put("/api/settings/gitlab/project-token", SettingsController, :update_project_token)
    post("/api/v1/refresh", ObservabilityApiController, :refresh)
  end

  scope "/", SymphonyElixirWeb do
    get("/assets/*path", StaticAssetController, :static)
    get("/favicon.png", StaticAssetController, :favicon)
  end

  scope "/", SymphonyElixirWeb do
    pipe_through(:browser)

    get("/", SpaController, :index)
    get("/*path", SpaController, :index)
  end
end
