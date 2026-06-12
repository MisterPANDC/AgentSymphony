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

  scope "/", SymphonyElixirWeb do
    pipe_through(:api)

    get("/api/issues", IssueController, :index)
    get("/api/issues/:id", IssueController, :show)
    get("/api/issues/:id/notes", IssueController, :notes)
    post("/api/issues/:id/notes", IssueController, :create_note)
    patch("/api/issues/:id/gitlab", IssueController, :update_gitlab)
    patch("/api/issues/:id/workflow", IssueController, :update_workflow)
    get("/api/issues/:id/events", IssueController, :events)

    get("/api/workflow/statuses", WorkflowController, :statuses)
    post("/api/workflow/transitions", WorkflowController, :transition)
    get("/api/issues/:id/blockers", WorkflowController, :blockers)
    post("/api/issues/:id/blockers", WorkflowController, :add_blocker)
    delete("/api/issues/:id/blockers/:blocking_issue_id", WorkflowController, :remove_blocker)

    post("/api/agents/dispatch", AgentController, :dispatch)
    post("/api/issues/:id/run", AgentController, :run_issue)
    get("/api/runs", RunController, :index)
    get("/api/runs/:id", RunController, :show)
    get("/api/runs/:id/events", RunController, :events)
    post("/api/runs/:id/cancel", RunController, :cancel)
    post("/api/runs/:id/retry", RunController, :retry)

    get("/api/monitor/state", MonitorController, :state)
    get("/api/monitor/events", MonitorController, :events)
    get("/api/monitor/blocks", MonitorController, :blocks)
    post("/api/monitor/blocks/:id/resolve", MonitorController, :resolve_block)
    post("/api/monitor/refresh", MonitorController, :refresh)
    get("/api/monitor/runs", MonitorController, :runs)
    get("/api/monitor/runs/:id", MonitorController, :run)
    get("/api/monitor/runs/:id/events", MonitorController, :run_events)
    post("/api/monitor/runs/:id/cancel", MonitorController, :cancel_run)

    get("/api/sync/status", SyncController, :status)
    post("/api/sync/refresh", SyncController, :refresh)

    get("/api/settings/gitlab", SettingsController, :gitlab)
    post("/api/settings/gitlab/test", SettingsController, :test_gitlab)
    get("/api/settings/workflow", SettingsController, :workflow)
    patch("/api/settings/workflow", SettingsController, :update_workflow)

    get("/api/v1/state", ObservabilityApiController, :state)
    post("/api/v1/refresh", ObservabilityApiController, :refresh)
    get("/api/v1/:issue_identifier", ObservabilityApiController, :issue)
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
