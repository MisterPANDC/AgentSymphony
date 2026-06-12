defmodule SymphonyElixirWeb.StaticAssetController do
  @moduledoc """
  Serves embedded and built frontend assets.
  """

  use Phoenix.Controller, formats: []

  alias Plug.Conn
  alias SymphonyElixirWeb.StaticAssets

  @spec dashboard_css(Conn.t(), map()) :: Conn.t()
  def dashboard_css(conn, _params), do: serve(conn, "/dashboard.css")

  @spec favicon(Conn.t(), map()) :: Conn.t()
  def favicon(conn, _params), do: serve(conn, "/favicon.png")

  @spec static(Conn.t(), map()) :: Conn.t()
  def static(conn, %{"path" => path_parts}) when is_list(path_parts) do
    relative_path = Path.join(path_parts)

    if String.contains?(relative_path, ["..", "\\"]) do
      send_resp(conn, 404, "Not Found")
    else
      file_path = static_file_path(["assets", relative_path])
      serve_file(conn, file_path)
    end
  end

  defp serve(conn, path) do
    case StaticAssets.fetch(path) do
      {:ok, content_type, body} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_resp(200, body)

      :error ->
        send_resp(conn, 404, "Not Found")
    end
  end

  defp serve_file(conn, file_path) do
    case File.read(file_path) do
      {:ok, body} ->
        conn
        |> put_resp_content_type(content_type(file_path))
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_resp(200, body)

      _ ->
        send_resp(conn, 404, "Not Found")
    end
  end

  defp static_file_path(path_parts) do
    app_path = Application.app_dir(:symphony_elixir, Path.join(["priv/static" | path_parts]))

    if File.exists?(app_path) do
      app_path
    else
      Path.expand(Path.join(["../../../priv/static" | path_parts]), __DIR__)
    end
  end

  defp content_type(path) do
    case Path.extname(path) do
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".svg" -> "image/svg+xml"
      ".png" -> "image/png"
      ".ico" -> "image/x-icon"
      ".json" -> "application/json"
      _ -> "application/octet-stream"
    end
  end
end
