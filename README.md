# OpenHarmony Codex Agent Workspace

这个工作区用于把上游 Codex 的 Rust 后端能力接入到鸿蒙窗口应用中。它不是单一仓库，而是由两个项目组成：

- `Agent`：鸿蒙应用工程，提供 ArkTS 前端、N-API 桥接和应用内自启动逻辑
- `codex-main`：上游 Codex CLI 源码，核心实现位于 `codex-rs`

当前文档描述的是这个工作区的真实状态，而不是上游 `codex-main` 原仓库的默认状态。

## 当前状态

截至 `2026-04-28`，当前工作区已经完成这些关键工作：

- 已将 `codex-rs app-server` 以应用内嵌方式接入鸿蒙应用
- 已新增 `codex-rs/ohos-host` Rust crate，用于在应用进程内启动 `codex-app-server`
- 已通过 N-API 把 Rust host 暴露给 ArkTS，并在 `EntryAbility.onCreate()` 中自动启动
- 前端已适配真实 app-server 协议，包括线程、回合、流式消息、diff、计划和审批请求
- 已支持双 ABI 构建：`arm64-v8a` 和 `x86_64`
- 已支持手动模型提供方配置：`base_url + api_key + model`
- `assembleHap` 已构建成功，并可在模拟器中启动应用

当前仍然存在的边界和风险：

- provider 配置变更后，内嵌后端需要重启应用才会重新加载
- 当前仍需进一步验证第三方 OpenAI-compatible 服务的实际兼容性，例如 OpenRouter 对 `responses` API 的支持
- 代码和打包链路已打通，但还没有做完整真机验证
- 鸿蒙设备侧对文件、进程、网络和工作目录的限制，仍可能影响完整 agent 能力

## 工作区结构

```text
OpenHarmony/
|-- Agent/               # 鸿蒙应用工程
|-- codex-main/          # 上游 Codex 源码
|-- AI_CONTEXT_zh.md     # 供其他 AI 接手的上下文文档
`-- README.md            # 当前工作区说明
```

### Agent

`Agent` 是鸿蒙前端工程，当前职责包括：

- 提供 ArkTS 图形界面
- 通过 N-API 调用内嵌 Rust host
- 作为 WebSocket JSON-RPC 客户端连接本机 `ws://127.0.0.1:7456`
- 展示消息流、计划、diff 和审批请求
- 管理会话状态、模型配置和工作目录

### codex-main

`codex-main` 是上游源码镜像。对这个工作区最重要的不是 npm 包装层，而是 `codex-rs`：

- `codex-cli`：Node/npm 启动壳
- `codex-rs`：Rust 主实现
- `codex-rs/app-server`：协议入口
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

当前已经不是“前端连接外部后端”的模式，而是应用启动时自动拉起内嵌后端：

1. `EntryAbility.onCreate()` 调用 ArkTS 封装层启动内嵌 host
2. ArkTS 调用 `libcodexhost.so`
3. `libcodexhost.so` 通过 FFI 调到 Rust `codex-ohos-host`
4. Rust host 创建 Tokio runtime，并启动上游 `codex-rs app-server`
5. Rust host 在 `ws://127.0.0.1:7456` 监听
6. ArkTS 前端自动连接这个本地 WebSocket 地址

### 请求处理链路

前端发送一条消息时，路径大致如下：

1. ArkTS UI 收集用户输入、工作目录和模型信息
2. `CodexBackend.ets` 发出 `thread/start` 或 `turn/start`
3. `codex-rs app-server` 将请求转入上游 `core`
4. `core` 调度线程、模型、工具、审批和 diff 生成
5. app-server 通过 `item/started`、`item/agentMessage/delta`、`turn/diff/updated`、`turn/completed` 等事件把结果流回前端
6. ArkTS 更新消息列表、右栏 diff、审批卡片和状态摘要

## 已完成的核心改造

### 1. Rust 嵌入式 host

已新增 `codex-main/codex-rs/ohos-host` crate，职责是：

- 暴露可供 N-API 调用的 C ABI 接口
- 负责设置 `CODEX_HOME` 和 `HOME`
- 在后台线程中启动 Tokio runtime
- 调用上游 `run_main_with_transport(...)`
- 等待 WebSocket 端口真正可连通后，再向前端返回“已就绪”
- 持久化 provider 配置并生成 `CODEX_HOME/config.toml`

### 2. 鸿蒙 N-API 桥接

`Agent/entry/src/main/cpp` 下的关键文件：

- `napi_init.cpp`：把 Rust host 暴露给 ArkTS
- `CMakeLists.txt`：负责构建 `libcodexhost.so`
- `build_codex_ohos_host.cmd`：在 hvigor 构建流程中触发 Rust host 交叉编译

当前桥接给 ArkTS 的核心能力包括：

- `startHost(codexHome, serverUrl)`
- `getStatus()`
- `isHostRunning()`
- `getLastMessage()`
- `getServerUrl()`
- `getProviderConfig()`
- `saveProviderConfig()`

### 3. ArkTS 后端接入

前端不再是 mock backend，而是真实协议客户端，已接入：

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

### 4. 手动 provider 模式

当前模型配置已改成手动模式，不再依赖 GPT 账号登录界面：

- 前端填写 `base_url`
- 前端填写 `api_key`
- 前端填写默认 `model`
- 保存后写入 `CODEX_HOME/config.toml`

当前默认生成的 provider 是：

- provider id：`harmony-openai-compatible`
- `wire_api = "responses"`
- `requires_openai_auth = false`
- `supports_websockets = false`

注意：

- 点击 `Save provider` 只会保存配置
- 内嵌 app-server 需要重启应用后才会加载新的 provider 配置

## 关键文件

### 前端

- `Agent/entry/src/main/ets/pages/Index.ets`
  - 主界面，负责连接、消息输入、模型配置、审批、diff 和状态展示
- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
  - ArkTS 版 app-server 协议客户端
- `Agent/entry/src/main/ets/backend/CodexHostNative.ets`
  - ArkTS 到 `libcodexhost.so` 的封装
- `Agent/entry/src/main/ets/entryability/EntryAbility.ets`
  - 应用入口，在 `onCreate()` 中启动内嵌 host
- `Agent/entry/src/main/module.json5`
  - 模块配置，包括网络权限等声明

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
- `codex-main/codex-rs/app-server/src/transport/websocket.rs`
  - 已为鸿蒙客户端补过 `Origin` 头兼容

## 构建环境

建议环境：

- Windows 主机
- DevEco Studio
- OpenHarmony / HarmonyOS SDK 和 Native 工具链
- Rust toolchain `1.93.0`
- Rust target：
  - `aarch64-unknown-linux-ohos`
  - `x86_64-unknown-linux-ohos`

上游 `rust-toolchain.toml` 当前固定为：

```toml
[toolchain]
channel = "1.93.0"
components = ["clippy", "rustfmt", "rust-src"]
```

安装目标：

```powershell
rustup target add --toolchain 1.93.0-x86_64-pc-windows-msvc aarch64-unknown-linux-ohos
rustup target add --toolchain 1.93.0-x86_64-pc-windows-msvc x86_64-unknown-linux-ohos
```

### 可能需要调整的硬编码路径

如果你的 DevEco SDK 不在默认路径下，需要检查这些文件：

- `codex-main/codex-rs/.cargo/config.toml`
- `codex-main/codex-rs/toolchains/ohos-aarch64-clang.cmd`
- `Agent/entry/src/main/cpp/build_codex_ohos_host.cmd`
- `Agent/entry/src/main/cpp/CMakeLists.txt`

默认 SDK 路径：

```text
C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
```

## 构建方式

### 方式 A：直接构建鸿蒙应用

推荐方式。在 `Agent` 目录执行：

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

### 方式 B：单独构建 HAP

当前更适合调试：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry@default -p product=default -p requiredDeviceType=2in1 assembleHap
```

### 方式 C：单独构建 Rust host

```powershell
cargo build --package codex-ohos-host --target aarch64-unknown-linux-ohos --release
```

或者：

```powershell
cargo build --package codex-ohos-host --target x86_64-unknown-linux-ohos --release
```

### 方式 D：单独构建上游 app-server 可执行文件

```powershell
cargo build -p codex-app-server --target aarch64-unknown-linux-ohos
```

## 当前产物位置

常见产物：

- `Agent/build/outputs/default/Agent-default-signed.app`
- `Agent/entry/build/default/outputs/default/entry-default-signed.hap`
- `Agent/.cargo-target/codex-ohos-host/.../libcodex_ohos_host.a`

当前已确认：

- `.hap` 内包含 `libs/arm64-v8a/libcodexhost.so`
- `.hap` 内也包含 `libs/x86_64/libcodexhost.so`

## 使用方式

### 默认运行流程

1. 启动应用
2. `EntryAbility` 自动启动内嵌 Rust host
3. Rust host 监听 `ws://127.0.0.1:7456`
4. 前端自动连接这个地址
5. 用户在界面中填写 provider 配置、工作目录并发起请求

### Provider 配置

左侧 `Provider` 面板支持：

- `base_url`
- `api_key`
- `model`

典型示例：

- OpenAI：`https://api.openai.com/v1`
- OpenRouter：`https://openrouter.ai/api/v1`

保存后需要：

1. 点击 `Save provider`
2. 完全关闭应用
3. 重新打开应用

否则内嵌后端仍会使用旧配置。

### CODEX_HOME 位置

内嵌 host 会把 `CODEX_HOME` 设置到应用文件目录下：

```text
<app filesDir>/codex-home
```

其中会保存：

- 会话状态
- 缓存
- provider 配置
- `config.toml`
- 认证和运行时数据

## 调试方式

### 查看构建日志

- `Agent/.hvigor/outputs/build-logs/build.log`
- `Agent/build_codex_ohos_host_full.log`

### 查看应用启动日志

重点关注日志标签：

- `CodexHost`

如果内嵌 host 启动失败，优先看这个标签。

### 常见问题

#### 1. WebSocket 连不上

先确认：

- 应用是否真正启动了内嵌 host
- `ws://127.0.0.1:7456` 是否显示为已连接
- `CodexHost` 日志里是否出现 `ready on ws://127.0.0.1:7456`

#### 2. 保存 provider 后输入框被清空

这是之前存在过的桥接字段名问题，当前版本已修复。若再次出现，优先检查：

- `CodexHostNative.ets`
- `napi_init.cpp`
- `codex-home/harmony-provider.json`

#### 3. 仍然请求 `api.openai.com`

说明新 provider 配置尚未被内嵌后端重新加载。处理方式：

1. 点击 `Save provider`
2. 完全退出应用
3. 重新打开应用

#### 4. OpenRouter 返回鉴权或协议错误

当前 provider 使用的是 `responses` API。若第三方服务不兼容，需要进一步调整：

- `wire_api`
- 请求头
- OpenAI-compatible 协议细节

## 已知限制

- provider 配置当前不是热更新，修改后必须重启应用
- 第三方 OpenAI-compatible 服务的兼容性还未完全验证
- 真机侧文件访问、命令执行、权限审批能力还没有做完整闭环验证
- DevEco SDK 路径当前仍有硬编码，移植性一般
- 仍有少量 ArkTS warning，但不阻塞当前构建

## 当前结论

当前项目已经从“前端 mock 原型”推进到了“应用内嵌真实 Codex Rust 后端并自动启动”的阶段。它不再只是连接外部服务的演示 UI，而是一个具备真实 app-server 交互能力的鸿蒙客户端原型。

更准确地说，当前已经完成的是：

- 代码级接入
- 内嵌后端自启动
- native 打包
- 构建验证
- 手动 provider 模式接入

还没有完全闭环的是：

- 真机安装与运行验证
- 第三方 provider 完整兼容性验证
- 设备侧权限、工作目录和工具链能力验证

## 下一步建议

建议按这个顺序继续推进：

1. 在模拟器和真机上验证自定义 `base_url` 是否真正生效
2. 验证 OpenRouter 或其他第三方 provider 对 `responses` API 的兼容性
3. 如有必要，为第三方服务调整 `wire_api` 或 provider 生成逻辑
4. 清理 ArkTS 中残留的旧登录路径和无用状态
5. 做一轮真机 smoke test，覆盖工作目录、命令执行和审批流程

## 相关文档

- `AI_CONTEXT_zh.md`
  - 当前工作区交接上下文
- `codex-main/docs/architecture_zh.md`
  - 上游 Codex 架构中文分析
- `codex-main/codex-rs/app-server/README.md`
  - 上游 app-server 协议说明
- `codex-main/README.md`
  - 上游项目总览
