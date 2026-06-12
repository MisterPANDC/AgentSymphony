defmodule SymphonyElixirWeb.SpaController do
  use Phoenix.Controller, formats: [:html]

  alias Plug.Conn

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, File.read!(index_path()))
  rescue
    _ ->
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, fallback_html())
  end

  defp index_path do
    app_path = Application.app_dir(:symphony_elixir, "priv/static/index.html")

    if File.exists?(app_path) do
      app_path
    else
      Path.expand("../../../priv/static/index.html", __DIR__)
    end
  end

  defp fallback_html do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Symphony</title>
      </head>
      <body>
        <div id="root">Symphony frontend assets have not been built. Run npm install and npm run build in symphony/assets.</div>
      </body>
    </html>
    """
  end
end
