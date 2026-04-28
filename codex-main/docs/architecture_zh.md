# Codex 项目架构分析（中文）

本文基于当前仓库代码结构整理，目标不是逐个 crate 解释，而是回答三个核心问题：

1. 这个仓库的真正核心在哪里？
2. 交互式 CLI、非交互式执行、IDE/SDK 为什么能共用一套后端？
3. 配置、工具调用、沙箱、持久化、扩展能力分别落在哪一层？

## 1. 项目总体判断

`codex-main` 是一个以 Rust 为核心的 monorepo，外层包了一层分发与 SDK 生态。

从架构上看，它不是“一个 CLI 项目”，而是“四层结构”：

1. **入口层**：命令行、TUI、SDK、桌面/IDE 集成入口。
2. **协议层**：统一的 `app-server` / JSON-RPC 模型，把不同前端收敛到同一接口。
3. **核心运行时**：线程、回合、工具、模型调用、权限、技能、MCP、插件等真正的 agent 能力。
4. **基础设施层**：沙箱、执行环境、JSONL rollout、SQLite 状态库、遥测、构建与发布。

这套项目最关键的设计点是：

> **无论是 TUI、`codex exec`、IDE 扩展，还是 Python SDK，最终都尽量收敛到 `app-server` 这一层，而不是各自直接操作 core。**

这使得交互面不同，但会话模型、事件流、权限语义、线程管理和工具系统可以保持一致。

## 2. 顶层目录怎么分工

| 目录 | 角色 |
| --- | --- |
| [`codex-rs`](../codex-rs) | 主体代码；Rust workspace，核心架构都在这里 |
| [`codex-cli`](../codex-cli) | npm 分发层；现在主要是原生 Rust 二进制的 Node 启动器 |
| [`sdk/typescript`](../sdk/typescript) | TypeScript SDK，封装 CLI 进程与 JSONL 事件 |
| [`sdk/python`](../sdk/python) | Python SDK，直接封装 `codex app-server` JSON-RPC v2 |
| [`docs`](../docs) | 用户与开发文档 |
| [`scripts`](../scripts) | 安装、发布、调试与仓库维护脚本 |
| [`tools`](../tools) | 辅助工具，例如参数注释 lint |
| [`patches`](../patches) / [`third_party`](../third_party) | 第三方依赖补丁与第三方源码 |

如果只抓主干，建议把注意力集中在这几个路径：

- [`codex-rs/cli/src/main.rs`](../codex-rs/cli/src/main.rs)
- [`codex-rs/tui/src/lib.rs`](../codex-rs/tui/src/lib.rs)
- [`codex-rs/app-server/src/lib.rs`](../codex-rs/app-server/src/lib.rs)
- [`codex-rs/app-server/src/message_processor.rs`](../codex-rs/app-server/src/message_processor.rs)
- [`codex-rs/core/src/lib.rs`](../codex-rs/core/src/lib.rs)
- [`codex-rs/core/src/thread_manager.rs`](../codex-rs/core/src/thread_manager.rs)
- [`codex-rs/core/src/codex_thread.rs`](../codex-rs/core/src/codex_thread.rs)
- [`codex-rs/core/src/codex.rs`](../codex-rs/core/src/codex.rs)
- [`codex-rs/rollout/src/recorder.rs`](../codex-rs/rollout/src/recorder.rs)
- [`codex-rs/state/src/lib.rs`](../codex-rs/state/src/lib.rs)

## 3. 一张图看整体分层

```text
用户 / IDE / 脚本
    |
    | 入口
    v
codex CLI / TUI / exec / TypeScript SDK / Python SDK
    |
    | 统一收敛
    v
app-server 协议层
    - JSON-RPC v2
    - Thread / Turn / Item
    - stdio / websocket
    |
    | 调度
    v
core 运行时
    - ThreadManager / CodexThread / Codex
    - 模型调用
    - tool router
    - skills / MCP / plugins / apps
    - approvals / sandbox / exec policy
    |
    | 依赖基础设施
    v
执行与持久化
    - sandboxing / windows-sandbox / exec-server
    - rollout(JSONL)
    - state(SQLite)
    - telemetry / auth / backend clients
```

## 4. 入口层：用户到底是怎么进入系统的

### 4.1 npm 包不是核心实现，而是原生二进制启动器

[`codex-cli/bin/codex.js`](../codex-cli/bin/codex.js) 会根据平台解析目标三元组，找到对应的预编译原生包，然后把命令行参数转发给 Rust 二进制。

这说明当前分发模型是：

- **运行时核心是 Rust**
- **Node 只负责跨平台安装分发和启动**

同时 [`codex-cli/README.md`](../codex-cli/README.md) 也明确说明旧版 TypeScript CLI 已被 Rust 版本取代。

### 4.2 Rust CLI 是真正的命令分发器

[`codex-rs/cli/src/main.rs`](../codex-rs/cli/src/main.rs) 是统一入口，主要子命令包括：

- 交互式 TUI
- `exec` 非交互执行
- `review`
- `mcp` / `mcp-server`
- `app-server`
- `sandbox`
- `cloud`

这个文件很重要，因为它展示了一个明确的架构事实：

- 交互式模式走 `codex_tui::run_main`
- 非交互式模式走 `codex_exec::run_main`
- IDE/外部集成可以直接走 `codex app-server`

但这些路径最终并不是三套不同内核，而是向下收敛。

## 5. 协议层：`app-server` 是整个项目的收敛点

### 5.1 `app-server` 不是附属功能，而是系统总线

[`codex-rs/app-server/README.md`](../codex-rs/app-server/README.md) 给出的模型非常清楚：系统把交互抽象成三层对象：

- **Thread**：会话
- **Turn**：一次问答/操作回合
- **Item**：回合内产生的具体条目，比如用户输入、工具调用、文件修改、agent message

这是整个项目最核心的领域模型。

### 5.2 为什么它重要

`app-server` 的价值不在于“暴露一个 RPC 接口”，而在于它把这些能力统一抽象出来：

- 会话生命周期
- turn 的启动、中断、steer
- 流式事件
- 审批请求
- 配置读写
- 文件系统操作
- 模型列表
- 技能、MCP、插件、Apps
- 账户与认证
- 命令执行

也就是说，**前端看到的是协议对象，而不是 core 内部细节**。

### 5.3 TUI 和 exec 也故意通过 app-server 访问能力

这点是本仓库最值得注意的架构决策之一。

[`codex-rs/app-server-client/src/lib.rs`](../codex-rs/app-server-client/src/lib.rs) 的注释写得很直白：这个 crate 为 TUI 和 exec 提供统一的 in-process app-server facade。  
换句话说：

- 即使在同一进程内
- 也尽量维持和远程 `app-server` 一致的请求/通知/事件模型

这带来的好处是：

- 交互式 TUI、headless exec、远程 IDE 客户端共享同一语义
- 协议层可以做 schema 生成、版本兼容与测试
- 新前端接入时只要实现协议，不必直接碰 core

## 6. 前端形态：TUI、exec、SDK 各自扮演什么角色

### 6.1 TUI：交互外壳，不是业务内核

[`codex-rs/tui/src/lib.rs`](../codex-rs/tui/src/lib.rs) 说明了 TUI 的定位：

- 它负责终端 UI、输入、渲染、picker、onboarding、状态展示
- 它可以启动 **嵌入式 app-server**
- 也可以连到 **远程 websocket app-server**

也就是说，TUI 是一个前端壳层，而不是 agent 内核本身。

### 6.2 `exec`：无 UI 的 headless 客户端

[`codex-rs/exec/src/lib.rs`](../codex-rs/exec/src/lib.rs) 的实现路径与 TUI 很像，只是它不渲染界面，而是：

- 启动 in-process app-server client
- 发起 `thread/start` / `turn/start` / `review/start`
- 消费事件并输出成人类可读文本或 JSONL

因此它本质上是一个“无界面的协议客户端”。

### 6.3 TypeScript SDK：封装 CLI 进程

[`sdk/typescript/README.md`](../sdk/typescript/README.md) 说明 TypeScript SDK 的策略是：

- 启动 `codex` CLI
- 通过 stdin/stdout 交换 JSONL 事件

所以它更像是：

- **对 CLI 的编程接口封装**
- 而不是直接对 core 或 app-server 的低层绑定

### 6.4 Python SDK：直接封装 app-server

[`sdk/python/README.md`](../sdk/python/README.md) 则相反，它直接对接：

- `codex app-server`
- JSON-RPC v2 over stdio

这两种 SDK 策略的差异，恰好反映了项目的双入口设计：

- 一条是 **CLI 事件流**
- 一条是 **app-server 协议**

## 7. 核心运行时：真正的 agent 在哪里

真正的 agent 运行时集中在 [`codex-rs/core`](../codex-rs/core)。

### 7.1 `Codex`：会话级运行时

[`codex-rs/core/src/codex.rs`](../codex-rs/core/src/codex.rs) 将 `Codex` 定义成一个高层接口：

> 它本质上是一个“提交 submission / 接收 event”的队列对。

这是非常典型的事件驱动内核设计：

- 上游提交操作
- 内核在后台 session loop 中推进状态
- 下游持续接收事件

### 7.2 `CodexThread`：对外暴露的线程句柄

[`codex-rs/core/src/codex_thread.rs`](../codex-rs/core/src/codex_thread.rs) 提供了线程级 API：

- `submit`
- `steer_input`
- `next_event`
- `shutdown_and_wait`
- `config_snapshot`

从职责上看，它是对 `Codex` 的线程级封装，让上层不用直接管理底层 session loop。

### 7.3 `ThreadManager`：所有活跃线程的调度中心

[`codex-rs/core/src/thread_manager.rs`](../codex-rs/core/src/thread_manager.rs) 负责：

- 创建线程
- 恢复线程
- fork 线程
- 追踪内存中活跃线程
- 关联 models manager / skills manager / plugins manager / mcp manager

这说明 `ThreadManager` 不是简单容器，而是 **会话编排器**。

### 7.4 一个关键观察

`ThreadManager::spawn_thread(...)` 最终会调用 `Codex::spawn(...)`。  
也就是说，线程管理与 agent 内核运行之间是明显分层的：

- `ThreadManager` 负责生命周期与注册
- `Codex` 负责真正的运行循环
- `CodexThread` 负责对外句柄

## 8. `app-server` 如何把协议请求映射到 core

### 8.1 `MessageProcessor` 是协议入口调度器

[`codex-rs/app-server/src/message_processor.rs`](../codex-rs/app-server/src/message_processor.rs) 负责：

- 初始化握手
- JSON-RPC 请求反序列化
- 配置类 API
- 文件系统类 API
- 把其余线程/回合/模型/插件/MCP 请求转交给 `CodexMessageProcessor`

它本质上像一个“协议总路由器”。

### 8.2 `CodexMessageProcessor` 才是 app-server 到 core 的桥

[`codex-rs/app-server/src/codex_message_processor.rs`](../codex-rs/app-server/src/codex_message_processor.rs) 会持有：

- `ThreadManager`
- `AuthManager`
- 配置与云要求加载器
- outgoing sender

它把 `thread/start`、`turn/start`、`review/start`、`skills/list`、`plugin/*`、`mcp/*` 等请求翻译成对 core 能力的调用。

因此可以把 app-server 层进一步拆成：

- **MessageProcessor**：协议解包与路由
- **CodexMessageProcessor**：领域逻辑桥接

## 9. 配置系统：这不是简单的 `config.toml`

[`codex-rs/core/src/config/mod.rs`](../codex-rs/core/src/config/mod.rs) 和 [`codex-rs/core/src/config_loader/README.md`](../codex-rs/core/src/config_loader/README.md) 说明，这个项目的配置是分层加载的。

至少可以确认这些维度：

- 用户配置
- 项目配置
- CLI session overrides
- system managed config
- macOS MDM managed preferences
- cloud requirements / 托管约束

配置层不仅决定模型、UI 和开关，还会进一步编译成：

- approval policy
- sandbox policy
- filesystem/network policy
- feature flags
- auth 限制
- SQLite / rollout / notifications / MCP / plugins 等运行参数

所以从架构角度看，`Config` 更像 **运行时策略对象**，不是简单的“配置文件映射”。

## 10. 工具执行、权限与沙箱

这是第二个很关键的主轴。

### 10.1 工具系统在 core 中

[`codex-rs/core/src/lib.rs`](../codex-rs/core/src/lib.rs) 暴露了大量与工具相关的模块：

- `tools`
- `shell`
- `exec`
- `sandboxing`
- `mcp`
- `function_tool`
- `user_shell_command`

说明工具调用不是附加功能，而是 core 设计中心。

### 10.2 沙箱是平台分治实现

[`codex-rs/sandboxing/src/lib.rs`](../codex-rs/sandboxing/src/lib.rs) 表明项目按平台拆分：

- macOS: `seatbelt`
- Linux: `bwrap` / `landlock`
- Windows: 独立的 [`codex-rs/windows-sandbox-rs`](../codex-rs/windows-sandbox-rs)

这说明沙箱抽象是统一的，但落地实现是平台专用的。

### 10.3 `exec-server` 是执行环境抽象

[`codex-rs/exec-server/src/lib.rs`](../codex-rs/exec-server/src/lib.rs) 同时暴露：

- process
- file_system
- remote_process
- remote_file_system
- `EnvironmentManager`

这意味着执行层并不被写死为“本机 shell”，而是已经抽象成可切换环境，具备向远程执行环境扩展的能力。

### 10.4 `apply-patch` 是独立工具

[`codex-rs/apply-patch`](../codex-rs/apply-patch) 被单独拆出，说明“文件补丁应用”被视为基础工具能力，而不是仅在某个前端里临时实现。

## 11. 持久化：JSONL rollout + SQLite 双轨

### 11.1 JSONL rollout 是事实来源

[`codex-rs/rollout/src/recorder.rs`](../codex-rs/rollout/src/recorder.rs) 说明会话会被持续写成 JSONL rollout。

这里记录的是：

- 会话元数据
- turn/item/event
- fork/resume 轨迹
- 适合重放、恢复、审计与问题排查

也就是说，**rollout 更像事件日志**。

### 11.2 SQLite state DB 是查询与索引层

[`codex-rs/state/src/lib.rs`](../codex-rs/state/src/lib.rs) 说明 state crate 的目标很明确：

> 从 rollout 中提取元数据，并镜像到本地 SQLite。

所以它不是替代 rollout，而是做这些事情：

- 线程元数据索引
- 日志存储
- backfill
- memories / jobs / spawn edges

因此项目的持久化策略可以概括成：

- **rollout(JSONL)**：完整事件历史
- **state(SQLite)**：结构化索引、查询和衍生状态

这是一个比较成熟的事件源 + 查询投影思路。

## 12. 扩展能力：Skills、MCP、Plugins、Apps

这一层是 Codex 可扩展性的关键。

### 12.1 Skills

[`codex-rs/core-skills/src/lib.rs`](../codex-rs/core-skills/src/lib.rs) 与 core 中的 `skills` / `skills_watcher` 表明：

- skills 有独立加载、渲染、注入和缓存逻辑
- 能被文件监听器热更新
- 与 `AGENTS.md`、显式提及、隐式调用机制结合

### 12.2 MCP

MCP 在项目里不是一个薄插件，而是完整一层：

- `mcp-server`：把 Codex 作为 MCP server 暴露
- core 里的 `mcp` / `mcp_connection_manager`
- app-server 里的 `mcpServerStatus/*`、OAuth 登录、tool approvals

这说明 Codex 同时支持：

- **作为 MCP 客户端接第三方工具**
- **作为 MCP 服务端被别人接入**

### 12.3 Plugins 与 Apps/Connectors

插件相关逻辑分布在：

- [`codex-rs/plugin`](../codex-rs/plugin)
- core 的 `plugins`
- app-server 的 `plugin/*` API

Apps/Connectors 则分布在：

- [`codex-rs/connectors`](../codex-rs/connectors)
- app-server 的 `app/list`

这两者的区别可以这样理解：

- **Plugin**：本地安装、带技能/MCP/app 能力包的扩展单元
- **App/Connector**：偏 ChatGPT 连接器生态，面向外部服务接入

## 13. 模型与后端接入

模型接入也分层得比较清楚。

### 13.1 `codex-api`

[`codex-rs/codex-api/src/lib.rs`](../codex-rs/codex-api/src/lib.rs) 提供了：

- Responses API
- realtime websocket
- models
- compaction / memories 相关 endpoint

可以把它理解为“面向模型能力的统一客户端层”。

### 13.2 `backend-client`

[`codex-rs/backend-client/src/lib.rs`](../codex-rs/backend-client/src/lib.rs) 主要面向一方 Codex backend / cloud tasks，属于更上层的业务后端接入。

### 13.3 多模型与本地提供方

从 `core` 依赖和模块命名可以看到，项目同时支持：

- OpenAI
- Ollama
- LM Studio
- 其他 provider 配置

说明模型层的目标不是绑定单一后端，而是统一 provider 抽象。

## 14. 协议与 schema：为什么这个系统适合做 IDE 集成

[`codex-rs/app-server-protocol/src/lib.rs`](../codex-rs/app-server-protocol/src/lib.rs) 与 `app-server generate-ts/json-schema` 相关命令说明：

- 协议对象是可导出的
- 可以生成 TypeScript bindings
- 可以生成 JSON Schema

这意味着项目不是只把协议当内部细节，而是把它当正式边界。

这对 IDE/编辑器集成非常重要，因为它让客户端可以：

- 生成类型安全的请求/响应代码
- 跟随版本演化更新 schema
- 用通知流驱动 UI，而不是解析脆弱文本输出

## 15. 构建与发布方式

从仓库根目录和 workspace 可以看出这是一个多构建系统项目：

- Rust workspace: [`codex-rs/Cargo.toml`](../codex-rs/Cargo.toml)
- npm/pnpm workspace: [`package.json`](../package.json), [`pnpm-workspace.yaml`](../pnpm-workspace.yaml)
- Bazel: [`BUILD.bazel`](../BUILD.bazel), [`MODULE.bazel`](../MODULE.bazel)
- Nix: [`flake.nix`](../flake.nix)

我的理解是：

- **Cargo** 是开发主线
- **pnpm** 负责 JS 包与 SDK 分发
- **Bazel** 更偏 CI / 构建统一化 / 大仓管理
- **Nix** 提供可复现实验环境

## 16. 我对这个项目架构的结论

如果只用一句话概括：

> **Codex 是一个以 Rust core 为中心、以 app-server 协议为收敛层、以多前端/多 SDK 入口暴露能力的本地 agent 平台。**

再展开一点，有五个关键判断：

1. **`app-server` 是系统中枢，不是附带能力。**
2. **TUI/exec/SDK 不是不同内核，只是不同客户端。**
3. **`core` 负责真实 agent 运行时，尤其是线程、turn、工具、模型与扩展。**
4. **持久化采用 rollout(JSONL) + SQLite projection 双轨设计。**
5. **可扩展性不是事后补丁，而是从 skills/MCP/plugins/apps 一开始就进入主架构。**

## 17. 推荐阅读顺序

如果你准备继续深入代码，我建议按这个顺序读：

1. [`README.md`](../README.md)
2. [`codex-rs/cli/src/main.rs`](../codex-rs/cli/src/main.rs)
3. [`codex-rs/tui/src/lib.rs`](../codex-rs/tui/src/lib.rs)
4. [`codex-rs/app-server/README.md`](../codex-rs/app-server/README.md)
5. [`codex-rs/app-server/src/lib.rs`](../codex-rs/app-server/src/lib.rs)
6. [`codex-rs/app-server/src/message_processor.rs`](../codex-rs/app-server/src/message_processor.rs)
7. [`codex-rs/core/src/lib.rs`](../codex-rs/core/src/lib.rs)
8. [`codex-rs/core/src/thread_manager.rs`](../codex-rs/core/src/thread_manager.rs)
9. [`codex-rs/core/src/codex_thread.rs`](../codex-rs/core/src/codex_thread.rs)
10. [`codex-rs/core/src/codex.rs`](../codex-rs/core/src/codex.rs)
11. [`codex-rs/rollout/src/recorder.rs`](../codex-rs/rollout/src/recorder.rs)
12. [`codex-rs/state/src/lib.rs`](../codex-rs/state/src/lib.rs)

如果你关注特定主题，再配合这些文档看：

- 配置：[docs/config.md](./config.md)
- 认证：[docs/authentication.md](./authentication.md)
- 项目级指令：[docs/agents_md.md](./agents_md.md)

