# ArkPilot

ArkPilot 是一个面向 HarmonyOS / OpenHarmony 的 AI Agent 实验仓库，用来把 `codex host` 能力接入鸿蒙应用。当前仓库由三个部分组成：鸿蒙前端应用、Rust 原生 Host，以及用于产出 `.so` 的独立构建模块。

如果你想快速了解应用侧能力，请先看 `Agent/README.md`；如果你要编译原生库，请看 `libcodexhost-builder/README.md`。

## 仓库组成

```text
ArkPilot/
├─ Agent/                  # HarmonyOS 应用，ArkTS UI + NAPI 桥接
├─ codex-main/             # Rust 侧源码，其中包含 ohos-host crate
└─ libcodexhost-builder/   # 独立 CMake 构建模块，产出 libcodex_ohos_host.so
```

### 1. Agent

`Agent/` 是鸿蒙端应用工程，负责：

- 提供 Chat 工作台与会话界面
- 管理 Provider、MCP、Prompts、Skills
- 通过 `libentry.so` 调用原生桥接层
- 在应用启动时拉起内置 `codex host`

入口与关键代码主要在：

- `Agent/entry/src/main/ets/entryability/EntryAbility.ets`
- `Agent/entry/src/main/ets/pages/Index.ets`
- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
- `Agent/entry/src/main/ets/backend/CodexNative.ets`
- `Agent/entry/src/main/cpp/napi_init.cpp`

更完整说明见 `Agent/README.md`。

### 2. codex-main

`codex-main/` 存放 Rust 侧源码，其中 `codex-main/codex-rs/ohos-host` 会编译出：

- `libcodex_ohos_host.so`

这个动态库为鸿蒙应用提供宿主能力，包括：

- host 启停与状态查询
- thread / turn / poll 对话接口
- approval 审批接口
- provider / prompts / skills / MCP 配置读写
- account 登录状态读取

关键 crate 配置位于：

- `codex-main/codex-rs/ohos-host/Cargo.toml`

### 3. libcodexhost-builder

`libcodexhost-builder/` 是独立的原生构建模块，负责把 Rust host 交叉编译为 OpenHarmony 可加载的共享库，并安装到 Agent 工程中。

它主要负责：

- 调用 DevEco / OpenHarmony Native SDK 工具链
- 编译 `codex-ohos-host`
- 生成 `libcodex_ohos_host.so`
- 将产物复制到 `Agent/entry/libs/<ABI>/`

详细说明见：

- `libcodexhost-builder/README.md`

## 整体架构

```text
ArkTS UI
  ↓
CodexBackend.ets
  ↓
CodexNative.ets
  ↓
libentry.so (NAPI)
  ↓
dlopen("libcodex_ohos_host.so")
  ↓
Rust codex-ohos-host
```

应用启动后，`EntryAbility.ets` 会调用 `startEmbeddedCodexHost()`，默认以 `ws://127.0.0.1:7456` 作为本地服务地址启动 embedded host，并在首次启动时自动导入已有 `AGENTS.md`。

## 当前状态

仓库目前明显处于开发中，至少可以从现有代码看出以下事实：

- 根目录 `README.md` 曾被删除，当前这份文档用于补充整体说明
- `Agent/README.md` 已经包含较完整的应用侧能力介绍
- `Agent` 已接入 external native build，CMake 配置位于 `Agent/entry/src/main/cpp/CMakeLists.txt`
- 原生桥接文件已迁移到 `Agent/entry/src/main/cpp/`
- 仓库依赖 `libcodex_ohos_host.so` 才能完整跑通应用内 host 能力

## 快速上手

### 只看应用能力

直接阅读：

- `Agent/README.md`

它更适合了解页面、功能和模块边界。

### 编译原生库

优先阅读：

- `libcodexhost-builder/README.md`

常见构建方式示例：

```bat
build.bat debug x86_64
build.bat release arm64-v8a
```

构建成功后，产物会安装到：

- `Agent/entry/libs/<ABI>/libcodex_ohos_host.so`

### 打开鸿蒙应用工程

在 DevEco Studio 中打开：

- `Agent/`

当前 `entry` 模块已经声明 external native build：

- `Agent/entry/build-profile.json5`

依赖的本地类型包配置位于：

- `Agent/entry/oh-package.json5`

## 运行前提

要跑通完整链路，至少需要：

- DevEco Studio / HarmonyOS 构建环境
- OpenHarmony Native SDK
- Rust 工具链与对应 Ohos target
- 成功编译并打包进应用的 `libcodex_ohos_host.so`

如果缺少原生库，ArkTS 页面可能可以编译，但 embedded host、Provider、Prompts、Skills、MCP 等能力无法完整工作。

## 建议阅读顺序

如果你是第一次进入这个仓库，推荐按下面顺序阅读：

1. `README.md`
2. `Agent/README.md`
3. `libcodexhost-builder/README.md`
4. `Agent/entry/src/main/ets/entryability/EntryAbility.ets`
5. `Agent/entry/src/main/ets/pages/Index.ets`
6. `Agent/entry/src/main/cpp/napi_init.cpp`
7. `codex-main/codex-rs/ohos-host/Cargo.toml`

## 适合的使用场景

这个仓库更适合：

- 研究 AI Agent 在 HarmonyOS 上的接入方式
- 验证 ArkTS + NAPI + Rust host 的跨层桥接方案
- 继续完善鸿蒙端的 Provider / MCP / Prompts / Skills 一体化管理
- 做 embedded host 方案的真机或模拟器实验

## 说明

当前根 README 的目标是补齐仓库级导航，而不是替代各子项目文档。具体实现细节、构建命令和限制说明，请分别以 `Agent/README.md` 与 `libcodexhost-builder/README.md` 为准。
