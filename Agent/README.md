# Agent

`Agent/` 是这个工作区里的 OpenHarmony 应用工程。

它的职责不是直接实现 `codex-rs`，而是把一个已经嵌入到应用进程内的
Codex Host 包装成桌面应用，提供：

- ArkTS 图形界面
- 本地 WebSocket 会话客户端
- NAPI native bridge 接入
- HAP 构建与最终打包

## 目录结构

```text
Agent/
|-- AppScope/                     # 应用级配置
|-- entry/                        # 主模块
|   |-- src/main/ets/             # ArkTS 源码
|   |-- src/main/libs/x86_64/     # 预编译 libcodexhost.so
|   `-- src/main/types/           # native 模块类型声明
|-- script/helpsetup/             # 构建与环境初始化脚本
|-- hvigorfile.ts                 # HAP 构建完成后的二次打包钩子
|-- build-profile.json5           # 应用构建配置
`-- oh-package.json5              # 应用依赖
```

## 运行时架构

`Agent` 的运行时可以分成三层。

### 1. UI 层

ArkTS 页面主要在 `entry/src/main/ets/pages/`：

- `Index.ets`
  - 主界面
  - 负责会话输入、消息展示、diff、plan、approval、工作区选择
- `SettingsPage.ets`
  - 设置页
  - 聚合 provider、MCP、skills、prompts 等管理入口
- `ApiManagementPage.ets`
  - API/provider 管理页
- `PromptsPage.ets`
  - prompt 管理页

这层只处理界面状态和交互，不直接碰 Rust。

### 2. ArkTS 服务层

`entry/src/main/ets/backend/` 是中间服务层：

- `CodexBackend.ets`
  - 前端的 WebSocket JSON-RPC 客户端
  - 连接本地 `ws://127.0.0.1:7456`
  - 管理 thread、turn、message delta、diff、plan、approval
- `CodexHostNative.ets`
  - ArkTS 对 `libcodexhost.so` 的封装
  - 负责调用 `startHost`、`getStatus`、provider catalog、skills、prompts 等 native 能力
- `ConsoleModels.ets`
  - 前端共享模型定义
- `ProviderCatalogService.ets`
  - provider catalog 的 UI 侧封装逻辑

另外还有三个垂直功能模块：

- `entry/src/main/ets/apim/`
  - API/provider 管理模型与服务
- `entry/src/main/ets/prompts/`
  - prompts 管理模型与服务
- `entry/src/main/ets/skills/`
  - skills 管理模型与服务

### 3. Native 接入层

`Agent` 自己不编 Rust 源码，但它消费一个预编译 native 模块：

- `entry/src/main/libs/x86_64/libcodexhost.so`

并通过本地类型包导入它：

- `entry/src/main/types/libcodexhost/`
- `entry/oh-package.json5`

运行时关系是：

```text
EntryAbility.ets
  -> CodexHostNative.ets
  -> libcodexhost.so
  -> embedded codex-ohos-host
  -> local app-server (WebSocket)
  -> CodexBackend.ets
  -> UI pages
```

## 启动流程

应用入口是：

- `entry/src/main/ets/entryability/EntryAbility.ets`

当前启动链路是：

1. `EntryAbility.onCreate()` 计算 `codexHome`
2. 调 `startEmbeddedCodexHost(codexHome, ws://127.0.0.1:7456)`
3. native host 在应用内拉起 embedded app-server
4. 首次启动时自动导入已有 prompt/`AGENTS.md`
5. 页面加载后，`CodexBackend.ets` 通过 WebSocket 连到本地 host

所以这里有两个关键面：

- native 面：负责把 host 拉起来
- protocol 面：负责和 host 进行 JSON-RPC 通信

## 构建架构

`Agent` 当前已经不再内联编译 Rust/CMake。

它的构建方式是：

1. 由工作区外层的 `libcodexhost-builder` 先生成并安装 `libcodexhost.so`
2. `Agent` 再把这个预编译 so 当成 native 依赖消费

### 构建入口

日常构建用：

```bat
script\helpsetup\build.bat debug
```

这个脚本会：

- 调 `setup_env.bat`
- 自动定位 DevEco SDK
- 检查 `libcodexhost.so` 是否已安装
- 调 `hvigor assembleHap`
- 构建结束后重新打包 HAP

### 二次打包

`hvigorfile.ts` 注册了一个自定义 hvigor 插件。

它会在 HAP 构建完成后调用：

- `script/helpsetup/repack_hap_with_native.js`

这个步骤会把下面两个 native 库重新注入最终 HAP：

- `libcodexhost.so`
- `libc++_shared.so`

所以 `Agent` 的打包不是“纯 ArkTS 包”，而是“ArkTS HAP + 手动注入 native 产物”。

## 关键配置文件

- `AppScope/app.json5`
  - 应用级元数据，例如 bundleName
- `entry/src/main/module.json5`
  - 模块入口、权限、Ability 配置
- `entry/build-profile.json5`
  - 模块构建配置
- `build-profile.json5`
  - 应用构建配置
- `hvigorfile.ts`
  - 构建完成后的 native 重打包钩子

## 工作区与权限

应用里的“工作区”是会话级输入，不是 Windows 主机上的仓库目录。

前端会把 `workspaceRoot` 作为 `cwd` 传给后端，后端再把它交给 embedded host。
当前默认策略是：

- approval policy: `on-request`
- sandbox mode: `workspace-write`

但这个可写范围必须是设备内的有效目录，通常应该落在应用沙箱中，例如：

```text
/data/storage/el2/base/files/project
```

## 对外依赖边界

`Agent` 只关心两类外部输入：

- 预编译 native 库
  - `entry/src/main/libs/x86_64/libcodexhost.so`
- DevEco / hvigor / ohpm 构建环境

`Agent` 本身不负责：

- 编译 Rust workspace
- 维护 `codex-rs` 依赖图
- 生成 `libcodexhost.so`

这些职责已经被拆到工作区里的 `libcodexhost-builder/`。

## 适合在哪改什么

- 改界面布局、会话交互、显示逻辑
  - 改 `entry/src/main/ets/pages/`
- 改 WebSocket 协议适配、turn 管理、approval 处理
  - 改 `entry/src/main/ets/backend/CodexBackend.ets`
- 改 provider / prompt / skill 管理前端逻辑
  - 改 `apim/`、`prompts/`、`skills/`
- 改 native 接口签名或新增 native 能力
  - 改 `CodexHostNative.ets` 和 `entry/src/main/types/libcodexhost/`
  - 同时需要改工作区里的 `libcodexhost-builder` 和 Rust host
