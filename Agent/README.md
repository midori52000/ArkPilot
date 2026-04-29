# ArkPilot Agent

基于 OpenHarmony 的 ArkTS 应用，包含 C++ 原生模块。

## 快速开始

### 环境要求

1. **DevEco Studio 4.1+** - [下载地址](https://developer.harmonyos.com/cn/develop/deveco-studio)
2. **Node.js 18+** - [下载地址](https://nodejs.org/)
3. **Rust 1.70+** - [安装指南](https://rustup.rs/)
4. **OpenHarmony SDK 6.1.0**

### 一键配置（Windows）

运行以下脚本自动配置环境：

```bash
# 运行环境配置脚本
setup_env.bat

# 启动 DevEco Studio（推荐）
quick_start.bat

# 或手动构建
build.bat
```

### 手动配置

#### 1. 安装依赖

```bash
# 安装 Hvigor 构建工具
npm install -g @ohos/hvigor

# 安装 OpenHarmony Rust targets
rustup target add aarch64-unknown-linux-ohos
rustup target add x86_64-unknown-linux-ohos
```

#### 2. 设置环境变量

```bash
# Windows
set OHOS_NATIVE=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
set PATH=%OHOS_NATIVE%\build-tools\cmake\bin;%PATH%
set PATH=%OHOS_NATIVE%\llvm\bin;%PATH%

# Linux/macOS
export OHOS_NATIVE=/path/to/DevEcoStudio/sdk/default/openharmony/native
export PATH=$OHOS_NATIVE/build-tools/cmake/bin:$PATH
export PATH=$OHOS_NATIVE/llvm/bin:$PATH
```

#### 3. 构建项目

```bash
# 安装项目依赖
npm install

# 构建 HAP 包
hvigor assembleHap

# 或使用构建脚本
build.bat      # Windows
./build.sh     # Linux/macOS
```

#### 4. 安装到设备

```bash
# 安装到连接的设备
hdc install entry/build/default/outputs/default/entry-default-unsigned.hap
```

### 使用 DevEco Studio（推荐）

1. 运行 `quick_start.bat` 或手动打开 DevEco Studio
2. 选择 "Open" → 打开项目目录
3. 等待项目同步完成
4. 选择设备（模拟器或真实设备）
5. 点击运行按钮（绿色三角形）

## 项目架构

ArkPilot Agent 是一个 OpenHarmony 原生 AI 编程助手应用。它在应用内嵌入 Rust 编写的 Codex AI 后端服务（app-server），通过 WebSocket JSON-RPC 协议与 ArkTS 前端通信。

### 整体分层

```
┌──────────────────────────────────────────┐
│       ArkTS UI 前端 (entry/src/main/ets/) │
│  pages/    — 三栏式 AI 对话界面           │
│  backend/  — WebSocket RPC 客户端         │
│  backend/  — NAPI 桥接封装                │
├──────────────────────────────────────────┤
│     C++ NAPI 桥接层 (entry/src/main/cpp/) │
│  napi_init.cpp — 封装 Rust FFI 为 NAPI    │
├──────────────────────────────────────────┤
│  Rust 原生后端 (外部仓 codex-main/codex-rs)│
│  codex-ohos-host — AI app-server         │
│  WebSocket 服务 + LLM 推理调度             │
└──────────────────────────────────────────┘
```

### 数据流

1. **应用启动** → `EntryAbility.onCreate()` 调用 `startEmbeddedCodexHost()` → C++ NAPI → Rust FFI → 在应用沙箱内启动本地 WebSocket 服务器（默认 `ws://127.0.0.1:7456`）
2. **握手** → 前端发送 `initialize` 请求，app-server 返回平台信息，前端回复 `initialized` 完成握手
3. **用户发送消息** → `Index.ets` 调用 `codexBackend.startTurn()` → 先 `thread/start` 获取远程线程 ID → 再 `turn/start` 发送 prompt
4. **流式响应** → app-server 推送一系列通知，`CodexBackend` 分别处理：
   - `item/started` / `item/completed` — 消息和工具调用生命周期
   - `item/agentMessage/delta` — 流式消息增量，逐字符追加到对话
   - `turn/plan/updated` — 推理计划/步骤更新
   - `turn/diff/updated` — 文件 diff，解析 unified diff 格式并渲染到右侧面板
   - `turn/completed` — turn 结束，触发 Promise resolve
5. **权限审批** — app-server 发送 `item/commandExecution/requestApproval`、`item/fileChange/requestApproval`、`item/permissions/requestApproval` 等请求 → UI 弹出确认卡片 → 用户允许/拒绝后返回 RPC result

### 各文件夹职责

**`AppScope/`** — 应用全局配置
- `app.json5` 定义应用包名、版本等元信息
- `resources/` 存放应用级别的全局资源（图标、字符串等）

**`entry/`** — 主模块（核心代码所在）

| 子目录 | 职责 |
|---|---|
| `src/main/ets/pages/` | UI 页面。`Index.ets` 是三栏式 AI 对话界面：左侧栏管理连接、会话列表和 Provider 配置；中间栏展示对话消息、输入框和推理计划；右侧栏实时渲染 unified diff |
| `src/main/ets/backend/` | 后端逻辑层。`CodexBackend.ets` 是前端核心——通过 `@ohos.net.webSocket` 与 Rust app-server 建立 WebSocket 连接，实现 JSON-RPC 2.0 协议，管理线程/会话状态，处理流式 delta、diff、计划、审批等通知。`CodexHostNative.ets` 封装对 C++ NAPI 模块 `libcodexhost.so` 的调用，管理嵌入式 Rust 后端的生命周期和 Provider 配置读写 |
| `src/main/ets/entryability/` | 应用入口。`EntryAbility.ets` 在 `onCreate` 时启动内嵌 Rust app-server，加载 `pages/Index` |
| `src/main/ets/entrybackupability/` | 备份扩展。标准 HarmonyOS 备份恢复能力，当前为空实现 |
| `src/main/cpp/` | C++ NAPI 桥接层。`napi_init.cpp` 将 Rust 导出的 C 函数（`codex_ohos_host_start`、`codex_ohos_host_is_running`、`codex_ohos_host_provider_config_json` 等）注册为 NAPI 模块 `libcodexhost.so`。`CMakeLists.txt` 在构建时先通过 `build_codex_ohos_host.cmd` 交叉编译 Rust 静态库（aarch64/x86_64-unknown-linux-ohos），再将其与 NAPI 代码动态链接 |
| `src/main/cpp/types/libcodexhost/` | NAPI 类型声明。`index.d.ts` 声明 `NativeCodexHostStatus`、`NativeCodexProviderConfig` 等接口，供 ArkTS 侧类型检查 |
| `src/main/resources/` | 模块级资源，包括 UI 字符串、媒体文件、暗色主题配色等 |

**`hvigor/`** — HarmonyOS 构建工具 Hvigor 的元数据目录

**`oh_modules/`** — npm 依赖包。`@ohos/hypium`（测试框架）、`@ohos/hamock`（Mock 框架）

**`.hvigor/`** — Hvigor 构建缓存和输出（自动生成）

**`.cargo-target/`** — Rust 交叉编译产物目录（libcodex_ohos_host.a 等）

### 技术栈

| 层 | 技术 |
|---|---|
| UI 框架 | ArkTS (HarmonyOS 声明式 UI) |
| 构建系统 | Hvigor + CMake + Cargo |
| 网络协议 | WebSocket JSON-RPC 2.0 |
| 原生桥接 | NAPI (C++ ↔ ArkTS) + C FFI (C++ ↔ Rust) |
| 后端语言 | Rust，交叉编译至 `aarch64/x86_64-unknown-linux-ohos` target，放置在父目录 `codex-main/codex-rs/` |

## 项目结构

```
Agent/
├── AppScope/                          # 应用全局配置
│   ├── app.json5                      # 应用包名、版本等元信息
│   └── resources/                     # 全局资源（图标、字符串）
├── entry/                             # 主模块
│   ├── src/main/
│   │   ├── ets/                       # ArkTS 源码
│   │   │   ├── backend/               # 后端逻辑
│   │   │   │   ├── CodexBackend.ets   # WebSocket JSON-RPC 客户端核心
│   │   │   │   └── CodexHostNative.ets# NAPI 桥接封装（管理 Rust 后端）
│   │   │   ├── pages/
│   │   │   │   └── Index.ets          # 三栏式 AI 对话主界面
│   │   │   ├── entryability/
│   │   │   │   └── EntryAbility.ets   # 应用入口，启动 Rust app-server
│   │   │   └── entrybackupability/    # 备份恢复扩展（空实现）
│   │   ├── cpp/                       # C++ NAPI 桥接层
│   │   │   ├── napi_init.cpp          # Rust FFI → NAPI 封装
│   │   │   ├── CMakeLists.txt         # CMake + Cargo 联合构建配置
│   │   │   ├── build_codex_ohos_host.cmd  # Rust 交叉编译脚本
│   │   │   └── types/libcodexhost/    # NAPI 类型声明
│   │   └── resources/                 # 模块资源（UI 字符串、媒体、暗色主题）
│   └── build-profile.json5            # 模块构建配置（CMake 集成、ABI）
├── build-profile.json5                # 应用构建配置（签名、SDK 版本、模块注册）
├── oh-package.json5                   # 项目依赖（hypium 测试框架等）
├── hvigorfile.ts                      # Hvigor 构建入口脚本
├── build.sh                           # 命令行构建脚本
├── .cargo-target/                     # Rust 交叉编译产物目录
├── .hvigor/                           # Hvigor 构建缓存和输出
├── hvigor/                            # Hvigor 元数据
├── oh_modules/                        # npm 依赖
├── 启动指南.md                         # 详细启动说明
└── CLEANUP_README.md                  # 清理说明
```

## 脚本说明

| 脚本文件 | 说明 |
|---------|------|
| `setup_env.bat` | 环境配置脚本（Windows） |
| `quick_start.bat` | 快速启动 DevEco Studio |
| `build.bat` / `build.sh` | 项目构建脚本 |
| `start.bat` / `start.sh` | 启动助手（环境检查+构建） |
| `set_env.bat` | 环境变量设置脚本 |

## 开发说明

### ArkTS 开发

- 主入口：`entry/src/main/ets/entryability/EntryAbility.ets`
- 主页面：`entry/src/main/ets/pages/Index.ets`
- 后端逻辑：`entry/src/main/ets/backend/`

### C++ 原生模块

- CMake 配置：`entry/src/main/cpp/CMakeLists.txt`
- 构建脚本：`entry/src/main/cpp/build_codex_ohos_host.cmd`
- 类型定义：`entry/src/main/cpp/types/libcodexhost/`

### 构建配置

- 应用配置：`build-profile.json5`
- 模块配置：`entry/build-profile.json5`
- 依赖管理：`oh-package.json5`

## 常见问题

### 1. 构建失败：缺少 OpenHarmony SDK

**解决方案**：
- 确认 DevEco Studio 已安装
- 检查 `OHOS_NATIVE` 环境变量是否正确设置
- 运行 `setup_env.bat` 自动配置

### 2. Rust 模块构建失败

**解决方案**：
```bash
# 检查 Rust 安装
rustc --version

# 检查 OpenHarmony targets
rustup target list | grep ohos

# 如果缺少 targets
rustup target add aarch64-unknown-linux-ohos
rustup target add x86_64-unknown-linux-ohos
```

### 3. Hvigor 命令未找到

**解决方案**：
```bash
# 全局安装
npm install -g @ohos/hvigor

# 或使用项目本地版本
npx hvigor assembleHap
```

### 4. 设备连接失败

**解决方案**：
```bash
# 检查设备连接
hdc list targets

# 如果无设备，确保：
# 1. 设备已开启开发者模式
# 2. USB 调试已开启
# 3. 已安装设备驱动
```

### 5. 签名错误

**解决方案**：
- 调试版本使用自动生成的调试证书
- 发布版本需要申请正式签名证书
- 检查 `build-profile.json5` 中的签名配置

## 调试

### 查看日志
```bash
# 查看设备日志
hdc shell hilog
```

### 远程调试
1. 在 DevEco Studio 中启用远程调试
2. 使用 ArkTS 调试器设置断点
3. 查看变量和调用栈

### 性能分析
使用 DevEco Studio 的性能分析工具：
- CPU Profiler
- Memory Profiler
- Network Profiler

## 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 许可证

[待添加]

## 支持

- 问题反馈：[GitHub Issues](https://github.com/your-repo/issues)
- 文档：[项目 Wiki](https://github.com/your-repo/wiki)
- 讨论：[GitHub Discussions](https://github.com/your-repo/discussions)