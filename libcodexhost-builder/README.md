# libcodexhost-builder

ArkPilot 项目的独立构建模块，负责将 Rust 编写的 `codex-ohos-host` 编译为 OpenHarmony 原生共享库 `libcodex_ohos_host.so`，供 Agent 应用通过 N-API 桥接层调用。

## 项目结构

```text
libcodexhost-builder/
├── build.bat                       # cmd/批处理构建脚本
├── build.ps1                       # PowerShell 构建脚本
└── README.md
```

## 构建产物

构建输出 `libcodex_ohos_host.so`，包含以下 C FFI 接口：

| 分类 | 接口 |
|------|------|
| 服务管理 | `start`, `is_running`, `last_message`, `server_url` |
| Provider 配置 | `provider_config_json`, `save_provider_config`, `provider_catalog_json`, `save_provider_catalog` |
| Skills 管理 | `skills_registry_json`, `save_skills_registry`, `skills_repos_json`, `save_skills_repos`, `install_skill_from_dir`, `uninstall_skill`, `set_skill_enabled`, `reconcile_skills` |
| Prompts 管理 | `prompts_registry_json`, `save_prompts_registry`, `read_agents_md`, `write_agents_md` |
| 对话引擎 | `initialize`, `thread_start`, `turn_start`, `turn_events`, `turn_poll` |
| 审批流程 | `approval_poll`, `approval_approve`, `approval_decline` |
| MCP 服务 | `mcp_status_list`, `mcp_config_read`, `mcp_config_write`, `mcp_config_batch_write`, `mcp_reload`, `mcp_oauth_start` |
| 账户管理 | `account_login`, `account_read` |

## 环境依赖

- **DevEco Studio** 及其 OpenHarmony Native SDK
- **Rust 工具链**（含 `cargo`），需添加 `aarch64-unknown-linux-ohos` 和/或 `x86_64-unknown-linux-ohos` target
- **CMake**（随 DevEco SDK 自带）
- **Ninja**（随 DevEco SDK 自带）

## 构建流程说明

当前推荐使用 `build.bat` 或 `build.ps1` 作为唯一入口。

外层脚本会直接完成：

1. 调用 `cargo` 交叉编译 `codex-ohos-host`
2. 将生成的 `.so` 复制到 Agent 工程

如果已经有预构建的 `.so`，也可以通过 `PREBUILT_RUST_SHARED_LIB` 跳过 Rust 编译。

## SDK 路径发现

`build.bat` 和 `build.ps1` 都会按以下顺序查找 DevEco SDK：

1. 环境变量 `DEVECO_SDK_HOME`
2. `C:\Program Files\Huawei\DevEco Studio\sdk`
3. `D:\develop\deveco\DevEco Studio\sdk`
4. `D:\DevEco Studio\sdk`

如路径不在上述列表中，请显式设置 `DEVECO_SDK_HOME`。

## 使用方式

### 快速构建（cmd/批处理）

```bat
build.bat debug x86_64
build.bat release arm64-v8a
build.bat debug x86_64 --no-install
```

### 快速构建（PowerShell）

```powershell
.\build.ps1 debug x86_64
.\build.ps1 release arm64-v8a
.\build.ps1 debug x86_64 -NoInstall
```

构建产物默认安装到：

- `../Agent/entry/libs/<ABI>/libcodex_ohos_host.so`

### 使用预构建的 Rust 库

PowerShell：

```powershell
$env:PREBUILT_RUST_SHARED_LIB = "E:\path\to\libcodex_ohos_host.so"
.\build.ps1 release x86_64
```

cmd：

```bat
set PREBUILT_RUST_SHARED_LIB=E:\path\to\libcodex_ohos_host.so
build.bat release x86_64
```

## 支持的架构

| ABI | Rust Target Triple | 用途 |
|-----|-------------------|------|
| `arm64-v8a` | `aarch64-unknown-linux-ohos` | 真机 |
| `x86_64` | `x86_64-unknown-linux-ohos` | 模拟器 |

## 与 Agent 项目的关系

```text
codex-main/codex-rs/          Rust 源码（ohos-host crate）
        │
        ▼
libcodexhost-builder/         外层脚本编译 Rust
        │
        ▼
Agent/entry/libs/             安装目标目录
        │
        ▼
Agent/entry/src/main/cpp/     N-API 桥接层（dlopen + dlsym 加载 .so）
        │
        ▼
Agent/entry/src/main/ets/     ArkTS 业务层调用
```

构建脚本在编译完成后会自动将 `.so` 复制到 Agent 项目的 `libs` 目录，确保 DevEco Studio 打包时能包含该原生库。
