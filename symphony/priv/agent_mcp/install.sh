#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: install.sh <payload.json>

Dispatches per-agent MCP installation to the adapter for payload.provider.
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
  echo "python3 is required for MCP installer payload parsing" >&2
  exit 69
fi

provider="$(
  python3 - "$payload" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

provider = payload.get("provider")
if not isinstance(provider, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", provider):
    raise SystemExit("invalid provider")

print(provider)
PY
)"

adapter="$ROOT_DIR/installers/$provider.sh"

if [[ ! -x "$adapter" ]]; then
  echo "unsupported agent provider or adapter is not executable: $provider" >&2
  exit 64
fi

exec "$adapter" "$payload"
