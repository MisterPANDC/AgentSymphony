# AgentSymphony

Native Symphony implementation without Linear, specialized for long-horizon agents.

> In this [demo video](https://player.vimeo.com/video/1186371009?h=5626e4b899), Symphony monitors a Linear board for work and spawns agents to handle the tasks. The agents complete the tasks and provide proof of work: CI status, PR review feedback, complexity analysis, and walkthrough videos. When accepted, the agents land the PR safely. Engineers do not need to supervise Codex; they can manage the work at a higher level.

## 项目背景

本项目基于 OpenAI 开源的 Symphony 框架：

- [openai/symphony](https://github.com/openai/symphony)
- [Open-source Codex orchestration with Symphony](https://oapenai.com/zh-Hans-CN/index/open-source-codex-orchestration-symphony/)

在原 Symphony 实现的基础上，本项目针对现有流程中的平台依赖、Agent 编排方式和工程闭环能力进行了优化与改进。

## 主要改进

### 1. 简化平台依赖（gitlab_spec.md）

当前 Symphony 的实现完全依赖 Linear 平台作为 Issue 控制面板来管理整个仓库。一个开发项目可能形成 `Symphony -> GitHub -> Linear` 的多平台关系，这种依赖显得冗余，也会带来团队费用和维护成本。

本项目简化了平台依赖，将控制面板前端也纳入 Symphony 实现中，并使用可自搭建的 GitLab 免费版作为项目代码管理平台，后续也可以方便地支持 GitHub。

### 2. 调整 Coding Agent 编排方式

当前 Symphony 对 Coding Agent 的调用仍停留在几个月前的 Codex 调用方式：针对一个 Issue，不断调用 Codex app-server client。在 Coding Agent 执行 long-horizon tasks 的能力不断提升的背景下，Symphony 对 Agent 的编排方式也应该随之调整。

例如，现在可以使用 Codex 内置的 `/goal` 模式，让 Codex 在内部持续执行，直到满足 Issue 关闭条件。对于 long-horizon tasks，任务需求和边界也需要被清晰定义。为降低这部分工作量，本项目可以使用 Agent 辅助 Issue 编写，自动补充边界条件；在需求还不够清楚时，也可以直接与 Agent 对话，持续细化需求，直到其达到可转换为 Issue 的完整定义。

此外，很多简单清晰的小改动并不需要使用 `/goal` 模式。因此，Symphony 在新建 Issue 时还提供 `oneshot` 模式，用于直接完成较简单的 Issue。

### 3. 强化端到端工程闭环

在 Agent long-horizon tasks 能力增强的背景下，只要能让 Agent 通过设计好的工作流完成测试等细节工作，就可以实现端到端代码编写的自动化闭环，减少人工对 Agent 产出代码的搬运和处理。

但当前开发团队在流程闭环建设上仍可能存在缺口，Symphony 系统在这种情况下也无法良好运行：

> Symphony works best in codebases that have adopted [harness engineering](https://openai.com/index/harness-engineering/). Symphony is the next step -- moving from managing coding agents to managing work that needs to get done.

因此，本项目在 Symphony 实现中加入了 AI 助手，用于直接检查代码仓库和 Harness 环境设置，帮助确认还需要完善哪些地方，最终实现 Agent 闭环。
