# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库概览

这个仓库由三部分组成，改动时通常要先判断自己落在哪一层：

- `Agent/`：HarmonyOS / OpenHarmony 应用，ArkTS UI + NAPI 桥接。
- `codex-main/`：Rust workspace；真正的 agent / app-server / protocol / MCP / skills 逻辑在这里。
- `libcodexhost-builder/`：把 `codex-main/codex-rs/ohos-host` 交叉编译成 `libcodex_ohos_host.so`，并复制到 `Agent/entry/libs/<ABI>/`。

不要把 `Agent/entry/build/`、`Agent/.hvigor/` 下的生成产物当作源码修改；源码以 `Agent/entry/src/**` 为准。

## 常用命令

### HarmonyOS Agent（在 `Agent/` 目录执行）

> 仓库里没有提交 `hvigorw` 包装脚本；命令默认使用 DevEco Studio 自带的 `hvigor` CLI，或者直接在 DevEco Studio 中执行同名任务。

- 安装依赖：`ohpm install`
- 查看可用任务：`hvigor tasks`
- 构建模块 HAP：`hvigor assembleHap`
- 构建应用包：`hvigor assembleApp`
- 运行本地单元测试：`hvigor test`
- 运行设备侧测试：`hvigor onDeviceTest`
- 清理构建缓存：`hvigor clean`

补充说明：

- `Agent/entry/build-profile.json5` 定义了 `default` 和 `ohosTest` 两个 target。
- 已存在示例测试文件：`Agent/entry/src/test/LocalUnit.test.ets`、`Agent/entry/src/ohosTest/ets/test/Ability.test.ets`；它们更像模板样例，不是高覆盖率业务测试。
- 仓库里有 ArkTS linter 规则文件 `Agent/code-linter.json5`，但当前未看到已提交的独立 CLI lint task；若需要 lint，优先使用 DevEco Studio 对应能力，或先通过 `hvigor tasks` 确认本机环境下的可用任务。
- 根 `build-profile.json5` 明确说明本地签名配置未提交；新 clone 默认应能构建未签名 debug HAP，但不能假设 release 签名可直接使用。

### Rust host（分别在 `libcodexhost-builder/` 或 `codex-main/codex-rs/` 执行）

推荐优先走外层脚本，而不是手写交叉编译参数：

- 模拟器构建并安装：`./build.ps1 debug x86_64`
- 真机构建并安装：`./build.ps1 release arm64-v8a`
- 只构建不复制到 Agent：`./build.ps1 debug x86_64 -NoInstall`
- 使用预编译 `.so`：`$env:PREBUILT_RUST_SHARED_LIB = "E:\path\libcodex_ohos_host.so"; ./build.ps1 release x86_64`

常用 Rust 校验命令（在 `codex-main/codex-rs/`）：

- 整个 workspace 测试：`cargo test`
- 只测 Harmony host crate：`cargo test -p codex-ohos-host`
- 运行单个 Rust 测试：`cargo test -p codex-ohos-host <test_name>`
- 检查单个 crate：`cargo check -p codex-ohos-host`
- 格式化：`cargo fmt --all`
- lint：`cargo clippy -p codex-ohos-host --all-targets -- -D warnings`

补充说明：

- `codex-main/codex-rs/rust-toolchain.toml` 固定 Rust `1.93.0`，并启用了 `clippy` / `rustfmt` / `rust-src`。
- `build.ps1` 会自动探测 `DEVECO_SDK_HOME`，并配置 OHOS linker wrapper；如果 SDK 不在脚本列出的默认路径，需要先设置环境变量。
- ABI 对应关系：`x86_64` 用于模拟器，`arm64-v8a` 用于真机。

## 高层架构

### 1. 应用启动与运行链路

核心链路是：

`ArkTS UI -> CodexBackend.ets -> CodexNative.ets -> libentry.so (NAPI) -> dlopen("libcodex_ohos_host.so") -> codex-ohos-host -> codex-app-server / codex-core`

关键点：

- `Agent/entry/src/main/ets/entryability/EntryAbility.ets` 会在应用启动时把 `codexHome` 设为 `${filesDir}/codex-home`，并调用 `startEmbeddedCodexHost()`。
- Rust host 默认监听 `ws://127.0.0.1:7456`；这是真正的 embedded app-server 地址。
- `Agent/entry/src/main/ets/backend/CodexBackend.ets` 里的默认“后端地址”是 `native://entry`；它表示前端优先走原生桥接，不是直接连 websocket。
- 首次启动时还会调用 `PromptsBackendService.autoImportOnFirstLaunch()`，把已有 `AGENTS.md` 导入 Prompt 管理体系。

### 2. Agent 层职责边界

`Agent/entry/src/main/ets/` 是主要业务层：

- `pages/Index.ets`：Chat 工作台、消息、diff、审批、会话入口。
- `pages/SettingsPage.ets` / `pages/ApiManagementPage.ets` / `pages/PromptsPage.ets`：Provider、MCP、Prompts、Skills 等配置界面。
- `backend/CodexBackend.ets`：前端状态中心。它负责线程映射、turn 轮询、审批轮询、账户状态、MCP 配置缓存等。
- `backend/CodexNative.ets`：对 `libentry.so` 的 ArkTS 包装；native 不可用时会返回兜底 JSON / 默认值。

如果是 UI 表现问题，通常只改 `pages/**`；如果是线程、审批、MCP、登录状态之类的行为问题，通常落在 `CodexBackend.ets`；如果是跨语言接口问题，先看 `CodexNative.ets`。

### 3. NAPI 桥接层

`Agent/entry/src/main/cpp/napi_init.cpp` 是 ArkTS 与 Rust host 之间的胶水层：

- 运行时通过 `dlopen("libcodex_ohos_host.so")` + `dlsym(...)` 加载导出符号。
- 暴露的能力不仅有聊天初始化 / thread / turn / approval，还包括 provider、prompts、skills、MCP、account 等整套管理接口。
- `Agent/entry/src/main/cpp/CMakeLists.txt` 只有在 `Agent/entry/libs/${OHOS_ARCH}/libcodex_ohos_host.so` 存在时才会把它加入链接路径。

这意味着：

- ArkTS 代码可能能编过，但如果 `.so` 没被放进 `entry/libs/<ABI>/`，运行期仍然会因为 `libcodex_ohos_host.so` 加载失败而退化。
- 一旦修改 Rust FFI 接口签名，需要同步检查三层：`codex-main/codex-rs/ohos-host` 导出、`napi_init.cpp`、`Agent/entry/src/main/types/libentry` 的类型声明。

### 4. Rust workspace 的角色

`codex-main/codex-rs/` 是一个大型 workspace；HarmonyOS 相关入口只是其中的 `ohos-host` crate：

- `codex-main/codex-rs/ohos-host/Cargo.toml` 把它声明为 `cdylib`，产物名是 `libcodex_ohos_host.so`。
- 这个 crate 依赖 `codex-app-server`、`codex-core`、`codex-protocol` 等共享核心组件，所以 HarmonyOS 端并不是独立重写了一套 agent 逻辑，而是复用了主 Rust 引擎。
- 如果问题涉及 turn 协议、app-server 事件格式、MCP 行为或账户状态，往往不能只在 `ohos-host` 修，需要顺着依赖继续查 workspace 里的共享 crate。

### 5. libcodexhost-builder 的作用

`libcodexhost-builder/build.ps1` 是当前最可靠的原生构建入口：

- 负责解析 DevEco SDK 路径。
- 设置 OHOS clang / cmake / ninja / cargo target 环境。
- 调用 `cargo build --package codex-ohos-host --target <ohos-target>`。
- 在成功后把 `.so` 复制到 `Agent/entry/libs/<ABI>/`。

如果你改了 Rust host 但 Agent 侧没有生效，先检查是不是忘了重新跑这个脚本，或者 `.so` 被安装到了错误 ABI 目录。

## 运行时数据与配置

`codexHome` 位于应用私有目录下的 `codex-home`。从现有实现看，以下数据都围绕它读写：

- `harmony-provider.json`
- `config.toml`
- prompts registry / skills registry / skills repos / backups
- `AGENTS.md`

重要联动：

- Prompt 管理不是只改 UI 状态；启用 Prompt 最终会写回 `AGENTS.md`。
- `PromptsPage.ets` 文案已经明确提示：切换 Prompt 后通常需要新建会话才能生效。
- Provider、MCP、Skills 的配置持久化都走 native host，不是前端自己直接落盘。

## 开发时最容易踩的点

- `Agent/entry/src/main/types/libentry` 里的类型包名叫 `libentry.so`，它描述的是 ArkTS 看到的 NAPI 模块，不是 Rust `.so` 本体。
- 真正的 Rust host 产物名是 `libcodex_ohos_host.so`，二者不要混淆。
- `EntryAbility.ets` 启动的是 embedded host；`CodexBackend.ets` 管理的是前端如何通过 native bridge 使用它。这两个入口看起来都像“连接后端”，但职责不同。
- 目前仓库中的 Hypium 测试仍是模板级样例；修改关键桥接逻辑后，不要把 `hvigor test` 通过视为完整回归。
- 构建相关问题优先看 `Agent/.hvigor/outputs/` 日志，但不要修改这些生成文件本身。


## 当前我们要做的事
1、目前纯设计前端，不改动后端，预留好接口，前端设计完给出一定交互反馈（比如按钮按压的时候会缩放，有一定的粒子效果等），同时如果还没对接后端则给出一个提示没有对接的弹窗（自动消散无需确认），我给出参考文件在design/design.md
2、即使更新gitignore,更新claude.md。

### Settings 前端先行约定

- 当前 `Agent/entry/src/main/ets/pages/SettingsPage.ets` 以 **独立 settings 控制台** 的形式推进，和主聊天页分离。
- 本轮以 **统一 mock / facade** 为准：允许做前端状态切换、草稿编辑、自动消散提示、按压缩放、轻粒子/装饰反馈，但**不要把新的 settings 交互直接接到真实后端写入逻辑**。
- 未对接完成的操作，应给出“暂未接入后端 / 当前仅前端模拟”之类的轻提示，不增加确认成本。
- 如果后续接入真实后端，优先替换 action/facade 层，不要推翻当前 settings 的页面结构与视觉层级。

## 错误经验
（这里写错误和解决方案，遇到错误优先查找，避免重复工作）
