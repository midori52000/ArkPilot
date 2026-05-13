# ArkPilot Agent

ArkPilot Agent 是一个运行在 HarmonyOS / OpenHarmony 上的 Codex 风格 AI Agent 前端实验项目。它通过 ArkTS UI + NAPI + Native 动态库桥接的方式，把内置 Rust `codex host` 能力接入到鸿蒙应用中，在设备侧提供会话、diff、审批、Provider、MCP、Prompts、Skills 等管理界面。

## 项目目标

这个项目的核心目标是验证以下链路在鸿蒙侧是否可行：

- 应用启动时自动拉起内置 `codex host`
- ArkTS 前端通过 `libentry.so` 调用 Native 桥接层
- Native 桥接层再动态加载 `libcodex_ohos_host.so`
- 前端直接消费线程、turn、diff、审批、MCP、Prompt、Skill、Provider 等能力

## 当前功能

### 1. Chat 工作台

主界面位于 `entry/src/main/ets/pages/Index.ets`。

支持：

- 自动连接应用内置后端
- 多会话切换与新建会话
- 指定工作目录 `workspaceRoot`
- 发送 turn 请求
- 展示消息流、摘要、变更文件和 unified diff
- 展示审批卡片，并允许用户批准或拒绝
- 手动连接 / 断开后端
- 选择 reasoning effort

相关实现：

- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/backend/CodexBackend.ets`
- `entry/src/main/ets/backend/CodexNative.ets`

### 2. 应用内嵌 Host 启动

应用启动入口位于 `entry/src/main/ets/entryability/EntryAbility.ets`。

启动流程：

1. 计算 `codexHome`
2. 调用 `startEmbeddedCodexHost()`
3. 通过 Native 桥接启动 embedded Rust host
4. 首次启动时自动导入已有 `AGENTS.md`

默认连接地址：

- `native://entry`：ArkTS 侧默认原生桥接地址
- `ws://127.0.0.1:7456`：启动 host 时传入的默认 server URL

相关实现：

- `entry/src/main/ets/entryability/EntryAbility.ets`
- `entry/src/main/ets/backend/CodexNative.ets`
- `entry/src/main/cpp/napi_init.cpp`
- `entry/src/main/cpp/codex_ohos_host.h`

### 3. Provider 管理

设置页内置 Provider 管理页，支持维护模型服务商配置。

支持：

- 预设 Provider 快速创建
- 自定义 Provider 编辑
- Provider 激活与同步到 live config
- API Key 连通性验证
- 模型发现
- 多 endpoint 测速
- 配置导入导出
- OpenAI 风格用量查询

内置预设包括：

- OpenAI
- Anthropic
- Google AI
- AWS Bedrock
- OpenRouter
- SiliconFlow
- DeepSeek
- ZhipuAI
- Moonshot
- DashScope
- Volcengine
- NewAPI

相关实现：

- `entry/src/main/ets/pages/ApiManagementPage.ets`
- `entry/src/main/ets/apim/ApiManagementViewModel.ets`
- `entry/src/main/ets/apim/ApiManagementService.ets`
- `entry/src/main/ets/apim/ApiTypes.ets`
- `entry/src/main/ets/backend/ProviderCatalogService.ets`

### 4. MCP 管理

设置页支持读取和编辑当前用户配置中的 MCP server。

支持：

- 刷新 MCP 状态
- 重载 MCP 配置
- 查看 server health / auth / tool / resource 数量
- 编辑 transport、command、args、url、env、enabled
- 发起 OAuth 登录

相关实现：

- `entry/src/main/ets/pages/SettingsPage.ets`
- `entry/src/main/ets/backend/CodexBackend.ets`

### 5. Prompts 管理

Prompts 模块用于管理 `AGENTS.md` 风格的自定义指令。

支持：

- 创建 Prompt
- 编辑 Prompt
- 启用 / 停用 Prompt
- 实时预览 `AGENTS.md`
- 首次启动自动导入已有 `AGENTS.md`
- 删除未启用 Prompt

相关实现：

- `entry/src/main/ets/pages/PromptsPage.ets`
- `entry/src/main/ets/prompts/PromptsBackendService.ets`
- `entry/src/main/ets/prompts/PromptsViewModel.ets`

### 6. Skills 管理

Settings 中包含 Skills 管理界面与后端服务。

已具备的数据结构和服务能力包括：

- 已安装 Skill 注册表读写
- GitHub 仓库配置管理
- Skill 发现、安装、卸载、启用/禁用、更新检测
- 本地 Skill 导入
- `skills.sh` 搜索

相关实现：

- `entry/src/main/ets/skills/SkillsBackendService.ets`
- `entry/src/main/ets/skills/SkillsViewModel.ets`
- `entry/src/main/ets/skills/SkillTypes.ets`
- `entry/src/main/ets/pages/SettingsPage.ets`

## 技术架构

### 前端层

使用 ArkTS / ArkUI 构建页面与状态管理：

- `Index.ets`：主工作台
- `SettingsPage.ets`：设置页
- `ApiManagementPage.ets`：Provider 管理
- `PromptsPage.ets`：Prompt 管理

### 业务层

通过服务类和 ViewModel 封装业务逻辑：

- `CodexBackend.ets`
- `ApiManagementService.ets`
- `ProviderCatalogService.ets`
- `PromptsBackendService.ets`
- `SkillsBackendService.ets`

### Native 桥接层

NAPI 模块 `libentry.so` 负责把 ArkTS 调用转发给动态加载的 Native Host 库：

- `entry/src/main/cpp/napi_init.cpp`
- `entry/src/main/cpp/codex_ohos_host.h`

桥接层通过 `dlopen("libcodex_ohos_host.so")` 加载实际宿主库，并导出：

- host 生命周期接口
- provider 配置接口
- prompts / skills 接口
- initialize / thread / turn / approval 接口
- MCP 配置与 OAuth 接口
- account 登录状态接口

### Native Host / Rust 层

Rust host 实现不在当前目录内，当前仓库通过外部产物链接：

- `../codex-main/codex-rs/ohos-host`
- `../libcodexhost-builder`

`entry/src/main/cpp/CMakeLists.txt` 会尝试链接：

- `libcodex_ohos_host.so`

## 目录结构

```text
Agent/
├─ entry/
│  ├─ src/main/ets/
│  │  ├─ apim/                 # Provider/API 管理逻辑
│  │  ├─ backend/              # Codex backend 与 Native 包装层
│  │  ├─ entryability/         # 应用入口 Ability
│  │  ├─ pages/                # ArkUI 页面
│  │  ├─ prompts/              # Prompt 管理
│  │  └─ skills/               # Skill 管理
│  ├─ src/main/cpp/            # NAPI 桥接层
│  └─ src/main/types/          # Native 模块类型声明
├─ script/helpsetup/           # 辅助脚本说明
└─ hvigorfile.ts               # HarmonyOS 构建入口
```

## 构建相关

### 基本要求

你至少需要准备：

- DevEco Studio / HarmonyOS 构建环境
- `hvigor` / `ohpm` 对应依赖环境
- 可用的 Native 构建产物 `libcodex_ohos_host.so`

### Native 构建接入

`entry/build-profile.json5` 已开启 external native 构建：

- CMake 文件：`entry/src/main/cpp/CMakeLists.txt`

CMake 会从以下目录查找 Rust 桥接库：

- `entry/libs/${OHOS_ARCH}/libcodex_ohos_host.so`

如果这个 so 不存在，前端模块虽然可以编译 ArkTS，但运行时无法正常加载 Native Host。

### 权限

当前模块声明了网络权限：

- `ohos.permission.INTERNET`

见：`entry/src/main/module.json5`

### 页面入口

当前已注册页面：

- `pages/Index`
- `pages/SettingsPage`

见：`entry/src/main/resources/base/profile/main_pages.json`

## 运行流程概览

1. 应用启动进入 `EntryAbility`
2. 自动调用 `startEmbeddedCodexHost()`
3. ArkTS 页面连接 `CodexBackend`
4. `CodexBackend` 调用 Native initialize 接口
5. 后续通过 thread / turn / poll 完成会话交互
6. 如果出现审批请求，前端通过 approval 接口处理
7. Provider / MCP / Prompts / Skills 配置都通过 Native 接口持久化

## 数据与配置

项目当前围绕 `codexHome` 维护运行时数据。根据代码可知会涉及：

- Provider config
- Provider catalog
- Skills registry
- Skills repos
- Prompts registry
- `AGENTS.md`

其中 `PromptsBackendService` 会把启用中的 Prompt 内容写入 `AGENTS.md`。

## 当前已知限制

这是一个仍在演进中的实验项目，当前至少有以下限制：

### 1. Skills 的 ZIP 安装尚未完成

`SkillsBackendService.ets` 中的 ZIP 解压仍是占位实现：

- `extractZip()` 当前直接抛错
- `importFromZip()` 当前直接抛错

这意味着：

- GitHub Skill 下载流程依赖完整 ZIP 解压支持补齐后才能真正落地
- ZIP 包导入目前不可用

### 2. Skills 设置页目前偏“注册表管理”

`SettingsPage.ets` 里的 Skills 页主要在操作 registry / repos / backups，和 `SkillsBackendService.ets` 提供的完整安装发现流程还没有完全打通成最终 UI。

### 3. Provider 导出未见脱敏逻辑

`ApiManagementService.exportProviders()` 当前直接序列化 `providers`。如果配置中包含真实 API Key，请不要把导出内容直接分享给他人。

### 4. 依赖外部 Native 产物

当前应用能力高度依赖 `libcodex_ohos_host.so`。如果 Native 库未正确构建或未被打包：

- host 无法启动
- provider / prompt / skill / mcp 等能力会退化或不可用
- 前端只能展示有限的占位状态

## 适合谁使用

这个仓库更适合：

- 研究 Codex / Agent 能力在 HarmonyOS 上的接入方式
- 开发鸿蒙端 AI Agent 工作台
- 验证 ArkTS + NAPI + Rust host 的多层桥接方案
- 继续完善 Provider / MCP / Prompts / Skills 一体化管理能力

## 后续建议

如果你准备继续推进这个项目，优先级比较高的事情通常是：

1. 补齐 `libcodex_ohos_host.so` 的构建与打包链路
2. 完成 Skills ZIP 解压与 GitHub 安装流程
3. 补充 README 中缺失的实际构建命令与打包步骤
4. 增加真机联调说明
5. 为 Provider 导出增加脱敏逻辑

## 关键文件索引

- 应用入口：`entry/src/main/ets/entryability/EntryAbility.ets`
- 主界面：`entry/src/main/ets/pages/Index.ets`
- 设置页：`entry/src/main/ets/pages/SettingsPage.ets`
- Provider 页面：`entry/src/main/ets/pages/ApiManagementPage.ets`
- Prompt 页面：`entry/src/main/ets/pages/PromptsPage.ets`
- 后端封装：`entry/src/main/ets/backend/CodexBackend.ets`
- Native 包装：`entry/src/main/ets/backend/CodexNative.ets`
- NAPI 桥接：`entry/src/main/cpp/napi_init.cpp`
- CMake：`entry/src/main/cpp/CMakeLists.txt`

## 说明

当前这份 README 是基于现有代码结构整理出的开发说明，重点帮助后来者快速理解项目定位、模块边界和现阶段限制。如果后续补齐了 Native 构建链路、真机运行步骤或发布方式，建议再补一版更完整的安装与调试文档。
