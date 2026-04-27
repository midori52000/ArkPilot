# OpenHarmony Codex Agent Workspace

这个工作区用于把 OpenAI Codex 的 Rust 后端能力接入到鸿蒙窗口应用中。它不是单一仓库，而是由两个项目组成：

- `codex-main`：上游 Codex CLI 源码，核心实现位于 `codex-rs`
- `Agent`：本地鸿蒙窗口应用工程，提供 ArkTS 前端和 N-API / Native 集成

本文档描述的是当前工作区的真实状态，而不是上游 `codex-main` 原仓库的默认状态。

## 当前状态

截至 `2026-04-27`，当前工作区已经完成这些关键工作：

- 已将 `codex-rs app-server` 以嵌入式方式接入鸿蒙应用，而不是依赖外部手动启动的后端进程
- 已增加 `codex-rs/ohos-host` Rust crate，用于在应用进程内启动 `codex-app-server`
- 已通过 N-API 把 Rust host 暴露给 ArkTS，并在 `EntryAbility.onCreate()` 中自动启动
- 前端已适配真实 app-server 协议，包括线程、回合、流式消息、diff、计划和审批请求
- `hvigorw assembleApp` 已构建成功
- 已生成未签名 `.app` 和 `.hap` 产物，并确认 `.hap` 内包含 `libcodexhost.so`

当前仍然存在的边界和风险：

- 产物还是未签名包，直接装真机前需要补签名配置
- 代码和打包已经打通，但还没有做完整真机运行验证
- 鸿蒙设备侧对文件、进程、网络和工作目录的限制，仍可能影响完整 agent 能力

## 项目目标

目标不是重写一套“类似 Codex”的前后端，而是尽量复用上游 Codex 的核心运行时能力，让鸿蒙应用成为一个真实的 Codex 图形客户端。

当前方案的定位是：

- 前端：ArkTS 窗口应用
- 中间桥：N-API + C++ shared library
- 后端：内嵌 Rust `codex-rs app-server`
- 通信：应用内 Rust host 启动 WebSocket server，ArkTS 通过 JSON-RPC 风格协议与之通信

## 工作区结构

```text
OpenHarmony/
|-- Agent/                     # 鸿蒙应用工程
|-- codex-main/                # 上游 Codex 源码
|-- AI_CONTEXT_zh.md           # 便于交接给其他 AI 的上下文文件
`-- README.md                  # 当前文档
```

### `Agent`

`Agent` 是鸿蒙前端工程，当前职责包括：

- 提供 ArkTS 界面
- 通过 N-API 调用内嵌 Rust host
- 作为 WebSocket JSON-RPC 客户端连接本机 `ws://127.0.0.1:7456`
- 展示消息流、计划、diff 和审批请求
- 管理会话状态和前端快照

### `codex-main`

`codex-main` 是上游源码镜像。对这个工作区最重要的部分不是 npm 包装层，而是 `codex-rs`：

- `codex-cli`：Node/npm 启动壳
- `codex-rs`：Rust 主实现
- `codex-rs/app-server`：富客户端协议入口
- `codex-rs/core`：线程、回合、工具执行、审批、模型调用等核心逻辑
- `codex-rs/state`：状态和持久化
- `codex-rs/rollout`：事件落盘和会话回放
- `codex-rs/ohos-host`：本工作区新增的鸿蒙嵌入式 host crate

## 当前架构

### 总体结构

```text
ArkTS UI
  |
  | N-API
  v
libcodexhost.so
  |
  | FFI
  v
codex-ohos-host (Rust staticlib)
  |
  | Tokio runtime
  v
codex-rs app-server
  |
  | WebSocket JSON-RPC
  v
CodexBackend.ets
```

### 应用内自启动链路

当前已经不是“前端连接外部后端”的模式，而是应用启动时自动拉起内嵌后端。启动链路如下：

1. `EntryAbility.onCreate()` 调用 ArkTS 封装层启动内嵌 host
2. ArkTS 调用 `libcodexhost.so`
3. `libcodexhost.so` 通过 FFI 调到 Rust `codex-ohos-host`
4. Rust host 创建 Tokio runtime，并启动上游 `codex-rs app-server`
5. Rust host 在 `ws://127.0.0.1:7456` 监听
6. ArkTS 前端自动连接这个本地 WebSocket 地址

### 请求处理链路

前端发送一条消息时，逻辑路径大致如下：

1. ArkTS UI 收集用户输入和工作目录信息
2. `CodexBackend.ets` 发出 `thread/start` 或 `turn/start`
3. `codex-rs app-server` 把请求转进上游 `core`
4. `core` 调度线程、模型、工具、审批和 diff 生成
5. app-server 将 `item/started`、`item/agentMessage/delta`、`turn/diff/updated`、`turn/completed` 等事件流回前端
6. ArkTS 更新消息列表、右栏 diff、审批卡片和状态摘要

## 已完成的核心改造

### 1. Rust 嵌入式 host

已新增 `codex-main/codex-rs/ohos-host` crate，职责是：

- 暴露可供 N-API 调用的 C ABI 接口
- 负责设置 `CODEX_HOME` 和 `HOME`
- 在后台线程中启动 Tokio runtime
- 调用上游 `run_main_with_transport(...)`
- 等待 WebSocket 端口真正可连通后，再向前端返回“已就绪”

这意味着 ArkTS 不需要自己管理 Rust 二进制生命周期，也不需要单独拉起一个外部进程。

### 2. 鸿蒙 N-API 桥接

已在 `Agent/entry/src/main/cpp` 下增加 native 模块：

- `napi_init.cpp`：把 Rust host 暴露给 ArkTS
- `CMakeLists.txt`：负责构建 `libcodexhost.so`
- `build_codex_ohos_host.cmd`：在 hvigor 构建过程中触发 Rust host 交叉编译

这层桥接对 ArkTS 提供的核心能力包括：

- `startHost(codexHome, serverUrl)`
- `getStatus()`
- `isHostRunning()`
- `getLastMessage()`
- `getServerUrl()`

### 3. ArkTS 后端接入

前端已经不再是 mock backend，而是真实协议客户端：

- `initialize / initialized`
- `thread/start`
- `turn/start`
- `item/started`
- `item/completed`
- `item/agentMessage/delta`
- `turn/diff/updated`
- `turn/plan/updated`
- `turn/completed`
- 命令、文件、权限审批请求

### 4. OHOS 运行时修补

已对上游 `apply_patch` 运行路径做了 OHOS 适配，使其在鸿蒙目标下走进程内实现，而不是依赖外部 `codex` 可执行文件再调用自身。这一步是为了让内嵌场景能跑通工具链。

## 关键文件

### 前端

- `Agent/entry/src/main/ets/pages/Index.ets`
  - 主界面，负责消息输入、连接、审批、diff 和状态展示

- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
  - ArkTS 版 app-server 协议客户端

- `Agent/entry/src/main/ets/backend/CodexHostNative.ets`
  - ArkTS 到 `libcodexhost.so` 的封装

- `Agent/entry/src/main/ets/entryability/EntryAbility.ets`
  - 应用入口，在 `onCreate()` 中启动内嵌 host

- `Agent/entry/src/main/module.json5`
  - 模块配置，包含网络权限等声明

### Native / Build

- `Agent/entry/src/main/cpp/napi_init.cpp`
  - N-API 模块入口

- `Agent/entry/src/main/cpp/CMakeLists.txt`
  - native build 配置，负责链接 Rust staticlib 和系统库

- `Agent/entry/src/main/cpp/build_codex_ohos_host.cmd`
  - Rust host 的 Windows 主机侧 OHOS 交叉编译脚本

### Rust

- `codex-main/codex-rs/ohos-host/src/lib.rs`
  - 鸿蒙嵌入式 host 的 Rust 主逻辑

- `codex-main/codex-rs/core/src/tools/runtimes/apply_patch.rs`
  - OHOS 下的 `apply_patch` 运行时适配

- `codex-main/codex-rs/app-server/README.md`
  - 上游 app-server 协议说明

## 环境要求

建议构建环境：

- Windows 主机
- DevEco Studio
- OpenHarmony / HarmonyOS SDK 和 Native 工具链
- Rust toolchain `1.93.0`
- 已安装 Rust target `aarch64-unknown-linux-ohos`

`codex-main/codex-rs/rust-toolchain.toml` 当前固定为：

```toml
[toolchain]
channel = "1.93.0"
components = ["clippy", "rustfmt", "rust-src"]
```

如果要安装目标，请优先给这个固定 toolchain 安装：

```powershell
rustup target add --toolchain 1.93.0-x86_64-pc-windows-msvc aarch64-unknown-linux-ohos
```

### 硬编码路径说明

当前工程里有几处默认写死到了 DevEco 默认安装目录：

- `codex-main/codex-rs/.cargo/config.toml`
- `codex-main/codex-rs/toolchains/ohos-aarch64-clang.cmd`
- `Agent/entry/src/main/cpp/build_codex_ohos_host.cmd`
- `Agent/entry/src/main/cpp/CMakeLists.txt`

默认路径是：

```text
C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
```

如果你的 SDK 不在这个路径下，必须先改这些文件，否则 Rust host 和 native 模块都可能编不过。

## 构建方式

### 方式 A：直接构建鸿蒙应用

这是当前推荐方式。因为 `Agent` 的 native 构建流程已经会自动触发 Rust host 编译。

在 `Agent` 目录执行：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp
```

这一步会完成：

- ArkTS 编译
- N-API 模块构建
- Rust `codex-ohos-host` 交叉编译
- `libcodexhost.so` 打包进 `.hap`
- `.app` 和 `.hap` 产物生成

### 方式 B：单独构建 Rust host

如果你只想验证 Rust host，可以看 `Agent/entry/src/main/cpp/build_codex_ohos_host.cmd`，或者在 `codex-main/codex-rs` 下直接构建：

```powershell
cargo build --package codex-ohos-host --target aarch64-unknown-linux-ohos --release
```

输出目录默认位于：

```text
Agent/.cargo-target/codex-ohos-host/aarch64-unknown-linux-ohos/release/libcodex_ohos_host.a
```

### 方式 C：单独构建上游 app-server 可执行文件

这不是应用内自启动的必需步骤，但对调试上游后端有帮助：

```powershell
cargo build -p codex-app-server --target aarch64-unknown-linux-ohos
```

输出位于：

```text
codex-main/codex-rs/target/aarch64-unknown-linux-ohos/debug/codex-app-server
```

## 产物位置

当前已验证存在的关键产物：

```text
Agent/build/outputs/default/Agent-default-unsigned.app
Agent/entry/build/default/outputs/default/entry-default-unsigned.hap
Agent/.cargo-target/codex-ohos-host/aarch64-unknown-linux-ohos/release/libcodex_ohos_host.a
```

并且已经确认：

- `entry-default-unsigned.hap` 内包含 `libs/arm64-v8a/libcodexhost.so`
- 同一个 `.hap` 内也包含 `ets/modules.abc`

## 应用如何使用

### 默认使用方式

应用现在的默认行为是：

1. 启动应用
2. `EntryAbility` 自动启动内嵌 Rust host
3. Rust host 自动监听 `ws://127.0.0.1:7456`
4. 前端自动连接这个地址
5. 用户在界面中输入任务并发起回合

也就是说，当前版本默认不需要你再单独手工启动一个外部 `codex-app-server`。

### `CODEX_HOME` 位置

内嵌 host 会把 `CODEX_HOME` 设置到应用文件目录下：

```text
<app filesDir>/codex-home
```

这意味着：

- 会话状态
- 缓存
- 认证相关文件
- app-server 运行时数据

都会落在应用沙箱里，而不是桌面环境的用户目录。

### 首次运行建议

如果你准备上真机或模拟器，建议按这个顺序验证：

1. 先补签名配置并生成可安装包
2. 安装并启动应用
3. 观察应用日志，确认内嵌 host 成功启动
4. 在界面中设置一个设备可访问的工作目录
5. 发送一条简单请求，例如让它读取目录或解释某个文件
6. 验证消息流、diff 和审批卡片是否正常工作

### 典型使用场景

当前前端已经支持这些交互：

- 发送用户消息
- 维护线程和回合
- 展示助手流式输出
- 展示统一 diff
- 展示计划更新
- 接收命令、文件、权限审批请求
- 在前端做审批反馈

## 调试方式

### 查看构建日志

- hvigor 日志：

```text
Agent/.hvigor/outputs/build-logs/build.log
```

- Rust host 构建日志：

```text
Agent/build_codex_ohos_host_full.log
```

### 查看应用启动日志

应用入口和内嵌 host 的日志标签使用 `CodexHost`。如果设备端运行失败，优先看这个标签的日志。

### 检查 native 产物

如果怀疑打包不完整，重点检查：

- `Agent/entry/build/default/intermediates/cmake/default/obj/arm64-v8a/libcodexhost.so`
- `Agent/entry/build/default/outputs/default/entry-default-unsigned.hap`

## 已知限制

当前版本仍然有这些限制：

- `Agent-default-unsigned.app` 和 `entry-default-unsigned.hap` 仍是未签名产物
- `hvigor` 构建时仍可能出现 `Dependency libcodexhost.so not found` 警告，但当前不影响最终打包成功
- 还没有完成完整真机 smoke test
- 上游 Codex 的完整 agent 能力依赖文件访问、命令执行、网络和权限审批，设备侧限制越强，可用能力就越弱
- DevEco SDK 路径当前是硬编码的，可移植性一般

## 当前结论

当前项目已经从“前端 mock 原型”推进到了“应用内嵌真实 Codex Rust 后端并自动启动”的阶段。它不再只是连接外部服务的演示 UI，而是一个具备真实 app-server 交互能力的鸿蒙客户端原型。

更准确地说，当前已经完成的是：

- 代码级接入
- 内嵌后端自启动
- native 打包
- 构建验证

还没有完全闭环的是：

- 真机安装与运行验证
- 签名与发布流程
- 设备侧权限和工作目录能力验证

## 建议的下一步

如果你要继续把这个项目做实，建议按下面顺序推进：

1. 补齐 `Agent/build-profile.json5` 的签名配置
2. 在真机或模拟器上做最小 smoke test
3. 验证应用沙箱内的 `CODEX_HOME`、认证状态和工作目录访问
4. 验证命令执行、文件修改和审批链路在设备侧是否都可用
5. 处理剩余构建警告，尤其是 `libcodexhost.so` 依赖警告和符号包输出警告

## 相关文档

- `AI_CONTEXT_zh.md`
  - 方便把当前状态交接给其他 AI

- `codex-main/docs/architecture_zh.md`
  - 上游 Codex 架构中文分析

- `codex-main/codex-rs/app-server/README.md`
  - 上游 app-server 协议说明

- `codex-main/README.md`
  - 上游项目总览
