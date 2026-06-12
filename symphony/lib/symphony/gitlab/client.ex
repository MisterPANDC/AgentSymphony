defmodule Symphony.GitLab.Client do
  @moduledoc """
  GitLab REST API client scoped to one configured project.
  """

  require Logger

  alias Symphony.GitLab.{Config, Error}

  @timeout_ms 30_000

  @spec get_project(Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_project(%Config{} = config), do: request(config, :get, project_path(config), [])

  @spec list_project_issues(Config.t(), map() | keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_project_issues(%Config{} = config, params \\ %{}) do
    paginated_get(config, project_path(config) <> "/issues", params)
  end

  @spec get_project_issue(Config.t(), integer() | String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_project_issue(%Config{} = config, issue_iid) do
    request(config, :get, project_path(config) <> "/issues/#{issue_iid}", [])
  end

  @spec update_project_issue(Config.t(), integer() | String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_project_issue(%Config{} = config, issue_iid, attrs) when is_map(attrs) do
    request(config, :put, project_path(config) <> "/issues/#{issue_iid}", json: attrs)
  end

  @spec list_issue_notes(Config.t(), integer() | String.t(), map() | keyword()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def list_issue_notes(%Config{} = config, issue_iid, params \\ %{}) do
    paginated_get(config, project_path(config) <> "/issues/#{issue_iid}/notes", params)
  end

  @spec create_issue_note(Config.t(), integer() | String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_issue_note(%Config{} = config, issue_iid, body) when is_binary(body) do
    request(config, :post, project_path(config) <> "/issues/#{issue_iid}/notes", json: %{body: body})
  end

  @spec validate(Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def validate(%Config{} = config) do
    with :ok <- validate_api_root(config),
         {:ok, project} <- get_project(config),
         {:ok, issues} <- list_project_issues(config, state: "all", per_page: 1) do
      {:ok,
       %{
         project: project,
         issue_api_reachable: is_list(issues),
         token_permission_mode: "read_only_or_read_write"
       }}
    end
  end

  @spec validate_api_root(Config.t()) :: :ok | {:error, Error.t()}
  def validate_api_root(%Config{gitlab_api_root: api_root}) when is_binary(api_root) do
    if String.contains?(api_root, "/api/v4") do
      :ok
    else
      {:error, %Error{type: :invalid_config, message: "GitLab API root must contain /api/v4"}}
    end
  end

  def validate_api_root(_config),
    do: {:error, %Error{type: :invalid_config, message: "GitLab API root is missing"}}

  defp paginated_get(config, path, params) do
    params = params |> Map.new() |> Map.put_new(:per_page, config.sync_page_size)
    do_paginated_get(config, path, params, [])
  end

  defp do_paginated_get(config, path, params, acc) do
    case request(config, :get, path, params: params, raw_response: true) do
      {:ok, response} ->
        body = normalize_list_body(response.body)
        next_page = next_page(response)
        acc = acc ++ body

        if next_page do
          do_paginated_get(config, path, Map.put(params, :page, next_page), acc)
        else
          {:ok, acc}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_list_body(body) when is_list(body), do: body
  defp normalize_list_body(_body), do: []

  defp request(%Config{} = config, method, path, opts) do
    with :ok <- validate_api_root(config) do
      raw_response? = Keyword.get(opts, :raw_response, false)

      req_opts = [
        method: method,
        url: config.gitlab_api_root <> path,
        headers: [{"PRIVATE-TOKEN", config.token}, {"accept", "application/json"}],
        receive_timeout: @timeout_ms
      ]

      req_opts =
        opts
        |> Keyword.take([:params, :json])
        |> Keyword.merge(req_opts)
        |> Keyword.merge(req_extra_options())

      case Req.request(req_opts) do
        {:ok, %Req.Response{} = response} ->
          handle_response(response, raw_response?)

        {:error, reason} ->
          message = reason |> inspect() |> Config.redact()
          Logger.warning("GitLab REST request failed: #{message}")
          {:error, %Error{type: :network_error, message: message}}
      end
    end
  end

  defp handle_response(%Req.Response{status: status} = response, raw_response?)
       when status >= 200 and status < 300 do
    if raw_response?, do: {:ok, response}, else: {:ok, response.body}
  end

  defp handle_response(%Req.Response{} = response, _raw_response?) do
    error = error_from_response(response)
    Logger.warning("GitLab REST request failed status=#{response.status} type=#{error.type} message=#{Config.redact(error.message)}")
    {:error, error}
  end

  defp error_from_response(%Req.Response{status: status, body: body} = response) do
    type =
      cond do
        status == 401 -> :unauthorized
        status == 403 -> :forbidden
        status == 404 -> :not_found
        status == 429 -> :rate_limited
        status in 400..499 -> :validation_error
        status >= 500 -> :server_error
        true -> :unexpected_response
      end

    %Error{
      type: type,
      status: status,
      message: body_message(body, status) |> Config.redact(),
      retry_after: first_header(response, "retry-after")
    }
  end

  defp body_message(%{"message" => message}, _status) when is_binary(message), do: message
  defp body_message(%{"error" => message}, _status) when is_binary(message), do: message
  defp body_message(body, status) when is_binary(body), do: body <> " (HTTP #{status})"
  defp body_message(body, status), do: inspect(body) <> " (HTTP #{status})"

  defp project_path(%Config{gitlab_project_path_param: path_param}) do
    "/projects/#{path_param}"
  end

  defp req_extra_options do
    Application.get_env(:symphony_elixir, :gitlab_req_options, [])
  end

  defp next_page(%Req.Response{} = response) do
    case first_header(response, "x-next-page") do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        response
        |> first_header("link")
        |> next_page_from_link()
    end
  end

  defp next_page_from_link(nil), do: nil

  defp next_page_from_link(link) when is_binary(link) do
    link
    |> String.split(",")
    |> Enum.find_value(fn part ->
      if String.contains?(part, ~s(rel="next")) do
        case Regex.run(~r/[?&]page=([^&>]+)/, part) do
          [_, page] -> URI.decode(page)
          _ -> nil
        end
      end
    end)
  end

  defp first_header(%Req.Response{headers: headers}, wanted) do
    headers
    |> header_value(String.downcase(wanted))
    |> normalize_header_value()
  end

  defp header_value(headers, wanted) when is_map(headers) do
    Map.get(headers, wanted) || Map.get(headers, String.to_atom(wanted)) || list_header(Map.to_list(headers), wanted)
  end

  defp header_value(headers, wanted) when is_list(headers), do: list_header(headers, wanted)
  defp header_value(_headers, _wanted), do: nil

  defp normalize_header_value([value | _]) when is_binary(value), do: value
  defp normalize_header_value(value) when is_binary(value), do: value
  defp normalize_header_value(_value), do: nil

  defp list_header(headers, wanted) do
    Enum.find_value(headers, fn
      {key, [value | _]} when is_binary(key) ->
        if String.downcase(key) == wanted, do: value

      {key, value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == wanted, do: value

      _ ->
        nil
    end)
  end
end
