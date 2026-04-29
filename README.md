# OpenHarmony Codex Agent Workspace

这个目录不是单一仓库，而是一个用于把上游 Codex Rust 后端接入鸿蒙窗口应用的工作区。

当前工作区由两个核心部分组成：

- `Agent/`
  - 鸿蒙应用工程
  - 包含 ArkTS 前端、N-API 桥接、CMake/native 构建、应用内自启动逻辑
- `codex-main/`
  - 上游 Codex 源码镜像
  - 真正的核心后端在 `codex-main/codex-rs/`

根目录下这份 `README.md` 说明的是当前工作区的真实状态，不是上游 `codex-main` 原仓库默认状态。

## 当前状态

截至 `2026-04-29`，当前工作区已经完成这些关键工作：

- 已将真实 `codex-rs app-server` 以应用内嵌方式接入鸿蒙应用
- 已新增 `codex-main/codex-rs/ohos-host`，用于在应用进程内启动 Rust host
- 已通过 N-API 把 Rust host 暴露给 ArkTS
- 已支持应用启动时自动拉起内嵌后端
- 已接入真实 app-server 协议，而不是本地 mock backend
- 已支持手动 provider 配置：`base_url + api_key + model`
- 已支持 `x86_64` 模拟器和 `arm64-v8a` 真机双 ABI 构建
- 已修复聊天消息过多时不自动滚动到底部的问题
- `codex-main` 源码已纳入当前仓库版本管理，编译产物仍然忽略

当前仍然需要注意的边界：

- provider 配置修改后，需要重启应用，内嵌后端才会重新加载
- 第三方 OpenAI-compatible 服务是否完全兼容 `responses` API 仍需逐个验证
- 真机完整验证还没做完
- 包体目前偏大，主要原因是双 ABI 下把两个 `libcodexhost.so` 都打进了 HAP

## 目录结构

```text
OpenHarmony/
|-- Agent/
|-- codex-main/
|-- AI_CONTEXT_zh.md
|-- .gitignore
`-- README.md
```

说明：

- `Agent/`
  - 鸿蒙应用工程
- `codex-main/`
  - 上游 Codex 源码
- `AI_CONTEXT_zh.md`
  - 给其他 AI 接手时使用的上下文交接文档

## 架构概览

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

### 启动链路

应用启动后，后端会自动在应用内拉起：

1. `EntryAbility.onCreate()` 调用 ArkTS 封装层
2. ArkTS 调用 `libcodexhost.so`
3. `libcodexhost.so` 通过 FFI 调到 Rust `codex-ohos-host`
4. Rust host 启动 Tokio runtime
5. Rust host 调用上游 `codex-rs app-server`
6. app-server 监听 `ws://127.0.0.1:7456`
7. ArkTS 前端自动连接这个本地 WebSocket

### 请求链路

用户发送消息后，处理路径如下：

1. UI 收集输入、工作目录、模型和推理等级
2. `CodexBackend.ets` 发送 `thread/start` / `turn/start`
3. `codex-rs app-server` 把请求转入 `codex-core`
4. `core` 负责线程、回合、工具、模型、审批、diff
5. app-server 通过流式通知把结果回给前端
6. 前端更新消息列表、右侧 diff、摘要和审批卡片

## 当前已接入的能力

### 后端

当前使用的是真实 `codex-rs` 后端，不是自写的假循环。

已经接入的关键能力包括：

- `initialize / initialized`
- `thread/start`
- `turn/start`
- 流式消息增量
- diff 更新
- plan 更新
- 回合完成通知
- 命令审批
- 文件改动审批
- 权限审批

### 前端

当前前端已经支持：

- 连接本地内嵌 app-server
- 发送对话请求
- 展示消息流
- 展示统一 diff
- 展示审批请求
- 手动配置 provider
- 自动滚动到最新消息

## Provider 模式

当前已经改成手动 provider 模式，不再依赖 GPT 账号登录 UI。

配置项：

- `base_url`
- `api_key`
- `model`

典型示例：

- OpenAI
  - `https://api.openai.com/v1`
- OpenRouter
  - `https://openrouter.ai/api/v1`

当前行为：

1. 在左侧 `Provider` 面板填写 `base_url`、`api_key`、`model`
2. 点击 `Save provider`
3. 完全关闭应用
4. 重新打开应用

注意：

- 只点 `Save provider` 不够
- 因为内嵌 app-server 是启动时读取配置，不是热加载

## 关键文件

### ArkTS

- `Agent/entry/src/main/ets/pages/Index.ets`
  - 主界面
  - 包含连接、消息列表、输入区、provider 配置、diff 展示
- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
  - app-server 协议客户端
- `Agent/entry/src/main/ets/backend/CodexHostNative.ets`
  - ArkTS 到 native host 的桥接
- `Agent/entry/src/main/ets/entryability/EntryAbility.ets`
  - 应用入口，负责自启动 host

### Native

- `Agent/entry/src/main/cpp/napi_init.cpp`
  - N-API 模块入口
- `Agent/entry/src/main/cpp/CMakeLists.txt`
  - native 构建配置
- `Agent/entry/src/main/cpp/build_codex_ohos_host.cmd`
  - Rust host 交叉编译脚本

### Rust

- `codex-main/codex-rs/ohos-host/src/lib.rs`
  - 鸿蒙嵌入式 host 主逻辑
- `codex-main/codex-rs/app-server/`
  - 上游协议入口
- `codex-main/codex-rs/core/`
  - 线程、回合、工具、审批、模型核心逻辑
- `codex-main/codex-rs/state/`
  - 持久化
- `codex-main/codex-rs/rollout/`
  - 事件与回放

## 构建环境

建议环境：

- Windows
- DevEco Studio
- OpenHarmony / HarmonyOS SDK
- Rust `1.93.0`
- Rust target:
  - `aarch64-unknown-linux-ohos`
  - `x86_64-unknown-linux-ohos`

安装 target：

```powershell
rustup target add --toolchain 1.93.0-x86_64-pc-windows-msvc aarch64-unknown-linux-ohos
rustup target add --toolchain 1.93.0-x86_64-pc-windows-msvc x86_64-unknown-linux-ohos
```

### 可能需要调整的路径

如果 DevEco SDK 不在默认位置，需要检查这些文件里的硬编码路径：

- `codex-main/codex-rs/.cargo/config.toml`
- `codex-main/codex-rs/toolchains/ohos-aarch64-clang.cmd`
- `codex-main/codex-rs/toolchains/ohos-x86_64-clang.cmd`
- `Agent/entry/src/main/cpp/build_codex_ohos_host.cmd`
- `Agent/entry/src/main/cpp/CMakeLists.txt`

## 构建方式

### 在 DevEco 中构建

打开项目时，应打开：

- `OpenHarmony/Agent`

不要直接把根目录 `OpenHarmony` 当作 DevEco 工程打开。

### 命令行构建

在 `Agent/` 目录执行：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode project -p product=default assembleApp
```

如果只想构建 HAP：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry@default -p product=default assembleHap
```

## ABI 切换

当前 ABI 配置在：

- `Agent/entry/build-profile.json5`

当前同时启用了：

- `arm64-v8a`
- `x86_64`

如果要切换：

- 模拟器调试
  - 只保留 `x86_64`
- 真机调试
  - 只保留 `arm64-v8a`

这样做的好处：

- 包体明显变小
- 本地编译缓存明显减少
- 构建速度更快

## 包体与本地缓存

### 当前安装包大小

当前 HAP 约为：

- 已签名 HAP：约 `708 MB`

包体大的主要原因不是 ArkTS，也不是图片资源，而是两个 native so：

- `libs/x86_64/libcodexhost.so`
- `libs/arm64-v8a/libcodexhost.so`

### 为什么本地会涨到几十 GB

这是构建缓存，不是应用本体。

当前最大的目录通常是：

- `Agent/.cargo-target/`
- `Agent/entry/build/`
- `Agent/entry/.cxx/`

原因：

- 编译了完整 Rust workspace
- 双 ABI
- DevEco native 构建缓存
- Rust 中间产物很多

### 可安全清理的目录

这些目录删掉不会影响源码，只会导致下次重新编译：

- `Agent/.cargo-target/`
- `Agent/entry/build/`
- `Agent/entry/.cxx/`
- `Agent/build/`
- `codex-main/codex-rs/target/`

## 调试

### 重要日志

- `Agent/.hvigor/outputs/build-logs/build.log`
- `Agent/build_codex_ohos_host_full.log`

### 运行时重点日志标签

- `CodexHost`

如果应用连不上后端，优先看：

- host 是否启动
- 是否 ready
- 是否监听在 `ws://127.0.0.1:7456`

## 当前已知限制

- provider 配置不是热加载
- 第三方 OpenAI-compatible 服务兼容性还要逐个验证
- 包体偏大
- 真机侧完整能力还没全链路验证
- 当前根仓库仍可能有开发中的本地未提交改动，例如 ABI 配置切换

## Git 管理说明

当前仓库已经把 `codex-main` 源码纳入版本管理。

同时仍然忽略这些内容：

- `codex-main` 编译产物和缓存
- `Agent` 构建产物
- 签名材料
- 本地 IDE / hvigor 缓存

也就是说：

- 别人 clone 后可以拿到源码
- 但仍然需要本地安装 DevEco SDK 和 Rust 目标环境才能编译

## 下一步建议

建议按这个顺序继续推进：

1. 把 ABI 默认切成单架构开发模式
2. 继续验证 OpenRouter 等第三方 provider 的兼容性
3. 做一轮包体瘦身
4. 做真机 smoke test
5. 视需要进一步裁剪 `ohos-host` 依赖链

## 相关文档

- `AI_CONTEXT_zh.md`
  - 当前工作区交接上下文
- `codex-main/docs/architecture_zh.md`
  - 上游 Codex 架构中文分析
- `codex-main/codex-rs/app-server/README.md`
  - app-server 协议说明
- `codex-main/README.md`
  - 上游项目总览
