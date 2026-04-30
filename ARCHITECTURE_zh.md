# OpenHarmony Codex Agent 软件架构与编译流程

## 1. 目标与当前边界

这个工作区的目标不是单独发布上游 Codex，而是把真实的 `codex-rs app-server`
嵌入到 OpenHarmony 图形应用里，让 ArkTS 前端直接在应用进程内使用它。

当前工作区只保留三块核心内容：

- `Agent/`
  - OpenHarmony 应用工程
- `libcodexhost-builder/`
  - 单独构建 `libcodexhost.so` 的 native 工程
- `codex-main/codex-rs/`
  - 上游 Rust 工作区

这里有一个重要设计原则：

- `Agent` 负责 UI、HAP 构建和最终打包
- `libcodexhost-builder` 负责 native `.so` 产物
- `codex-main/codex-rs` 负责真实后端实现

也就是说，主应用构建已经不再内联编译 Rust/native；它只消费预编译好的
`libcodexhost.so`。

## 2. 总体架构

运行时可以分成两条链路：

- 控制链路
  - ArkTS 调用 native 模块，启动 embedded host、查询状态、读写 provider 配置
- 数据链路
  - ArkTS 通过本地 WebSocket 和 embedded `codex-rs app-server` 通信，传输 JSON-RPC

可以把整体结构理解成：

```text
ArkTS UI
  |
  | 1. 状态展示 / 用户输入
  v
CodexBackend.ets
  |
  | 2. WebSocket JSON-RPC
  v
ws://127.0.0.1:7456
  |
  v
embedded codex-rs app-server

ArkTS UI / EntryAbility
  |
  | A. NAPI 调用
  v
CodexHostNative.ets
  |
  v
libcodexhost.so
  |
  v
codex-ohos-host (Rust staticlib + C++ bridge)
  |
  v
codex-rs app-server
```

这两条链路的分工非常明确：

- `CodexHostNative.ets` 只负责“宿主控制面”
- `CodexBackend.ets` 只负责“协议数据面”

## 3. 目录与职责

### 3.1 `Agent/`

这是最终的 HarmonyOS / OpenHarmony 应用。

关键文件：

- `Agent/AppScope/app.json5`
  - 应用级元数据，包含 `bundleName`
- `Agent/entry/src/main/module.json5`
  - 模块声明、权限、入口 Ability
- `Agent/entry/src/main/ets/entryability/EntryAbility.ets`
  - 应用启动入口，在 `onCreate()` 中拉起 embedded host
- `Agent/entry/src/main/ets/pages/Index.ets`
  - 主界面，负责展示消息、计划、diff、provider 配置、审批 UI
- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
  - WebSocket JSON-RPC 客户端，负责线程、turn、流式消息、审批协议
- `Agent/entry/src/main/ets/backend/CodexHostNative.ets`
  - ArkTS 对 native 模块的封装
- `Agent/entry/src/main/types/libcodexhost/index.d.ts`
  - `libcodexhost.so` 的类型声明
- `Agent/entry/src/main/libs/x86_64/libcodexhost.so`
  - 预编译 native 库

### 3.2 `libcodexhost-builder/`

这是从主应用构建里拆出来的独立 native builder。

关键文件：

- `libcodexhost-builder/build.bat`
  - 独立构建入口
- `libcodexhost-builder/CMakeLists.txt`
  - native 桥接层链接规则
- `libcodexhost-builder/native/build_codex_ohos_host.cmd`
  - 调用 Cargo 为 OHOS 目标编译 Rust staticlib
- `libcodexhost-builder/native/bridge/napi_init.cpp`
  - NAPI 导出层，把 ArkTS 调用转成 C ABI

### 3.3 `codex-main/codex-rs/`

这是上游真实 Rust 工作区。

当前最关键的 crate：

- `ohos-host`
  - HarmonyOS 嵌入宿主
- `app-server`
  - 本地 WebSocket / JSON-RPC 服务
- `core`
  - 核心运行时能力
- `protocol`
  - 协议定义
- 以及 `ohos-host` 传递依赖到的一批 workspace crate

注意：

- 现在可以删掉 `codex-main` 外围目录
- 但不能把 `codex-rs` 想象成只留 `ohos-host` 就够
- `ohos-host` 依赖的是整个 Rust workspace 的一大段闭包

## 4. 运行时架构

### 4.1 UI 层

`Index.ets` 是当前主界面。它负责：

- 展示连接状态
- 展示当前 summary / plan / diff
- 展示会话消息
- 收集用户输入
- 处理审批请求
- 管理 provider 配置

UI 不直接碰 Rust，也不直接处理 native FFI。

### 4.2 WebSocket 协议层

`CodexBackend.ets` 是数据面核心。

它负责：

- 建立 WebSocket 连接
- 发送 `initialize / initialized`
- 发送 `thread/start`
- 发送 `turn/start`
- 接收 streaming 消息
- 合并 `item/agentMessage/delta`
- 接收 `turn/diff/updated`
- 接收 `turn/plan/updated`
- 接收 `turn/completed`
- 处理命令、文件和权限审批

它本质上是一个前端状态机，把 app-server 的 JSON-RPC 事件翻译成 ArkTS UI 可消费的状态。

### 4.3 Native 桥接层

`CodexHostNative.ets` + `libcodexhost.so` 组成控制面桥接层。

当前暴露给 ArkTS 的能力主要有：

- `startHost(codexHome, serverUrl)`
- `getStatus()`
- `isHostRunning()`
- `getLastMessage()`
- `getServerUrl()`
- `getProviderConfig(codexHome?)`
- `saveProviderConfig(codexHome?, baseUrl?, apiKey?, model?)`

其中：

- `CodexHostNative.ets` 负责类型归一化和容错
- `napi_init.cpp` 负责 NAPI 导出
- Rust `ohos-host` 负责真正的业务实现

### 4.4 Rust embedded host

`codex-main/codex-rs/ohos-host/src/lib.rs` 是嵌入式宿主的核心。

它负责：

- 解析 `codex_home` 和 `listen_url`
- 初始化 `CODEX_HOME` / `HOME`
- 生成 provider 配置
- 启动 Tokio runtime
- 调用 `run_main_with_transport(...)`
- 以 WebSocket 模式监听 `ws://127.0.0.1:7456`
- 轮询端口可达性，判断 app-server 是否 ready

同时它还维护了一个进程内状态：

- 是否正在运行
- 当前监听 URL
- 最近一条状态消息
- 当前使用的 `codex_home`

### 4.5 Provider 配置

provider 配置由 Rust host 维护，而不是 ArkTS 自己拼接请求直接访问外网。

配置文件位置：

- `<codexHome>/harmony-provider.json`
- `<codexHome>/config.toml`

默认行为：

- 默认 base URL 是 `https://api.openai.com/v1`
- provider id 是 `harmony-openai-compatible`
- `wire_api = "responses"`
- `approval_policy = "on-request"`
- `sandbox_mode = "workspace-write"`

这意味着前端改 provider 后，需要重新启动应用，让 embedded app-server 重新加载配置。

## 5. 启动流程

应用启动时的顺序如下：

1. OpenHarmony 启动 `EntryAbility`
2. `EntryAbility.onCreate()` 调用 `startEmbeddedCodexHost(...)`
3. ArkTS 进入 `CodexHostNative.ets`
4. NAPI 调到 `libcodexhost.so`
5. `libcodexhost.so` 再调 Rust `codex_ohos_host_start(...)`
6. Rust host 初始化 `codex-home`、provider 配置、环境变量
7. Rust host 启动 `codex-rs app-server`
8. app-server 监听 `ws://127.0.0.1:7456`
9. `Index.ets` 通过 `CodexBackend.ets` 发起 WebSocket 连接
10. 前端完成 `initialize / initialized` 握手
11. 后续 turn、diff、plan、approval 全部走 WebSocket JSON-RPC

可以看到：

- native 层只负责“把后端进程在应用内拉起来”
- 真正的对话协议，走的是 WebSocket，不是 NAPI

## 6. 对话与审批流程

发送一轮请求时：

1. `Index.ets` 收集 prompt、cwd、model、effort
2. `CodexBackend.startTurn(...)` 确保连接可用
3. 如有必要，先调用 `thread/start`
4. 再调用 `turn/start`
5. 后端开始流式回推消息
6. `CodexBackend` 合并消息 delta，更新消息区
7. `turn/plan/updated` 更新 summary / plan
8. `turn/diff/updated` 更新右侧 diff
9. `turn/completed` 结束当前 turn

审批流程类似：

1. 后端发来审批请求
2. `CodexBackend` 构造成 `CodexApprovalRequest`
3. `Index.ets` 渲染“允许 / 拒绝”卡片
4. 用户点击后，前端通过 JSON-RPC 回传审批结果

## 7. 编译与打包流程

当前已经拆成两个阶段。

### 7.1 阶段一：构建 `libcodexhost.so`

命令：

```bat
libcodexhost-builder\build.bat debug x86_64
```

这一步内部做的事情：

1. 定位 `codex-main/codex-rs`
2. 定位 DevEco SDK
3. 定位 `cargo`
4. 调用 CMake 配置 OHOS 工具链
5. 调用 `build_codex_ohos_host.cmd`
6. `cargo build --package codex-ohos-host --target x86_64-unknown-linux-ohos`
7. 生成 Rust 静态库 `libcodex_ohos_host.a`
8. 再由 CMake 把它和 `napi_init.cpp` 链接成 `libcodexhost.so`
9. 安装到：

```text
Agent\entry\src\main\libs\x86_64\libcodexhost.so
```

如果已经有现成的 Rust 静态库，也可以只做最终链接：

```bat
set PREBUILT_RUST_STATIC_LIB=C:\path\to\libcodex_ohos_host.a
libcodexhost-builder\build.bat debug x86_64
```

### 7.2 阶段二：构建 HAP

命令：

```bat
Agent\script\helpsetup\build.bat debug
```

这一步内部做的事情：

1. 运行 `setup_env.bat`
2. 自动定位 `Agent` 工程根目录
3. 自动定位 DevEco SDK
4. 生成 `Agent/local.properties`
5. 如缺失则执行 `ohpm install --all`
6. 确保 Rust OHOS targets 已安装
7. 清理 hvigor 用户缓存和 daemon
8. 检查 `Agent/entry/src/main/libs/x86_64/libcodexhost.so` 是否存在
9. 执行 `hvigor assembleHap`

这里有一个关键点：

- `Agent/entry/build-profile.json5` 已经去掉 `externalNativeOptions`
- 所以 `hvigor assembleHap` 不会再去编 Rust / CMake
- 它只构建 ArkTS 应用本体

### 7.3 阶段三：把 native 库重新注入 HAP

虽然主项目不再内联编译 native，但最终 HAP 仍然必须带上动态库。

这一步由：

- `Agent/hvigorfile.ts`
- `Agent/script/helpsetup/repack_hap_with_native.js`

共同完成。

流程是：

1. hvigor 完成 HAP 基础打包
2. `repack_hap_with_native.js` 读取 `local.properties`
3. 找到最终 `entry-default-unsigned.hap`
4. 找到：
   - `libcodexhost.so`
   - `libc++_shared.so`
5. 调用 `app_packing_tool.jar`
6. 把这两个 `.so` 注入 HAP

为什么必须额外带上 `libc++_shared.so`：

- `libcodexhost.so` 依赖 C++ 共享运行时
- 如果 HAP 里只有 `libcodexhost.so`，运行时会出现
  `Error loading shared library libc++_shared.so`

## 8. 当前产物与路径

关键产物：

- native 构建输出：

```text
libcodexhost-builder\out\cmake\<abi>\<mode>\staging\<abi>\libcodexhost.so
```

- 安装到主项目后的 native 库：

```text
Agent\entry\src\main\libs\x86_64\libcodexhost.so
```

- 最终 unsigned HAP：

```text
Agent\entry\build\default\outputs\default\entry-default-unsigned.hap
```

HAP 内最终应至少包含：

```text
libs/x86_64/libcodexhost.so
libs/x86_64/libc++_shared.so
```

## 9. 修改代码时该动哪一层

### 9.1 只改 UI

改这些：

- `Index.ets`
- 其他 ArkTS 页面 / 组件

通常不需要重编 `libcodexhost.so`。

### 9.2 改 WebSocket 协议适配

改这些：

- `CodexBackend.ets`

这影响的是：

- 前端如何理解 `app-server` 事件
- message / diff / plan / approval 的合并逻辑

通常也不需要重编 native。

### 9.3 改 native 对 ArkTS 暴露的接口

改这些：

- `libcodexhost-builder/native/bridge/napi_init.cpp`
- `Agent/entry/src/main/types/libcodexhost/index.d.ts`
- `Agent/entry/src/main/ets/backend/CodexHostNative.ets`

这时需要重新构建 `libcodexhost.so`。

### 9.4 改 embedded host 或 provider 行为

改这些：

- `codex-main/codex-rs/ohos-host/src/lib.rs`

这时也需要重新构建 `libcodexhost.so`。

### 9.5 改真实后端逻辑

改这些：

- `codex-main/codex-rs/app-server`
- `codex-main/codex-rs/core`
- `codex-main/codex-rs/protocol`
- 以及相关依赖 crate

这同样需要重新构建 `libcodexhost.so`，因为 Rust staticlib 会变化。

## 10. 当前精简策略

当前已经对 `codex-main` 做了保守精简：

- 已删除外围文档、SDK、CLI 包装、CI、脚本等顶层内容
- 仅保留 `codex-main/codex-rs`

为什么没有继续把 `codex-rs` 再砍成只剩 `ohos-host`：

- `ohos-host` 并不是一个孤立 crate
- 它依赖 `app-server`、`core`、`protocol` 等大量 workspace crate
- 再往里精简，会变成一次真正的 Rust workspace 拆分工程，而不是简单清理

因此当前建议是：

- 可以把 `codex-main` 理解成“只剩 `codex-rs` 的上游源”
- 不要再对 `codex-rs` 内部目录做无分析删除

## 11. 常见故障点

### 11.1 `install sign info inconsistent`

原因：

- 模拟器里已安装同包名但不同签名的旧应用

处理：

- 卸载旧包后重装

### 11.2 `Cannot read property getStatus of undefined`

原因：

- `libcodexhost.so` 未正确打入 HAP，或 native 模块加载失败

当前状态：

- `CodexHostNative.ets` 已做防御，不应再直接把应用打崩

### 11.3 `Error loading shared library libc++_shared.so`

原因：

- HAP 里缺 `libc++_shared.so`

当前状态：

- `repack_hap_with_native.js` 已把它纳入打包

### 11.4 前端提示 WebSocket 错误

这通常不是前端本身有 bug，而是：

- embedded host 没有成功启动
- 或没有监听到 `ws://127.0.0.1:7456`

优先查看日志：

- `CodexHost`
- `Embedded host start result: code=... running=... url=... message=...`

## 12. 推荐日常工作流

如果你改的是 Rust / native：

```bat
libcodexhost-builder\build.bat debug x86_64
Agent\script\helpsetup\build.bat debug
```

如果你只改 ArkTS 前端：

```bat
Agent\script\helpsetup\build.bat debug
```

如果你要排查 provider：

1. 在 UI 里保存 provider 配置
2. 完全重启应用
3. 看 `CodexHost` 日志确认 embedded host 是否正常启动
4. 再看请求是否真正打到目标 `base_url`

---

如果后续还要继续精简，下一层不是删文件，而是单独为 `codex-ohos-host`
整理一份更小的 Rust workspace。那会是一次真正的源码重构，不再是简单清理。
