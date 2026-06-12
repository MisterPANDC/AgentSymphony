# Symphony GitLab

GitLab-native 的 Symphony 运行时，用 Elixir/Phoenix 提供本地调度服务，用 React 构建 operator 控制台。它从原 Elixir 原型迁移而来，但运行时不再依赖 Linear：GitLab 负责项目、issue 和 note，Symphony 自己持久化工作流状态、阻塞关系、运行记录、同步游标和人工介入状态。

## 亮点

- **GitLab 原生集成**：支持 GitLab project API URL、project path / numeric id、issue 同步、note 同步和必要的 GitLab 写入。
- **内部工作流**：`triage`、`todo`、`in_progress`、`blocked`、`review`、`done`、`canceled` 等状态存储在 Symphony 数据库中，不依赖 GitLab 付费工作流能力。
- **持久化运行态**：agent runs、run events、runtime blocks、operator-input、sync cursors 均可落库，重启后可恢复观察。
- **Linear 风格控制台**：高密度 issue dashboard、issue drawer、blocker editor、agent controls、run history、settings 和 Run Monitor。
- **可降级开发体验**：未配置 PostgreSQL 时使用本地 JSON store，便于本机快速试用。

## 快速开始

准备好 Elixir/Mix、Node.js/npm，以及一个具备 GitLab API 权限的 token 后：

```bash
cd symphony
cp .env.example .env.local
# 编辑 .env.local，填入 GitLab 项目 API 地址和 token

./scripts/setup.sh
./bin/symphony ./WORKFLOW.md --port 4000
```

打开 `http://127.0.0.1:4000` 进入控制台。

## 环境要求

| 依赖 | 用途 |
| --- | --- |
| Elixir / Mix | 后端运行时、任务、escript 构建 |
| Node.js / npm | React 前端依赖安装和构建 |
| PostgreSQL | 生产/规范持久化后端 |
| GitLab token | 访问项目、issue 和 note API |

项目提供 `mise.toml` 固定 Erlang/Elixir 版本。Linux 或 CI 环境推荐在镜像/主机初始化层预装依赖，再运行项目 setup。

## 配置

复制示例配置：

```bash
cp .env.example .env.local
```

最小配置：

```env
GITLAB_PROJECT_API_URL=https://gitlab.example.com/api/v4/projects/group%2Fproject
GITLAB_TOKEN=glpat_xxxxxxxxxxxxxxxxxxxx

SYMPHONY_BIND_HOST=127.0.0.1
SYMPHONY_PORT=4000
```

启用 PostgreSQL：

```env
SYMPHONY_STORE_BACKEND=postgres
SYMPHONY_DATABASE_URL=postgres://postgres:postgres@localhost:5432/symphony_dev
```

`GITLAB_TOKEN` 只在服务端使用，不会发送给浏览器；settings 和 monitor API 只返回脱敏状态。

## 初始化脚本

`scripts/setup.sh` 是统一入口：

```bash
./scripts/setup.sh
```

默认执行：

1. 检查 `mix`、`node`、`npm`。
2. 安装 Hex/Rebar、Mix 依赖和 npm 依赖。
3. 如果配置了 PostgreSQL，执行 `mix ecto.create` 和 `mix ecto.migrate`。
4. 构建前端资源到 `priv/static`。
5. 构建 `bin/symphony`。
6. 如果 GitLab 配置完整且 token 不是占位值，执行连通性校验。

常用选项：

| 命令 | 说明 |
| --- | --- |
| `./scripts/setup.sh --skip-db` | 跳过数据库 create/migrate |
| `./scripts/setup.sh --skip-frontend` | 跳过 npm install 和前端构建 |
| `./scripts/setup.sh --skip-build` | 跳过前端 build 和 escript build |
| `./scripts/setup.sh --skip-gitlab-test` | 跳过 GitLab 连通性校验 |
| `./scripts/setup.sh --test` | 初始化后运行 `mix test` |
| `./scripts/setup.sh --install-system-deps` | best-effort 安装系统依赖，仅建议本地开发使用 |

`make setup` 会调用同一个脚本。

## 数据库

迁移文件位于 `priv/repo/migrations`，覆盖项目、issue、note、workflow、dependency、run、block 和 sync cursor 等表。

手动初始化：

```bash
mix ecto.create
mix ecto.migrate
```

未配置 `SYMPHONY_DATABASE_URL` / `DATABASE_URL` 时，应用使用 JSON fallback。生产环境建议显式配置 PostgreSQL。

## 开发命令

```bash
mix specs.check
mix compile --warnings-as-errors
mix test
npm --prefix assets run build
mix escript.build
```

PostgreSQL 后端测试：

```bash
SYMPHONY_STORE_BACKEND=postgres \
SYMPHONY_DATABASE_URL=postgres://postgres:postgres@localhost:5432/symphony_test \
mix test --include postgres
```

GitLab 配置校验：

```bash
mix symphony.gitlab.test
```

交互式写入 GitLab 配置：

```bash
mix symphony.gitlab.setup
```

## 运行与接口

启动：

```bash
./bin/symphony ./WORKFLOW.md --port 4000
```

常用入口：

| 地址 | 说明 |
| --- | --- |
| `http://127.0.0.1:4000` | Operator 控制台 |
| `GET /api/v1/state` | 运行态 JSON 快照 |
| `POST /api/v1/refresh` | 手动触发刷新 |
| `GET /api/v1/:issue_identifier` | 单个 issue 调试视图 |

## Linux / 生产部署

生产部署建议把系统依赖放在基础镜像或主机初始化层，不依赖应用脚本临时安装：

```bash
elixir --version
mix --version
node --version
npm --version
psql --version
```

如果使用 `mise`：

```bash
mise install
./scripts/setup.sh
```

`--install-system-deps` 只做本地开发的 best-effort：

- macOS：使用 Homebrew 安装 `elixir`、`node`、`postgresql@16`。
- Linux：优先执行 `mise install`，再尝试 `apt` / `dnf` / `yum` 安装发行版包。

## 目录结构

```text
symphony/
  assets/                 React/Vite 前端
  config/                 Elixir 配置
  lib/symphony/           GitLab client 与 mapper
  lib/symphony_elixir/    核心运行时、Store、Orchestrator、Sync
  lib/symphony_elixir_web Phoenix API 与静态资源服务
  priv/repo/migrations    PostgreSQL schema
  scripts/setup.sh        统一初始化入口
  WORKFLOW.md             默认 workflow 配置
```
