# OpenHarmony Codex 工作区交接上下文

## 1. 当前目标

这个工作区的目标是把上游 `codex-main` 中的真实 Rust Codex 后端能力接入到鸿蒙窗口应用 `Agent` 中，并让前端通过应用内嵌的 `codex-rs app-server` 工作，而不是依赖 mock 逻辑或外部手动启动的后端进程。

当前状态不是“还没开始”，也不是“完全做完”。更准确地说：

- 内嵌 Rust `app-server` 已经接入并能启动
- ArkTS 前端已经能通过 WebSocket JSON-RPC 连上它
- 前端消息流、diff、计划、审批等主链路已经接通
- 当前正在继续打磨 provider 配置和第三方 OpenAI-compatible 服务兼容性

## 2. 工作区结构

工作区根目录：

- `C:\Users\asus\Desktop\OpenHarmony`

关键目录：

- `C:\Users\asus\Desktop\OpenHarmony\Agent`
  - 鸿蒙窗口应用工程
- `C:\Users\asus\Desktop\OpenHarmony\codex-main`
  - 上游 Codex 源码树

## 3. codex-main 是什么

`codex-main` 是 Codex CLI 的源码。

重要划分：

- `codex-cli`
  - npm / Node 启动壳和分发包装层
  - 不是主要业务逻辑
- `codex-rs`
  - 当前真正维护的 Rust 主实现
  - 包含 `core`、`state`、`rollout`、`app-server`、`app-server-client`、`exec`、`tui`、`cli`

关键架构文档：

- `C:\Users\asus\Desktop\OpenHarmony\codex-main\docs\architecture_zh.md`

与鸿蒙移植最相关的结论：

- `app-server` 是协议收敛层
- `tui` 和 `exec` 都围绕同一套 app-server 语义工作
- 核心运行时在 `codex-rs/core`
- 对鸿蒙移植来说，优先目标应是 `app-server`，不是 TUI

## 4. 关键 Rust 路径

这些是当前和后续工作最相关的目录：

- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server-client`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\state`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\rollout`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\ohos-host`

关键文件：

- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\ohos-host\src\lib.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server\src\lib.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server\src\transport\websocket.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core\src\thread_manager.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core\src\codex_thread.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core\src\codex.rs`

## 5. 当前鸿蒙应用状态

应用工程在：

- `C:\Users\asus\Desktop\OpenHarmony\Agent`

核心前端文件：

- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\pages\Index.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\backend\CodexBackend.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\backend\CodexHostNative.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\entryability\EntryAbility.ets`

UI 目前是三栏 Codex 风格窗口布局：

- 左侧：连接、provider 配置、会话、工作目录
- 中间：消息流、状态摘要、输入区
- 右侧：统一 diff

## 6. 已完成的后端接入

已经新增并接通：

- `codex-rs/ohos-host`
  - 作为鸿蒙内嵌 Rust host
- `libcodexhost.so`
  - N-API / C++ / Rust 桥接层
- `CodexBackend.ets`
  - ArkTS 端 app-server 协议客户端

当前应用启动链路：

1. `EntryAbility.onCreate()` 启动内嵌 host
2. ArkTS 调用 `libcodexhost.so`
3. Rust `codex-ohos-host` 启动 Tokio runtime
4. Rust host 启动上游 `codex-rs app-server`
5. 本地监听 `ws://127.0.0.1:7456`
6. 前端自动连接这个地址

## 7. 已接入的 app-server 协议能力

当前前端已接入这些协议：

- `initialize / initialized`
- `thread/start`
- `turn/start`
- `item/started`
- `item/completed`
- `item/agentMessage/delta`
- `turn/diff/updated`
- `turn/plan/updated`
- `turn/completed`
- 命令审批
- 文件修改审批
- 权限审批

这意味着当前应用已经不是 mock 演示，而是真实跑在 `codex-rs app-server` 上。

## 8. 之前修过的关键问题

已经处理过这些问题：

- 应用内自启动 `codex-rs app-server`
- WebSocket `Origin` 头被上游拒绝的问题
- 模拟器 `x86_64` 与 `arm64-v8a` ABI 不匹配问题
- 包名大小写不一致导致安装后无法启动的问题
- `zstd` / `qsort_r` 导致的 OHOS 链接失败问题
- provider 保存后前端字段被清空的问题

其中 provider 字段问题的根因是：

- Rust 侧 JSON 用的是 `camelCase`
- 前端一开始按 `snake_case` 读取
- 现在前端已经兼容 `baseUrl/apiKey` 和 `base_url/api_key`

## 9. 当前模型配置模式

当前前端已从“登录 GPT 账号 / API Key 登录按钮”改成“手动 provider 配置”模式。

现在 UI 支持填写：

- `base_url`
- `api_key`
- `model`

保存逻辑：

- ArkTS 调用 `saveProviderConfig`
- Rust host 将配置写入：
  - `CODEX_HOME/harmony-provider.json`
  - `CODEX_HOME/config.toml`

生成的 provider 当前是：

- provider id：`harmony-openai-compatible`
- `wire_api = "responses"`
- `requires_openai_auth = false`
- `supports_websockets = false`

重要限制：

- 当前配置不是热更新
- 修改 provider 后，必须完全重启应用，内嵌 app-server 才会重新加载新配置

## 10. 当前遗留问题

当前最重要的未闭环点是第三方 provider 兼容性。

例如 OpenRouter 场景：

- 前端已经能保存 `base_url + api_key + model`
- 但还需要继续验证重启后请求是否真正打到 `openrouter.ai`
- 如果确实还走 `api.openai.com`，需要继续排查 app-server 加载配置的链路
- 如果请求已经打到 OpenRouter，但协议不兼容，则需要调整：
  - `wire_api`
  - 请求头
  - OpenAI-compatible 兼容层细节

## 11. 最近改动过的文件

最近一轮相关修改集中在：

- `C:\Users\asus\Desktop\OpenHarmony\libcodexhost-builder\native\bridge\napi_init.cpp`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\types\libcodexhost\index.d.ts`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\backend\CodexHostNative.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\backend\CodexBackend.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\pages\Index.ets`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\ohos-host\src\lib.rs`

注意：

- 当前 Git 工作区是脏的
- 上面这些文件已有未提交改动
- 后续 AI 接手时不要误以为这些变更已经提交

## 12. 构建状态

最近已验证：

- `assembleHap` 构建成功

命令：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry@default -p product=default -p requiredDeviceType=2in1 assembleHap
```

当前产物：

- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\build\default\outputs\default\entry-default-signed.hap`

## 13. 下一步建议

如果由另一个 AI 或开发者继续推进，建议按这个顺序：

1. 在模拟器里重新安装最新 HAP
2. 验证 `Provider` 面板保存后是否能正确回显 `base_url/api_key/model`
3. 完全退出应用再重启
4. 验证请求是否已经切换到目标 `base_url`
5. 如果第三方服务仍不兼容，继续调整 provider 生成逻辑
6. 清理前端残留的旧认证路径和无用状态
7. 做真机 smoke test

## 14. 可直接给其他 AI 的提示词

可以把下面这段直接贴给其他 AI：

```text
Workspace root: C:\Users\asus\Desktop\OpenHarmony

There are two projects:
1. Agent = HarmonyOS window application
2. codex-main = upstream Codex source

Current objective:
Finish stabilizing the embedded Rust codex-rs app-server integration for HarmonyOS and make manual provider configuration work reliably with OpenAI-compatible services.

Important current status:
- The app already embeds and starts a real Rust codex-rs app-server.
- The ArkTS frontend already connects to it over ws://127.0.0.1:7456.
- The frontend supports thread/start, turn/start, streaming messages, diff, plan updates, and approvals.
- The UI has been changed from GPT login flow to manual provider config: base_url + api_key + model.
- Provider changes currently require a full app restart to take effect.
- Recent work fixed a bug where saved provider fields were cleared because Rust returned camelCase JSON while ArkTS expected snake_case.

Relevant files:
- Agent\entry\src\main\ets\pages\Index.ets
- Agent\entry\src\main\ets\backend\CodexBackend.ets
- Agent\entry\src\main\ets\backend\CodexHostNative.ets
- libcodexhost-builder\native\bridge\napi_init.cpp
- Agent\entry\src\main\types\libcodexhost\index.d.ts
- codex-main\codex-rs\ohos-host\src\lib.rs

Current open issue:
- Need to verify whether saved provider config is actually applied after restart.
- If requests still go to api.openai.com instead of the configured base_url, continue tracing config loading in the embedded app-server path.
- If requests hit the target base_url but fail, investigate wire_api and OpenAI-compatible provider behavior.

Build command:
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry@default -p product=default -p requiredDeviceType=2in1 assembleHap
```
