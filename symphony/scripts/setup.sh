#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INSTALL_SYSTEM_DEPS=0
SKIP_DB=0
SKIP_FRONTEND=0
SKIP_GITLAB_TEST=0
SKIP_BUILD=0
RUN_TESTS=0

usage() {
  cat <<'USAGE'
用法: ./scripts/setup.sh [选项]

选项:
  --install-system-deps   按当前平台尝试安装 elixir、node、postgresql
  --skip-db               跳过 mix ecto.create / mix ecto.migrate
  --skip-frontend         跳过 npm install 和前端构建
  --skip-gitlab-test      跳过 mix symphony.gitlab.test
  --skip-build            跳过前端 build 和 mix escript.build
  --test                  初始化后运行 mix test
  -h, --help              显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-system-deps)
      INSTALL_SYSTEM_DEPS=1
      ;;
    --skip-db)
      SKIP_DB=1
      ;;
    --skip-frontend)
      SKIP_FRONTEND=1
      ;;
    --skip-gitlab-test)
      SKIP_GITLAB_TEST=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --test)
      RUN_TESTS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

step() {
  printf '\n==> %s\n' "$1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  if ! has_cmd "$1"; then
    echo "缺少命令: $1" >&2
    echo "请先安装依赖，或运行: ./scripts/setup.sh --install-system-deps" >&2
    exit 1
  fi
}

install_system_deps() {
  step "安装系统依赖"

  case "$(uname -s)" in
    Darwin)
      if ! has_cmd brew; then
        echo "未找到 Homebrew，无法自动安装 macOS 系统依赖。" >&2
        echo "请手动安装 Elixir/Mix、Node.js/npm 和 PostgreSQL。" >&2
        exit 1
      fi

      brew install elixir node postgresql@16
      ;;

    Linux)
      if has_cmd mise; then
        echo "检测到 mise，将优先安装 mise.toml 中声明的 Erlang/Elixir 版本。"
        mise install
      fi

      if has_cmd apt-get; then
        sudo_or_root apt-get update
        sudo_or_root apt-get install -y elixir nodejs npm postgresql postgresql-contrib
      elif has_cmd dnf; then
        sudo_or_root dnf install -y elixir erlang nodejs npm postgresql-server postgresql-contrib
      elif has_cmd yum; then
        sudo_or_root yum install -y elixir erlang nodejs npm postgresql-server postgresql-contrib
      else
        echo "未识别 Linux 包管理器。" >&2
        echo "请手动安装 Elixir/Mix、Node.js/npm 和 PostgreSQL；生产环境建议使用 mise/asdf 或发行版包管理固定版本。" >&2
        exit 1
      fi
      ;;

    *)
      echo "不支持当前系统的自动系统依赖安装: $(uname -s)" >&2
      echo "请手动安装 Elixir/Mix、Node.js/npm 和 PostgreSQL。" >&2
      exit 1
      ;;
  esac
}

sudo_or_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif has_cmd sudo; then
    sudo "$@"
  else
    echo "需要 root 权限或 sudo 才能执行: $*" >&2
    exit 1
  fi
}

load_local_env() {
  if [[ -f .env.local ]]; then
    step "加载 .env.local"
    set -a
    # shellcheck disable=SC1091
    source .env.local
    set +a
  else
    echo "未发现 .env.local；可先执行: cp .env.example .env.local"
  fi
}

database_configured() {
  [[ -n "${SYMPHONY_DATABASE_URL:-}" ]] ||
    [[ -n "${DATABASE_URL:-}" ]] ||
    [[ "${SYMPHONY_STORE_BACKEND:-}" == "postgres" ]]
}

gitlab_configured() {
  [[ -n "${GITLAB_PROJECT_API_URL:-}" ]] &&
    [[ -n "${GITLAB_TOKEN:-}" ]] &&
    [[ "${GITLAB_TOKEN}" != "glpat_xxxxxxxxxxxxxxxxxxxx" ]]
}

setup_database() {
  if [[ "$SKIP_DB" -eq 1 ]]; then
    step "跳过数据库初始化"
    return
  fi

  if ! database_configured; then
    step "跳过数据库初始化"
    echo "未配置 SYMPHONY_DATABASE_URL / DATABASE_URL，运行时将使用 JSON fallback。"
    return
  fi

  step "初始化 PostgreSQL 数据库"
  if ! mix ecto.create; then
    echo "mix ecto.create 未成功；如果数据库已存在，将继续执行 migration。"
  fi
  mix ecto.migrate
}

setup_frontend() {
  if [[ "$SKIP_FRONTEND" -eq 1 ]]; then
    step "跳过前端依赖"
    return
  fi

  step "安装前端依赖"
  npm --prefix assets install

  if [[ "$SKIP_BUILD" -eq 0 ]]; then
    step "构建前端资源"
    npm --prefix assets run build
  fi
}

setup_gitlab() {
  if [[ "$SKIP_GITLAB_TEST" -eq 1 ]]; then
    step "跳过 GitLab 连通性校验"
    return
  fi

  if ! gitlab_configured; then
    step "跳过 GitLab 连通性校验"
    echo "GITLAB_PROJECT_API_URL 或 GITLAB_TOKEN 未配置，或仍为占位值。"
    return
  fi

  step "校验 GitLab 访问"
  mix symphony.gitlab.test
}

if [[ "$INSTALL_SYSTEM_DEPS" -eq 1 ]]; then
  install_system_deps
fi

step "检查基础命令"
require_cmd mix
require_cmd node
require_cmd npm

load_local_env

step "准备 Hex/Rebar"
mix local.hex --force
mix local.rebar --force

step "安装 Elixir 依赖"
mix deps.get

setup_frontend
setup_database

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  step "构建 CLI"
  mix escript.build
fi

setup_gitlab

if [[ "$RUN_TESTS" -eq 1 ]]; then
  step "运行测试"
  mix test
fi

step "初始化完成"
echo "启动命令: ./bin/symphony ./WORKFLOW.md --port ${SYMPHONY_PORT:-4000}"
