defmodule SymphonyElixirWeb.AiChatController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.AiChat
  alias SymphonyElixirWeb.AuthPlug

  @spec show(Conn.t(), map()) :: Conn.t()
  def show(conn, _params) do
    with %{} = project <- AuthPlug.current_project(conn) do
      json(conn, %{chat: AiChat.status(project)})
    else
      nil -> error(conn, 422, "missing_project", "Select a GitLab project before opening AI chat.")
    end
  end

  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, %{"message" => message}) when is_binary(message) do
    with %{} = project <- AuthPlug.current_project(conn),
         {:ok, chat} <- AiChat.send_message(project, message, AuthPlug.actor(conn)) do
      json(conn, %{chat: chat})
    else
      nil -> error(conn, 422, "missing_project", "Select a GitLab project before sending a chat message.")
      {:error, :empty_message} -> error(conn, 400, "empty_message", "Message is required.")
      {:error, :turn_in_progress} -> error(conn, 409, "turn_in_progress", "Codex is still responding. Wait for the current turn to finish.")
      {:error, reason} -> error(conn, 422, "codex_chat_failed", inspect(reason))
    end
  end

  def create(conn, _params), do: error(conn, 400, "missing_message", "Message is required.")

  @spec approve(Conn.t(), map()) :: Conn.t()
  def approve(conn, %{"id" => request_id, "decision" => decision})
      when is_binary(request_id) and is_binary(decision) do
    with %{} = project <- AuthPlug.current_project(conn),
         {:ok, chat} <- AiChat.resolve_approval(project, request_id, decision) do
      json(conn, %{chat: chat})
    else
      nil -> error(conn, 422, "missing_project", "Select a GitLab project before resolving an approval.")
      {:error, :invalid_approval_decision} -> error(conn, 400, "invalid_approval_decision", "Approval decision is invalid.")
      {:error, :approval_not_found} -> error(conn, 404, "approval_not_found", "Approval request is no longer pending.")
      {:error, reason} -> error(conn, 422, "approval_resolve_failed", inspect(reason))
    end
  end

  def approve(conn, _params), do: error(conn, 400, "missing_decision", "Approval decision is required.")

  @spec reset(Conn.t(), map()) :: Conn.t()
  def reset(conn, _params) do
    with %{} = project <- AuthPlug.current_project(conn) do
      :ok = AiChat.reset(project)
      json(conn, %{ok: true})
    else
      nil -> error(conn, 422, "missing_project", "Select a GitLab project before resetting AI chat.")
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
