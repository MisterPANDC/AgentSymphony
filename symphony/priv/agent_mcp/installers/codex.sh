#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: codex.sh <payload.json>

Reconciles an individual Codex home's MCP servers using `codex mcp`.
Only MCP server names registered in payload.registeredMcpServerNames are removed
when no longer selected. Unregistered MCP servers already present in CODEX_HOME
are left untouched and surfaced by the Symphony UI.
USAGE
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

payload="$1"

if [[ ! -f "$payload" ]]; then
  echo "payload not found: $payload" >&2
  exit 66
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for Codex MCP installation" >&2
  exit 69
fi

python3 - "$payload" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys


def validate_server(name, server):
    if not isinstance(server, dict):
        raise ValueError("MCP server entries must be objects")

    command = server.get("command")
    args = server.get("args", [])
    env = server.get("env", {})
    startup_timeout_sec = server.get("startup_timeout_sec")

    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise ValueError(f"invalid MCP server name: {name!r}")

    if not isinstance(command, str) or not command.strip():
        raise ValueError(f"MCP server {name} is missing command")

    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        raise ValueError(f"MCP server {name} args must be a string list")

    if not isinstance(env, dict) or not all(isinstance(key, str) and isinstance(value, str) for key, value in env.items()):
        raise ValueError(f"MCP server {name} env must be a string map")

    if startup_timeout_sec is not None and (not isinstance(startup_timeout_sec, int) or startup_timeout_sec <= 0):
        raise ValueError(f"MCP server {name} startup_timeout_sec must be positive")

    return {
        "name": name,
        "command": command,
        "args": args,
        "env": env,
        "startup_timeout_sec": startup_timeout_sec,
    }


def run_codex(home, args, check=True):
    env = dict(os.environ)
    env["CODEX_HOME"] = home
    result = subprocess.run([codex, *args], text=True, capture_output=True, env=env)
    output = (result.stdout + result.stderr).strip()
    if check and result.returncode != 0:
        raise RuntimeError(f"codex {' '.join(args)} failed with {result.returncode}: {output}")
    return result.returncode, output


def current_servers(home):
    status, output = run_codex(home, ["mcp", "list", "--json"])
    if status != 0:
        return {}

    servers = json.loads(output or "[]")
    return {server["name"]: server for server in servers if isinstance(server, dict) and isinstance(server.get("name"), str)}


def add_server(home, server):
    args = ["mcp", "add", server["name"]]
    if server["startup_timeout_sec"] is not None:
        args.extend(["-c", f"mcp_servers.{server['name']}.startup_timeout_sec={server['startup_timeout_sec']}"])
    for key in sorted(server["env"]):
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            raise ValueError(f"MCP server {server['name']} has invalid env key: {key!r}")
        args.extend(["--env", f"{key}={server['env'][key]}"])
    args.extend(["--", server["command"], *server["args"]])
    run_codex(home, args)


with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

if payload.get("provider") != "codex":
    raise SystemExit("codex installer received non-codex payload")

home = payload.get("home")
if not isinstance(home, str) or not home:
    raise SystemExit("payload.home is required")

mcp_servers = payload.get("mcpServers", {})
if not isinstance(mcp_servers, dict):
    raise SystemExit("payload.mcpServers must be an object")

registered_names = payload.get("registeredMcpServerNames", [])
if not isinstance(registered_names, list) or not all(isinstance(name, str) for name in registered_names):
    raise SystemExit("payload.registeredMcpServerNames must be a string list")

desired = {name: validate_server(name, server) for name, server in sorted(mcp_servers.items())}
registered = set(registered_names)
os.makedirs(home, mode=0o700, exist_ok=True)

codex = shutil.which("codex")
if codex is None:
    raise SystemExit("codex executable was not found")

current = current_servers(home)
desired_names = set(desired)

removed = []
for name in sorted(set(current) & registered - desired_names):
    run_codex(home, ["mcp", "remove", name])
    removed.append(name)

added = []
for name, server in desired.items():
    if name in current:
        run_codex(home, ["mcp", "remove", name])
    add_server(home, server)
    added.append(name)

unregistered = sorted(set(current) - registered)
print(f"Codex MCP reconcile completed: {len(added)} desired, {len(removed)} removed, {len(unregistered)} unregistered preserved")
if unregistered:
    print("unregistered preserved: " + ", ".join(unregistered))
PY
