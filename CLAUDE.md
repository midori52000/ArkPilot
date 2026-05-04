# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ArkPilot 是一个 HarmonyOS/OpenHarmony AI Agent 实验项目，将 Codex host 能力通过 ArkTS + NAPI + Rust 桥接接入鸿蒙应用。仓库包含三个子系统：

- **Agent/** — HarmonyOS 应用（ArkTS UI + NAPI 桥接）
- **codex-main/** — Rust 侧源码，含 `ohos-host` crate
- **libcodexhost-builder/** — 独立 CMake 构建模块，产出 `libcodex_ohos_host.so`

## Architecture (Data Flow)

```
ArkTS UI (Index.ets, SettingsPage.ets, etc.)
  → CodexBackend.ets (业务逻辑 + 状态管理)
    → CodexNative.ets (类型安全的 Native 调用封装)
      → libentry.so (NAPI 桥接层, napi_init.cpp)
        → dlopen("libcodex_ohos_host.so") (Rust FFI)
```

`CodexNative.ets` 通过 `import entry from 'libentry.so'` 调用 NAPI 导出函数，所有 Native 调用都包裹了 null-safe 降级逻辑。`CodexBackend.ets` 是核心业务层，管理连接状态、会话轮询、审批流和配置同步。

## Key Files

### ArkTS 前端 (Agent/entry/src/main/ets/)
- `entryability/EntryAbility.ets` — 应用入口，启动 embedded host、导入 AGENTS.md、安装 bundled skills
- `pages/Index.ets` — 主 Chat 工作台
- `pages/SettingsPage.ets` — 设置页（MCP、Skills、Prompts）
- `pages/ApiManagementPage.ets` — Provider 管理页
- `pages/AddProviderPage.ets` — 添加 Provider 页
- `pages/PromptsPage.ets` — Prompt 管理页
- `backend/CodexBackend.ets` — 核心业务层：连接、会话、审批、配置管理
- `backend/CodexNative.ets` — Native 桥接封装层
- `backend/ConsoleModels.ets` — 数据模型定义
- `backend/ProviderCatalogService.ets` — Provider 预设目录
- `backend/ProviderConfigStore.ets` — Provider 配置持久化
- `apim/ApiManagementService.ets` — Provider/API 管理服务
- `apim/ApiManagementViewModel.ets` — Provider 管理 ViewModel
- `prompts/PromptsBackendService.ets` — Prompt 后端服务
- `prompts/PromptsViewModel.ets` — Prompt ViewModel
- `skills/SkillsBackendService.ets` — Skill 后端服务
- `skills/BundledSkills.ets` — 预设 Skill 安装逻辑

### Native 层
- `Agent/entry/src/main/cpp/napi_init.cpp` — NAPI 桥接实现，dlopen/dlsym 加载 `libcodex_ohos_host.so`
- `Agent/entry/src/main/cpp/codex_ohos_host.h` — Rust FFI 头文件，定义所有 C 接口
- `Agent/entry/src/main/types/libentry/index.d.ts` — ArkTS 类型声明，定义 `EntryBridgeModule` 接口
- `codex-main/codex-rs/ohos-host/src/lib.rs` — Rust host 主入口
- `codex-main/codex-rs/ohos-host/src/skills_registry.rs` — Skills 注册表
- `codex-main/codex-rs/ohos-host/src/skills_backup.rs` — Skills 备份
- `codex-main/codex-rs/ohos-host/src/skills_hash.rs` — Skills 目录哈希
- `codex-main/codex-rs/ohos-host/src/prompts_registry.rs` — Prompts 注册表

## Build Commands

### Rust 原生库构建 (libcodexhost-builder/)
```bat
build.bat debug x86_64         # 模拟器调试构建
build.bat release arm64-v8a    # 真机发布构建
build.bat debug x86_64 --no-install  # 只编译不安装到 Agent
```
PowerShell:
```powershell
.\build.ps1 debug x86_64
.\build.ps1 release arm64-v8a -NoInstall
```
使用预构建 .so：
```bat
set PREBUILT_RUST_SHARED_LIB=E:\path\to\libcodex_ohos_host.so
build.bat release x86_64
```

SDK 路径按此顺序查找：`DEVECO_SDK_HOME` → `C:\Program Files\Huawei\DevEco Studio\sdk` → `D:\develop\deveco\DevEco Studio\sdk` → `D:\DevEco Studio\sdk`

产物安装到：`Agent/entry/libs/<ABI>/libcodex_ohos_host.so`

### HarmonyOS 应用
在 DevEco Studio 中打开 `Agent/` 目录。`entry/build-profile.json5` 已配置 external native build，ABI filter 当前仅 `x86_64`。

CMake 在 `Agent/entry/src/main/cpp/CMakeLists.txt` 中条件链接 `libcodex_ohos_host.so`（若存在）。

## NAPI Bridge Convention

`napi_init.cpp` 通过 `dlopen`/`dlsym` 动态加载 Rust 库，所有函数指针以 `codex_ohos_host_` 前缀在 C 头文件中声明。新增 Native 接口需要同时修改三处：
1. `codex_ohos_host.h` — 添加 C 函数声明
2. `napi_init.cpp` — 添加 dlsym 绑定和 NAPI 导出函数
3. `index.d.ts` — 添加 ArkTS 类型声明
4. `CodexNative.ets` — 添加类型安全的封装函数

## AppStorage Keys

- `codexHome` — 应用数据根目录，`EntryAbility.onCreate` 中设置为 `${filesDir}/codex-home`
- `defaultWorkspaceRoot` — 默认工作区路径，`${filesDir}/workspace-default`

## Error Experience

### `dirs` crate v6 不读取 `$HOME` 环境变量（Skills 注入失败）
- 问题：`dirs` crate v6 在 Linux/OHOS 上改用 `/etc/passwd`（`getpwuid_r`）获取 home 目录，忽略 `$HOME` 环境变量
- 影响：`core-skills/src/loader.rs` 中 `dirs::home_dir()` 返回错误路径，`$HOME/.agents/skills` 无法被 Rust skill loader 发现
- 解决：
  1. 将 Skills SSOT 目录从 `{codexHome}/../.agents/skills` 改为 `{codexHome}/skills`
  2. 在 `configure_environment()` 中设置 `CODEX_SKILLS_DIR` 环境变量
  3. 在 `skill_roots_with_home_dir()` 中检查 `CODEX_SKILLS_DIR` 作为 fallback root
  4. 在 `discover_skills_under_root()` 中添加 canonicalize 失败日志
- 涉及文件：`ohos-host/src/lib.rs`、`ohos-host/src/skills_registry.rs`、`core-skills/src/loader.rs`、`SkillsBackendService.ets`、`BundledSkills.ets`

## Known Limitations

- `SkillsBackendService.ets` 中 `extractZip()` 和 `importFromZip()` 仍为占位实现（直接抛错）
- Provider 导出未脱敏，`exportProviders()` 直接序列化含 API Key 的配置
- 应用缺少 `libcodex_ohos_host.so` 时 ArkTS 可编译但运行时 Native 功能不可用
- `build-profile.json5` 中 ABI filter 仅配置了 `x86_64`，真机构建需改为 `arm64-v8a`

## Testing

HarmonyOS 测试框架使用 `@ohos/hypium`（单元测试）和 `@ohos/hamock`（Mock），依赖声明在 `Agent/oh-package.json5`。测试文件位于 `Agent/entry/src/ohosTest/ets/` 和 `Agent/entry/src/test/`。
