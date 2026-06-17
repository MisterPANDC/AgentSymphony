#!/usr/bin/env bash
set -euo pipefail
set +x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_SETTING_ID_ARG=""
PROJECT_REF_ARG=""
GIT_PROTOCOL="${SYMPHONY_GLAB_GIT_PROTOCOL:-ssh}"
USE_KEYRING="${SYMPHONY_GLAB_USE_KEYRING:-1}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/glab-login-from-project-token.sh [options]

Log glab in with the automation credential selected in Symphony settings.
For the chosen repository this uses either its Project Access Token or the
global Service Account token, matching the current Settings -> GitLab mode. The
token is decrypted through Symphony's existing TokenVault path and passed to
glab over stdin, so it does not appear in process arguments.

Options:
  --project-setting-id ID   Use a specific gitlab_project_settings.id
  --project-ref REF         Use a project_ref, path_with_namespace, or GitLab project id
  --git-protocol PROTOCOL   glab git protocol: ssh, https, or http (default: ssh)
  --use-keyring             Store the token in the OS keyring (default)
  --no-keyring              Store the token in glab's config file instead
  -h, --help                Show this help

Environment:
  SYMPHONY_PROJECT_SETTING_ID   Same as --project-setting-id
  SYMPHONY_PROJECT_REF          Same as --project-ref
  SYMPHONY_GLAB_GIT_PROTOCOL    Same as --git-protocol
  SYMPHONY_GLAB_USE_KEYRING     Set to 0 to disable keyring storage

Examples:
  ./scripts/glab-login-from-project-token.sh
  ./scripts/glab-login-from-project-token.sh --project-ref group/repo
  SYMPHONY_PROJECT_SETTING_ID=... ./scripts/glab-login-from-project-token.sh --no-keyring
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-setting-id)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--project-setting-id requires a value" >&2
        exit 2
      fi
      PROJECT_SETTING_ID_ARG="$2"
      shift
      ;;
    --project-ref)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--project-ref requires a value" >&2
        exit 2
      fi
      PROJECT_REF_ARG="$2"
      shift
      ;;
    --git-protocol)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--git-protocol requires a value" >&2
        exit 2
      fi
      GIT_PROTOCOL="$2"
      shift
      ;;
    --use-keyring)
      USE_KEYRING=1
      ;;
    --no-keyring)
      USE_KEYRING=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$GIT_PROTOCOL" in
  ssh|https|http)
    ;;
  *)
    echo "--git-protocol must be one of: ssh, https, http" >&2
    exit 2
    ;;
esac

case "$USE_KEYRING" in
  0|1)
    ;;
  *)
    echo "SYMPHONY_GLAB_USE_KEYRING must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ -n "$PROJECT_SETTING_ID_ARG" && -n "$PROJECT_REF_ARG" ]]; then
  echo "Use either --project-setting-id or --project-ref, not both." >&2
  exit 2
fi

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  if ! has_cmd "$1"; then
    echo "Missing command: $1" >&2
    exit 1
  fi
}

load_local_env() {
  if [[ -f .env.local ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env.local
    set +a
  fi
}

payload_file="$(mktemp)"
trap 'rm -f "$payload_file"' EXIT

require_cmd mix
require_cmd glab
load_local_env

export SYMPHONY_PROJECT_SETTING_ID="${PROJECT_SETTING_ID_ARG:-${SYMPHONY_PROJECT_SETTING_ID:-}}"
export SYMPHONY_PROJECT_REF="${PROJECT_REF_ARG:-${SYMPHONY_PROJECT_REF:-}}"

if ! mix run --no-start -e '
SymphonyElixir.Dotenv.load()

if SymphonyElixir.Store.configured_backend() == :postgres do
  {:ok, _} = Application.ensure_all_started(:ecto_sql)
  {:ok, _} = Application.ensure_all_started(:postgrex)
  {:ok, _repo} = SymphonyElixir.Repo.start_link()
end

{:ok, _store} = SymphonyElixir.Store.start_link()

blank_to_nil = fn
  value when is_binary(value) ->
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end

  _ ->
    nil
end

project_setting_id = blank_to_nil.(System.get_env("SYMPHONY_PROJECT_SETTING_ID"))
project_ref = blank_to_nil.(System.get_env("SYMPHONY_PROJECT_REF"))
projects = SymphonyElixir.Store.projects()

project =
  cond do
    is_binary(project_setting_id) ->
      Enum.find(projects, &(to_string(&1[:id]) == project_setting_id))

    is_binary(project_ref) ->
      Enum.find(projects, fn project ->
        project[:project_ref] == project_ref or
          project[:path_with_namespace] == project_ref or
          to_string(project[:project_id]) == project_ref
      end)

    true ->
      SymphonyElixir.Store.project()
  end

if is_nil(project) do
  selector =
    cond do
      is_binary(project_setting_id) -> "project setting id #{project_setting_id}"
      is_binary(project_ref) -> "project ref #{project_ref}"
      true -> "default project"
    end

  raise "No GitLab project setting found for #{selector}"
end

case SymphonyElixir.Store.automation_credential(project.id) do
  {:ok, %{token: token, mode: credential_mode}} when is_binary(token) and token != "" ->
    {:ok, config} = Symphony.GitLab.Config.from_project_setting(project, token)

    raw_url = config.gitlab_base_url

    uri =
      if String.contains?(raw_url, "://") do
        URI.parse(raw_url)
      else
        URI.parse("https://" <> raw_url)
      end

    protocol = uri.scheme || "https"

    unless protocol in ["https", "http"] do
      raise "Unsupported GitLab protocol: #{inspect(protocol)}"
    end

    hostname = uri.host || raise("GitLab base URL is missing a hostname: #{inspect(raw_url)}")
    default_port = if protocol == "https", do: 443, else: 80

    api_host =
      if is_integer(uri.port) and uri.port != default_port do
        "#{hostname}:#{uri.port}"
      else
        hostname
      end

    project_label = project[:path_with_namespace] || project[:project_ref] || project.id

    IO.puts(
      Enum.join(
        ["SYMPHONY_GLAB_LOGIN", protocol, hostname, api_host, project_label, project.id, credential_mode, token],
        "\t"
      )
    )

  {:error, reason} ->
    raise "Automation credential unavailable: #{inspect(reason)}"
end
' >"$payload_file"; then
  cat "$payload_file" >&2
  echo "Failed to read an automation credential from Symphony settings." >&2
  exit 1
fi

payload="$(grep $'^SYMPHONY_GLAB_LOGIN\t' "$payload_file" | tail -n 1 || true)"

if [[ -z "$payload" ]]; then
  cat "$payload_file" >&2
  echo "Failed to read an automation credential from Symphony settings." >&2
  exit 1
fi

IFS=$'\t' read -r marker protocol hostname api_host project_label project_setting_id credential_mode token <<<"$payload"

if [[ "$marker" != "SYMPHONY_GLAB_LOGIN" ]]; then
  echo "Failed to parse GitLab login output." >&2
  exit 1
fi

if [[ -z "${protocol:-}" || -z "${hostname:-}" || -z "${api_host:-}" || -z "${project_setting_id:-}" || -z "${credential_mode:-}" || -z "${token:-}" ]]; then
  echo "Missing protocol, hostname, api_host, project_setting_id, credential mode, or token in GitLab login output." >&2
  exit 1
fi

glab_args=(
  auth login
  --hostname "$hostname"
  --api-protocol "$protocol"
  --git-protocol "$GIT_PROTOCOL"
  --stdin
)

if [[ "$api_host" != "$hostname" ]]; then
  glab_args+=(--api-host "$api_host")
fi

if [[ "$USE_KEYRING" -eq 1 ]]; then
  glab_args+=(--use-keyring)
fi

printf '%s' "$token" | glab "${glab_args[@]}"
unset token
glab auth status --hostname "$hostname"
echo "glab login completed for ${project_label} (${project_setting_id}) on ${hostname} using ${credential_mode}."
