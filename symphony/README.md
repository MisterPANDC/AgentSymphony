# Symphony GitLab

GitLab-native 的 Symphony 运行时，用 Elixir/Phoenix 提供本地调度服务，用 React 构建 operator 控制台。它从原 Elixir 原型迁移而来，但运行时不再依赖 Linear：GitLab 负责项目、issue 和 note，Symphony 自己持久化工作流状态、阻塞关系、运行记录、同步游标和人工介入状态。

## 亮点

- **GitLab 原生集成**：支持本地单项目 token 模式，也支持云端 GitLab OIDC 登录、多用户选择已加入 repo、issue 同步、note 同步和必要的 GitLab 写入。
- **内部工作流**：`triage`、`todo`、`in_progress`、`review`、`merging`、`rework`、`done`、`canceled` 等阶段存储在 Symphony 数据库中；依赖阻塞和人工介入作为 issue/run 的阻塞状态单独记录，不依赖 GitLab 付费工作流能力。
- **持久化运行态**：agent runs、run events、runtime blocks、operator-input、sync cursors 均可落库，重启后可恢复观察。
- **Linear 风格控制台**：高密度 issue dashboard、issue drawer、blocker editor、agent controls、run history、settings 和 Run Monitor。
- **可降级开发体验**：未配置 PostgreSQL 时使用本地 JSON store，便于本机快速试用。

## 快速开始

本地单项目模式下，准备好 Elixir/Mix、Node.js/npm，以及一个具备 GitLab API 权限的 token 后：

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
| GitLab token / Project Access Token | 本地模式访问 GitLab API；云端 OIDC 模式中由每个项目在设置页保存 Project Access Token |

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

`GITLAB_PROJECT_API_URL` 填的是 GitLab REST API endpoint，不是浏览器里的项目页面 URL。它不会直接出现在 GitLab 网页界面中，需要根据项目页面 URL 构造：

```text
项目页面 URL: https://gitlab.example.com/group/project
API URL:     https://gitlab.example.com/api/v4/projects/group%2Fproject
```

规则：

1. 取 GitLab 实例根地址，例如 `https://gitlab.example.com`。
2. 追加固定路径 `/api/v4/projects/`。
3. 再追加项目标识。可以使用 numeric project id，也可以使用 namespace path。
4. 如果使用 namespace path，需要把路径里的 `/` 编码成 `%2F`。例如 `group/project` 写成 `group%2Fproject`，`team/subgroup/app` 写成 `team%2Fsubgroup%2Fapp`。

例如项目页面是：

```text
https://gitlab.example.com/team/subgroup/app
```

则推荐配置为：

```env
GITLAB_PROJECT_API_URL=https://gitlab.example.com/api/v4/projects/team%2Fsubgroup%2Fapp
```

如果已知 GitLab numeric project id，也可以直接使用 id，避免手工编码路径：

```env
GITLAB_PROJECT_API_URL=https://gitlab.example.com/api/v4/projects/123
```

不要把 `/api/v4/projects/...` 拼到项目页面 URL 后面。下面这种写法是错误的，因为 `team/subgroup/app` 是项目网页路径，不是 GitLab 实例根地址，`group%2Fproject` 也只是占位示例：

```env
GITLAB_PROJECT_API_URL=https://gitlab.example.com/team/subgroup/app/api/v4/projects/group%2Fproject
```

也可以使用拆分配置，让 Symphony 自动处理 project path 编码：

```env
GITLAB_BASE_URL=https://gitlab.example.com
GITLAB_PROJECT_PATH=team/subgroup/app
# 或使用 numeric id:
# GITLAB_PROJECT_ID=123
```

启用 PostgreSQL：

```env
SYMPHONY_STORE_BACKEND=postgres
SYMPHONY_DATABASE_URL=postgres://postgres:postgres@localhost:5432/symphony_dev
```

`GITLAB_TOKEN` 只用于本地单项目模式，不会发送给浏览器；settings 和 monitor API 只返回脱敏状态。

启用 GitLab OIDC 登录：

```env
SYMPHONY_AUTH_MODE=gitlab_oidc
SYMPHONY_PUBLIC_URL=https://symphony.example.com
SYMPHONY_SESSION_SECRET=replace-with-a-stable-random-secret-at-least-64-bytes

GITLAB_OIDC_ISSUER=https://gitlab.example.com
GITLAB_OIDC_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITLAB_OIDC_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITLAB_OIDC_SCOPES=openid profile email api
# 可选；未设置时会复用 SYMPHONY_SESSION_SECRET / SECRET_KEY_BASE
SYMPHONY_TOKEN_ENCRYPTION_SECRET=replace-with-a-stable-random-secret
```

在自建 GitLab 创建 OAuth application，redirect URI 填：

```text
https://symphony.example.com/auth/gitlab/callback
```

登录后，Symphony 会通过用户 OAuth 拉取该用户加入的 repo 列表。用户选择 repo 后，Symphony 按该用户在 GitLab 上的 project membership 计算权限：Reporter 及以上可访问只读页面，Developer 及以上可执行用户发起的写操作，Maintainer 及以上可进入运维/设置操作。用户在 Symphony 中发起的 issue 编辑、评论、workflow 完成后关闭 GitLab issue 等操作，全部使用当前登录用户的 OAuth token 调 GitLab；Symphony 不会让用户在界面中执行超过其 GitLab 账号权限的写操作。

云端 OIDC 模式下，每个 repo 还需要在 `Settings -> GitLab` 填写一次 GitLab Project Access Token。这个 token 保存后会加密落库，前端和 API 只显示 `configured` / `missing` 状态，不再回显明文。如果当前项目未设置 Project Access Token，控制台会提示进入设置页填写。后台同步 GitLab 数据以及 Agent 对 GitLab 的写操作全部使用该项目的 Project Access Token，不使用任何一个登录用户的 OAuth token。

需要明确的权限边界：

1. Agent 写 GitLab 时使用 Project Access Token，因此 Agent 可能执行当前登录用户自身没有权限执行的 GitLab 写操作。Project Access Token 的权限应按项目维度最小化配置，并只授予 Symphony/Agent 确实需要的能力。
2. 罕见情况下，如果 Agent 或后台同步通过 Project Access Token 读取到了某个当前用户没有 GitLab 权限直接读取的数据，该数据可能已经进入 Symphony 数据库，用户可能通过 Symphony 数据库或后续页面间接看到。当前实现主要按 repo membership 做访问控制，绝大多数 issue/note 信息不涉及更细粒度权限；这个细粒度数据可见性风险暂不额外处理。

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

未配置 `SYMPHONY_DATABASE_URL` / `DATABASE_URL` 时，应用使用 JSON fallback。JSON fallback 只适合本地试用；云端多用户、多 repo、OIDC token 和 Project Access Token 场景建议显式配置 PostgreSQL。

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
