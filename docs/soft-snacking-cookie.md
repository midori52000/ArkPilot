# Status

- 当前状态：计划已持久化为文档。
- 执行状态：仅规划，不改代码。
- 范围：围绕 ArkPilot 的四层 context management 接入方案。

# Context

这次要落到 ArkPilot 的，不是泛泛的“压缩一下上下文”，而是一套**四层防御系统**：

1. **微压缩**：纯规则、本地删减部分字段、零模型成本。
2. **结构化记忆**：不是简单摘要历史，而是把已沉淀的对话提炼成结构化事实，同时保留最近一段完整原始上下文。
3. **完整压缩**：当上面两层都不够时，调用模型做高质量压缩，并在压缩后做关键上下文重建。
4. **自动触发与熔断**：统一判断什么时候触发哪一层，并防止失败重试导致死循环。

ArkPilot 已经具备接入这套逻辑的基础：
- ArkTS 侧已有 `TurnTokenUsage`、`contextRemainingPercent`、`CodexBackendSnapshot`、fallback compaction UI。
- Rust host 侧已有 `runtime/thread-context.json`、`runtime/token-usage.json`、`thread/read` 与 `turn/poll` payload。
- Codex core/state 侧已有 `context_manager/history.rs`、`compact.rs`、`codex.rs`、`memories/*`、`memory_mode polluted` 等成熟实现。

目标是在 **最小化改动** 前提下，把这四层完整接入 ArkPilot，并保持 **Rust core/host 为事实来源，ArkTS 负责展示、宿主策略与兜底**。

## 现状与新增能力边界

在开始实现前，需要明确“现状”和“目标”并不等价：

1. **当前已存在的能力**
   - `core/src/context_manager/history.rs` 已有历史写入时的截断/规范化能力，但它当前主要覆盖 `FunctionCallOutput` / `CustomToolCallOutput` 一类，不等于完整的 Layer 1 微压缩系统。
   - `core/src/codex.rs` 已有 pre-turn / model-switch / mid-turn 的完整压缩触发入口，但它们本质上仍是 Layer 3/Layer 4 的主链，而不是新的四层统一调度器。
   - `core/src/memories/*` 与 `state/src/runtime/memories.rs` 已有结构化记忆、polluted、forgetting 的后端能力，但 Host/UI 目前还没有把这些状态完整透出。
   - ArkTS 侧 `CompactionPolicy.ets` 现在只是宿主 fallback 策略，不是完整的自动压缩调度器。

2. **首版必须新增的能力**
   - Layer 1 的规则骨架、历史项元信息、pin 区和 replay key 约束
   - Layer 2 的 runtime 尾部保留策略与 Host/UI memory 状态透出
   - Layer 3 的战后重建观测与恢复契约
   - Layer 4 的显式熔断、排除名单、观测指标和宿主/核心边界说明

3. **条件性保证**
   - “删而可追溯”不是无条件成立；只有在 `persistExtendedHistory: true` 或等价持久化前提满足时，才承诺可回放到更完整的原始记录。
   - 若未满足该前提，首版只保证保留足够的 replay key / locator，不保证从 `thread/read` 得到非 lossy 原文。

# Recommended approach

## 总原则

1. **微压缩先做本地规则删减**：按你的定义，首版微压缩只做本地字段删减/占位替换，不依赖服务端 cache-micro API。
2. **结构化记忆不做“聊天摘要”**：只提炼长期有价值的事实，近期原始上下文保留完整尾部。
3. **完整压缩继续复用 Codex core**：不在 ArkTS 侧重写完整压缩 prompt 或摘要逻辑。
4. **自动触发必须有熔断**：任何自动压缩链都要有失败上限和排除名单，避免无限重试。
5. **主线程与后台任务隔离**：微压缩、自动触发只针对主聊天线程；memory/compact 子任务不能再触发自身压缩链。
6. **源头治理优先复用现有持久化**：大块工具结果优先保存在已有 rollout/session 持久化中，prompt 内只保留短摘要和可追溯指针，不急着新建一套 blob 系统。

## 首版范围、非目标与 Milestone 总览

### 首版范围

1. **Layer 1 首批覆盖面**：优先覆盖 `FunctionCallOutput` / `CustomToolCallOutput`，确保历史项元信息、call/result 边界、pin 区与 replay key 约束成立。
2. **Layer 1 第二批扩展面**：在首批稳定后，再扩到 `LocalShellCall`、`ToolSearchOutput`、web、MCP 大 JSON、diff/write 结果。
3. **Layer 2 首版目标**：打通结构化记忆、runtime 尾部保留、polluted/forgetting 语义与 Host/UI 可见性，不做记忆编辑器。
4. **Layer 3/4 首版目标**：复用现有 compact 主链，补齐战后重建契约、显式熔断、观测指标与宿主兜底边界。

### 首版非目标

- 不新建独立 blob 存储系统
- 不在 ArkTS 侧重写 compact prompt 或 memory 提炼器
- 不做独立 context 设置中心、memory 编辑器、复杂人工修复 UI
- 不承诺在未开启扩展持久化的前提下提供完整原文回放

### Milestone 总览表

| Milestone | 目标 | 入口条件 | 核心产出 | 阻塞项 | Done 定义 |
| --- | --- | --- | --- | --- | --- |
| M1 | 历史项元信息与 Layer 1 骨架 | 已确认 Layer 1 规则矩阵与 pin/replay 约束 | history 层微压缩骨架、边界锁、首批测试 | `call_id` 配对与 metadata 设计 | `record_items()/process_item()` 能稳定压缩首批结果类型，且不破坏 normalize |
| M2 | Host/UI 契约打底 | M1 能输出稳定的 Layer 1 结果 | snapshot/payload 字段、事件流/兜底流契约、基础 UI 状态 | Host payload 兼容性 | 新字段可缺省兼容，event/poll/reconcile 三路最终状态一致 |
| M3 | Layer 2 接入 | M1/M2 已提供 replay key 与基础状态流 | phase1/phase2 选择、tail 保留策略、polluted/forgetting 契约 | memory 状态透出 | memory 文件、forgetting、polluted 状态可验证且 Host/UI 可见 |
| M4 | Layer 3/4 联调 | M1-M3 稳定 | 手动/pre-turn/mid-turn/model-switch 完整压缩、熔断、排除名单、观测指标 | compact 契约与恢复语义 | 三类 trigger 跑通，同 turn 不套娃，失败 3 次后熔断 |
| M5 | UI/E2E 验收 | M1-M4 稳定 | notice/toast/card 展示、workspace/session 恢复、端到端回归 | 模拟器/Provider 场景 | 长会话、重启恢复、polluted、熔断恢复全部可复现并可解释 |

### 默认配置基线表（首版建议）

| 配置项 | 首版建议值 | 说明 |
| --- | --- | --- |
| `recent_messages_min` | 5 | Layer 2 尾部保留的最少消息数 |
| `recent_tokens_min` | 10_000 | 尾部保留的最小 token 预算 |
| `recent_tokens_max` | 40_000 | 尾部保留的最大 token 预算 |
| `recent_artifact_refs_max` | 5 | Layer 3 战后重建回灌的关键引用上限 |
| `auto_compact_limit` | `min(config_limit, 0.9 * context_window)` | Layer 4 主阈值 |
| `auto_compact_failure_trip` | 3 | 连续失败超过 3 次熔断 |
| `same_turn_auto_limit` | `1 pre_turn + 1 mid_turn` | 同一 turn 的自动压缩上限 |
| `pin_window` | 当前 turn + 最近一次关键工作集 | Layer 1/Layer 2 默认 pin 区 |
| `recent_full_results_per_tool` | 1 | 每类工具至少保留最近 1 条完整结果 |

### 接口 / 状态变更清单

| 层级 | 必需变更 | 说明 |
| --- | --- | --- |
| core/history | 历史项元信息、Layer 1 骨架、pin/replay 约束 | 为微压缩与后续 compact 提供统一口径 |
| state/memories | polluted/forgetting/no-output 契约、phase2 选择可观测 | 为 Layer 2/4 提供稳定状态 |
| host | `ThreadContextSnapshot`、turn/poll payload、compaction/memory 字段透出 | 作为 Rust 与 ArkTS 的事实来源桥梁 |
| ArkTS backend | `ConsoleModels` / `CodexBackend` / `CodexNative` 承载新字段 | 负责消费而不是推断算法结果 |
| UI | token/context/compaction/memory/workspace 状态展示 | 负责解释状态与提供手动重试 |

## Phase 1 — 历史项标准化与 Layer 1 微压缩

### 目标
先把“哪些数据能删、哪些边界不能动、删完之后如何还能追溯”定清楚，再把微压缩接到现有主线程链路里。

### 关键文件
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\context_manager\history.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\compact.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\ohos-host\src\lib.rs`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\ConsoleModels.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CodexBackend.ets`

### 复用点
- `record_items(...)`
- `get_total_token_usage(...)`
- `get_total_token_usage_breakdown(...)`
- `ThreadContextSnapshot`
- `build_thread_read_payload(...)`
- `build_turn_poll_payload(...)`
- `applyTokenUsagePayload(...)`
- `CodexThreadRecord`

### 实施内容
1. 先为“历史项”补最小元信息，供后续规则裁剪使用：
   - `item_kind`：`user | assistant | tool_use | tool_result | diff | summary | system`
   - `source_kind`：`main | memory_job | compact_job | other`
   - `group_id` / `message_id`：用于绑定同一结构边界
   - `tool_call_id` / `tool_name`
   - `is_compactable`
2. **微压缩定义为本地字段删减**，只作用在 `source_kind = main` 的历史项上。
   - **首批覆盖**：`FunctionCallOutput` / `CustomToolCallOutput`
   - **第二批扩展**：`LocalShellCall`、`ToolSearchOutput`、web、MCP 大 JSON、diff/write 结果
   - 在首批覆盖稳定前，不把第二批工具类型写成默认已支持能力
3. 微压缩只在命中“旧的、可再取的、低信息密度数据”时触发；当前 turn、pin 区和最近关键工作集不压。
4. 对首批覆盖对象执行本地字段删减：
   - 优先对象：`read file`、搜索结果、网页正文、MCP 大结果、日志/stdout/stderr、大 diff。
   - 对这些项删除或缩短低价值大字段：如 `raw_text`、`full_body`、`stdout`、`stderr`、`file_content`、`search_hits`、大 JSON 正文。
   - 保留高价值字段：`tool_call_id`、路径/URL、命中位置、结果状态、短摘要、时间戳、可回溯指针。
5. 被删减的大块内容**不直接消失**：
   - 首版直接把“完整原文的事实来源”指回已有 rollout/session 持久化（`thread_id + turn_id + tool_call_id` 或等价定位键）。
   - 这是一种**条件性保证**：若未启用扩展持久化，则只保证 locator/replay key 仍可见，不保证 `thread/read` 返回非 lossy 原文。
   - prompt 内只留下简短占位符，如“此处已微压缩，完整结果见 thread/turn/tool 指针”。
6. 微压缩规则采用白名单：
   - 首版只压缩工具结果类，不动 user/assistant 正常对话文本。
   - 每类工具只保留最近 N 条完整结果，更早结果改占位。
5. **结构边界锁**必须先落地：
   - `tool_use` 与对应 `tool_result` 必须成对保留或成对压缩。
   - 同一 `message_id` 下的流式碎片必须整体处理，不能只切掉半截 thinking/半截 tool block。
6. Host 快照中新增轻量字段：
   - `last_micro_compaction_at`
   - `last_micro_compaction_item_count`
   - `last_micro_compaction_saved_tokens`
   - `memory_mode`
   - `recent_artifact_refs`（最多 5 个，用于第三层重建）

### Layer 1 保留 / 剪去规则表

#### 总规则

1. **永远保留结构键**：`call_id`、`tool_name`、必要定位键、tool call / tool result 配对关系、顺序关系。
2. **永远不动正常对话**：Layer 1 只处理工具结果类大字段，不压 `user` / `assistant` 正常文本。
3. **只压旧的、可再取的、低信息密度数据**：当前 turn 与最近一次关键工作集默认不压。
4. **只做规则删减，不做语义摘要**：Layer 1 只删大字段、留骨架和回溯键，不承担结论提炼。

#### 当前工作集保护区

以下内容默认进入 pin 区，不参与 Layer 1 微压缩：
- 当前 turn 产生的工具结果
- 最近一次失败测试的关键输出
- 当前正在编辑文件的最近一次 `read file` 结果
- 最近一次刚被用来定位跳转的搜索结果
- 最近一次还会继续被 follow-up 使用的 MCP 结果

#### 按工具类型的规则矩阵

| 工具/结果类型 | must_keep | can_drop | pin_condition | placeholder_shape | test_assertions |
| --- | --- | --- | --- | --- | --- |
| `read file` / 文件读取 | `call_id`、`tool_name`、`path`、`line range`、文件指纹（`mtime` 或 hash）、`thread_id + turn_id + call_id` 回溯键 | 文件正文全文、大段连续代码、重复空行、大块注释/许可证正文 | 当前编辑文件；当前 turn 刚读过；assistant 下一步还要基于这段代码继续修改 | `已读取 <path:range>，正文已微压缩，完整内容见 replay key` | `raw_items()` 中正文被替换；`for_prompt(...)` 仍保留 `path/range`；文件指纹仍在；token 显著下降 |
| grep / search / ripgrep 结果 | `call_id`、`tool_name`、`query/pattern`、搜索根路径、命中总数、前几个命中的 `path + line`、短摘录、回溯键 | 大量上下文行、同文件重复命中、CLI 表头/颜色控制符、全量正文片段 | 最近一次刚用于定位跳转；后续 turn 仍在围绕同一 query 展开 | `已搜索 <pattern>，保留前 N 个命中，完整结果见 replay key` | 命中路径和行号仍在；正文长片段消失；命中总数仍在；token 下降 |
| shell / test / command output | `call_id`、`tool_name`、`command`、`cwd`、`exit_code`、时长（若有）、失败摘要、失败测试名/错误类型、首个关键栈帧或最后几行错误尾巴、回溯键 | 通过用例的大量成功日志、重复 warning、超长 `stdout/stderr`、构建流水噪音 | 当前失败正在修；最近一次测试结果正被 assistant 用来决定下一步 | `已执行 <command> (exit=<code>)，长日志已微压缩，关键错误已保留` | `exit_code` 和错误摘要保留；大段日志消失；失败尾部仍可见；token 下降 |
| MCP / 大 JSON / API 返回 | `call_id`、`tool_name`、顶层状态、主键/id/name、对象数量/数组长度、前几个对象的关键字段、回溯键 | 大数组正文、深层嵌套对象、重复字段、base64/blob、长 JSON 正文 | 最近一次结果还要继续 drill down；结果是后续写操作的输入 | `已获取 <tool_name> 结果，保留关键字段与对象计数，完整 JSON 见 replay key` | 顶层状态和计数保留；正文大块删除；关键 id/name 仍在；token 下降 |
| web / 网页正文 | `call_id`、`tool_name`、`url`、`title/domain`、fetch 状态、极短 snippet、时间戳、回溯键 | 网页正文全文、导航、页脚、广告、HTML 杂项 | 当前 turn 正在围绕该网页内容继续追问 | `已抓取 <url>，正文已微压缩，保留标题与摘要，完整内容见 replay key` | `url/title` 仍在；正文被裁剪；snippet 存在；token 下降 |
| diff / edit / write 结果 | `call_id`、`tool_name`、变更文件列表、成功/失败、`+/-` 行数、hunk/file 数、回溯键 | 完整 patch、完整新文件内容、大段 replacement 文本 | 当前 turn 刚改完、马上还要 review patch；最近一次 diff 正被 user/assistant 讨论 | `已修改 <files>，保留变更统计，完整 patch 见文件系统或 replay key` | 变更文件与统计保留；patch body 消失；token 下降 |

#### 最小字段白名单

Layer 1 无论压哪类结果，以下字段默认必须保留：
- `call_id`
- `tool_name`
- `exit_code` 或 success flag
- `path` / `url` / `query` / `command` 这类 locator
- `line range` / hit 行号
- `thread_id + turn_id + call_id` 形式的 replay key
- 文件指纹（至少对 `read file` 类）
- 对象数量 / 命中数量 / 变更数量这类计数
- 一句 deterministic placeholder

#### 优先剪除字段

Layer 1 首批优先删减的大字段：
- `stdout`
- `stderr`
- `file_content`
- `raw_text`
- `full_body`
- 长 `search_hits` 上下文
- 大 JSON 数组正文
- patch body
- base64 / 二进制正文

#### Layer 1 验证时必须对应的断言

1. **算法层**：`raw_items()` 已是压缩后形态，`for_prompt(...)` 看不到大字段，`call_id`/locator 仍在，token 明显下降。
2. **边界层**：不会产生 orphan output，不会触发 synthetic aborted output，call/output 顺序不乱，`LocalShellCall` 特例不坏。
3. **追溯层**：开启 `persistExtendedHistory: true` 时可通过 replay key 找回原始记录；未开启时至少保留足够定位键。
4. **保护区**：被 pin 的最近工作集不会被 Layer 1 提前压掉。

## Phase 2 — Layer 2 结构化记忆 + 近期原始尾部保留

### 目标
把“最近上下文”和“长期事实”拆开：最近部分保留原始细节，长期部分抽成结构化记忆，不再简单摘要整段聊天。

### 关键文件
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\memories\phase1.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\memories\phase2.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\memories\storage.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\runtime\memories.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\runtime\threads.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\extract.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\model\thread_metadata.rs`

### 复用点
- `Stage1Output`
- `claim_stage1_jobs_for_startup(...)`
- `record_stage1_output_usage(...)`
- `mark_thread_memory_mode_polluted(...)`
- `apply_rollout_item(...)` / `apply_rollout_items(...)`
- `rebuild_raw_memories_file_from_memories(...)`
- `sync_rollout_summaries_from_memories(...)`

### 实施内容
1. 继续复用 phase1/phase2 memory 管线，不在 ArkTS 实现新提炼器；ArkPilot 只消费 state/core 的结果。
2. 把 memory 的语义对齐为“结构化事实提炼”，输出重点放在：
   - 项目栈/模块事实
   - 当前任务进度/约束
   - 用户偏好/协作方式
   - 已确认的重要决定
3. 明确 Phase 1 选取条件：仅处理 `memory_mode = enabled`、非当前线程、满足 age/idle 窗口、且 DB watermark 落后的线程；不要把它写成“对所有历史线程统一摘要”。
4. 明确 Stage 1 输入窗口策略：复用 `build_stage_one_input_message()`，把 rollout 文本截到模型有效窗口的大约 70%；底层走 middle truncation，要求**同时保留头尾证据**，而不是简单 latest-only tail ring。
5. 明确 Phase 2 选择规则：memory 合并输入按 `usage_count DESC, COALESCE(last_usage, source_updated_at) DESC` 排序；写回文件时同步 `selected ∪ previous_selected`，这样 forgetting 可以删除上轮已选、但本轮被踢出的条目。
6. **近期上下文尾部保留** 仍单独实现，不和 memory 文件混在一起：
   - 默认策略：至少保留最近 5 条消息、至少保留 10k token、最多不超过 40k token
   - 截取方式：从最新消息向前回溯，直到满足双下限或触顶上限
   - 尾部窗口不是 latest-message ring 的持久化结构，而是 runtime 拼 prompt 时的保留策略
7. 尾部截取时沿用 `Phase 1` 的结构边界锁：
   - 命中 `tool_result` 就强制连带前一个 `tool_use`
   - 命中流式碎片就整组保留同一 `message_id`
   - 当前 turn、当前工作集 pin 区、最近一次失败测试输出默认不进入尾部裁剪候选
8. polluted 机制继续由 core/state 决定，并把 forgetting 语义写清：
   - WebSearch/MCP 命中后，线程进入 `polluted`
   - 如果该线程曾在上轮 baseline 中被选中，则立即 enqueue 一次 phase2 forgetting
   - ArkPilot 只展示，不自行判断污染
9. no-output 语义单列写清：
   - 若线程之前有旧 `stage1_output`，本轮无输出则删除旧记录并把 phase2 置脏
   - 若线程本来就没有 `stage1_output`，本轮无输出不应无意义地触发 phase2
10. Host/UI 首版只透出以下 memory 相关状态：
   - `memory_mode`: `enabled | disabled | polluted`
   - 最近 memory 摘要是否可用 / 更新时间 / 简短预览
   - 是否发生 forgetting / 最近一次 forgetting 影响的线程数（如后端可得）
11. 文档里显式注明一个实现注意点：README 里“never-used 回退到 generated_at”的描述应以代码真实行为为准；当前实现更接近回退到 `source_updated_at`，后续若代码与文档不一致，应以实现为事实来源。
## Phase 3 — Layer 3 完整压缩与战后重建

### 目标
当微压缩和结构化记忆都不够用时，复用 Codex core 的完整压缩链，并补上压缩后的关键上下文重建。

### 关键文件
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\compact.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\codex.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\ohos-host\src\lib.rs`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CodexBackend.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\pages\Index.ets`

### 复用点
- `pre_compress_tool_outputs(...)`
- `run_compact_task_inner(...)`
- `collect_user_messages(...)`
- `run_inline_auto_compact_task(...)`
- `run_auto_compact(...)`
- `compactThread(...)`
- `CompactionRunState`

### 实施内容
1. 完整压缩仍复用 `compact.rs` 现有 prompt 结构：
   - 允许模型先在 `analysis` 区域充分推理
   - 最终只把 `summary` 结果注入后续上下文
   - `analysis` 不进入最终历史
2. 明确完整压缩入口分三类：
   - 手动 `thread/compact/start` / `Op::Compact`
   - 回合前自动压缩（pre-turn / pre-sampling）
   - 回合中超窗后的 follow-up 压缩（mid-turn continuation）
3. 本地完整压缩阶段写清：
   - 先记录 `ContextCompaction` item
   - 先对工具输出做预截断（当前 core 里已有 500 token 级别的预瘦身）
   - 若 compact 请求本身仍超窗，则按**最老 history 分组**逐步删除并有限次重试
   - 成功后生成 `replacement_history`，同时保留必要 user message 与 summary
4. 远端完整压缩阶段写清：
   - 先裁掉末尾 codex-generated 项以塞进 context window
   - 调用 remote compact 能力
   - 过滤返回，只保留真实 user / hook prompt / assistant / compaction，避免把旧 developer 或大工具痕迹重新注回模型历史
5. 完整压缩成功后，必须执行**战后重建**：
   - 清理失效缓存/失效临时上下文
   - 清空或重置 `reference_context_item`，保证下个正常 turn 走一次全量 reinject
   - 回灌最近关键文件引用（来自 `recent_artifact_refs`，最多 5 个）
   - 回灌当前 workspace / plan / active skills / MCP 说明 / provider 关键配置
   - 保留最近一段原始尾部上下文，避免“压完立刻失忆”
   - 若发生模型切换，允许插入 `<model_switch>` 类 developer/context 提示，保持新窗口下的对齐语义
6. 恢复语义写清：
   - 新 rollout 优先依赖 `replacement_history` 重建
   - 遇到旧 rollout 没有 `replacement_history` 时，允许退化为“摘要 + 下次全量 reinject”
   - mid-turn compact 需要把新的 `TurnContext` 持久化为后续 baseline
7. `CompactionRunState` 建议扩展为：
   - `kind: micro | memory | full`
   - `triggerSource: manual | pre_turn | mid_turn | model_switch`
   - `providerMode: local | remote`
   - `saved_tokens`
   - `trimmed_item_count`
   - `rebuilt_artifact_count`
   - `failure_count`
   - `reference_context_reestablished`
   - `rerouteReason`（如发生 model reroute）
8. `Index.ets` 现有 compaction notice/toast 继续复用，但要区分：
   - 微压缩完成
   - 完整压缩完成
   - 战后重建完成
   - 完整压缩失败 / 熔断暂停
## Phase 4 — Layer 4 自动触发、排除名单与熔断

### 目标
把四层能力编排成一个严格顺序的自动调度器，并保证失败不会无限重试。

### 关键文件
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\codex.rs`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CompactionPolicy.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CodexBackend.ets`
- 如需扩展通知：
  - `D:\code\harmony\ArkPilot\codex-main\codex-rs\app-server-protocol\src\protocol\v2.rs`
  - `D:\code\harmony\ArkPilot\codex-main\codex-rs\app-server\src\bespoke_event_handling.rs`

### 复用点
- `run_pre_sampling_compact(...)`
- `run_auto_compact(...)`
- `maybe_run_previous_model_inline_compact(...)`
- `shouldStartCompaction(...)`
- `shouldStartFallbackCompaction(...)`
- `compactionSnapshot()`

### 实施内容
1. 自动触发顺序改为：
   - 先看是否做 `micro`
   - 不够再看是否有可用 `memory tail + structured memory`
   - 再不够进入 `full`
2. 明确触发器拆成三类：
   - **Trigger A / pre-turn**：每次采样前检查当前 token 用量，必要时先压缩再发请求
   - **Trigger B / model-switch**：若切到更小 context window 的模型，且当前 token 已超新阈值，则先基于旧模型上下文做一次 inline compact
   - **Trigger C / mid-turn**：若本 turn 已命中 `token_limit_reached` 且仍需要 follow-up，则在同一 turn 内执行 continuation compact
3. 阈值写成公式，不只写概念：
   - 自动压缩阈值以 `min(config.model_auto_compact_token_limit, 90% * model_context_window)` 为主
   - 宿主 fallback 阈值和安全缓冲区必须与 provider/window 配置一起评估，不能写死一套常数
4. 自动调度器必须区分阶段：
   - `pre_turn` 与 `mid_turn` 的状态、可观测字段和 UI 提示分开
   - 同一 turn 最多允许 1 次 `pre_turn` + 1 次 `mid_turn` 自动压缩，避免同 turn 套娃
5. 引入**连续失败熔断**：
   - 同一线程连续自动压缩失败超过 3 次，直接停自动重试
   - 熔断后进入 cooldown，UI 只展示错误与手动重试入口
   - 手动重试成功后才清零 failure count
6. 加入**排除名单**：
   - `TaskKind::Compact`
   - `SubAgentSource::Compact`
   - `SubAgentSource::MemoryConsolidation`
   - review/realtime 会话
   - 没有 `model_context_window` 的线程
   - 已经处于 compaction turn 的请求
   避免“给压缩做压缩”“给记忆做记忆”的无限套娃
7. 模型切换仍复用 `maybe_run_previous_model_inline_compact(...)`，不在宿主重新发明第二套策略。
8. 文档里补一张决策表：
   - 输入：`current_tokens`、`context_window`、`auto_compact_limit`、`needs_follow_up`、`trigger_source`、`failure_count`、`cooldown_state`
   - 输出：`none | micro | memory_tail | full | trip_circuit_breaker`
9. 补齐观测指标：
   - `trigger_source`
   - `providerMode: local | remote`
   - `phase: pre_turn | mid_turn | manual`
   - `old_total_tokens / new_total_tokens / saved_tokens`
   - `trimmed_item_count`
   - `compact_latency_ms`
   - `failure_count`
   - `cooldown_state`
   - `reference_context_reestablished`
   - `model_reroute_reason`
## Phase 5 — UI 展示与最小配置

### 目标
不重构页面，只把四层状态可视化，保证用户知道系统现在在删什么、提炼什么、何时会跳到更重的一层。

### 关键文件
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\pages\Index.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\pages\SettingsPage.ets`（仅在确有必要时）

### 复用点
- `tokenUsageCard()`
- `contextRemainingPct()` / `contextBarColor()`
- `applyBackendSnapshot(...)`
- `applyCompactionSnapshot(...)`
- 现有 compaction notice / toast / retry UI

### 实施内容
1. 先把 Host/UI 契约拆成三条状态流，并写进文档：
   - **turn 事件流**：server notification / native event batch → `applyTurnEventBatch(...)`
   - **poll/reconcile 兜底流**：`turn/poll` → `applyTurnPollResult(...)`
   - **session/workspace 恢复流**：`thread/list` / `thread/read` → `SessionSummary` → workspace 绑定与恢复
2. token/context 流单独列出：
   - `ThreadTokenUsageUpdated` → thread snapshot 持久化
   - 同步更新 daily aggregate
   - 最终进入 `snapshot.tokenUsage`
   - terminal 后仍要 drain late diff/token，不能在 turn 完成那一刻立刻停止吸收尾包
3. 文档里明确 UI 侧除消息外还要稳定承载的状态：
   - `TurnTokenUsage` / `TokenUsageBreakdown` / `TokenUsageAggregate`
   - `CodexCompactionSnapshot`
   - `CodexRequestUserInput`
   - `WorkspaceDescriptor` / `workspacePermissionState` / `workspaceAccessKind` / `writableRoots`
   - provider 相关的 `contextWindow` / `modelAutoCompactTokenLimit`
4. 在 token 卡片与 notice 上补充四层状态：
   - 正常
   - 已微压缩 / 待微压缩
   - 已提炼结构化记忆 / polluted
   - 已完整压缩 / 已重建
   - 已熔断 / 等待手动重试
5. 展示最近一次动作：
   - 删减了多少字段/多少条工具结果
   - 节省了多少 token
   - 是 `manual` / `pre_turn` / `mid_turn` / `model_switch` 哪一种触发
   - 是否因熔断暂停自动压缩
6. 区分 approval 与 request-user-input：
   - approval 卡片沿用现有审批流
   - `request-user-input` 走单独问题卡片与恢复逻辑，不与 compaction notice 混用
7. workspace/session 显示补充：
   - 只读 / 可写 / 已撤销权限状态
   - session 恢复后 workspace 绑定是否稳定
8. 配置保持最小：
   - 首版不做独立 context 设置页
   - 仅在已有配置入口可写时，补极少数开关：自动管理、长期记忆、污染后自动降级
   - 若 host 尚无稳定写配置入口，则先只读展示，不抢先做 UI 表单
# Execution order

1. **Phase 1 先行**：因为微压缩与结构边界锁是后面三层的地基。
2. **Phase 2 第二**：先把“长期事实”和“近期原始上下文”拆开，避免后面完整压缩承担所有压力。
3. **Phase 3 第三**：在已有微压缩与结构化记忆的前提下接完整压缩和战后重建。
4. **Phase 4 第四**：最后把四层串成自动调度器，再加熔断与排除名单。
5. **Phase 5 最后**：UI 只消费已经稳定的状态，减少返工。

## Milestone 验收出口（Done criteria）

### M1 完成出口
- Layer 1 首批覆盖对象已在 `record_items()/process_item()` 入 history 即完成微压缩
- `raw_items()`、`for_prompt(...)`、token 统计口径一致
- `call_id`/locator/顺序/normalize 边界稳定

### M2 完成出口
- 新增字段在 host payload 中缺省时兼容旧快照
- 仅靠 event、仅靠 poll、event 丢失后 reconcile 三路最终状态一致
- token/context/compaction/memory/workspace 基础状态可被 ArkTS 稳定消费

### M3 完成出口
- phase1/phase2 选择与 forgetting 语义可观测、可验证
- `raw_memories.md` / `rollout_summaries/` / `MEMORY.md` / `memory_summary.md` 的生成和清理逻辑稳定
- polluted/no-output/forgetting 三类边界都有明确测试

### M4 完成出口
- manual / pre-turn / model-switch / mid-turn 四类入口全部可复现
- 同一 turn 不超过 1 次 pre-turn + 1 次 mid-turn 自动压缩
- 连续失败第 4 次前后熔断生效，并进入 cooldown
- `saved_tokens`、`trigger_source`、`providerMode`、`reference_context_reestablished` 等指标可记录

### M5 完成出口
- notice/toast/card 能解释最近一次上下文管理动作
- workspace/session 恢复、approval/request-user-input、late diff/token drain 都稳定
- 端到端长会话、polluted、熔断恢复、重启恢复场景跑通

# Risks

1. **字段删减误伤结构边界**：如果裁掉了 `tool_use/tool_result` 配对字段，会直接破坏后续 API 结构。
2. **近期尾部截取不成组**：流式碎片或同一 `message_id` 被拆开，容易造成后续对话不一致。
3. **memory 文档与实现漂移**：README 中对排序/时间戳的描述可能与实现不一致；计划、测试与实现冲突时，以代码真实行为为准，并补回文档。
4. **phase2 假成功**：memory consolidation 子 agent 返回 Completed，但 `MEMORY.md` / `memory_summary.md` 实际未生成或未更新，容易造成“看似成功、实际未生效”。
5. **完整压缩后失忆**：如果没有 `recent_artifact_refs`、`replacement_history` 和战后重建，压缩完成后模型会立刻丢掉当前工作集。
6. **legacy rollout 恢复退化**：旧 rollout 可能没有 `replacement_history`，恢复时只能退化为“摘要 + 下次全量 reinject”。
7. **自动重试死循环**：没有失败上限、同 turn 上限和排除名单，会复现无限压缩重试问题。
8. **lossy history 误判**：默认 `ThreadItem` 是 lossy 的，如果不写清 `persistExtendedHistory: true` 前提，回溯验证会得出错误结论。
9. **terminal 尾包丢失**：turn completed 后若不继续 drain late diff/token，UI 和持久化会出现状态不一致。
10. **UI 过度设计**：首版不要做 memory 编辑器、blob 管理页、独立 context 设置中心。
# Verification

1. **Layer 1 微压缩验证（Rust 历史层）**
   - 在 `core/src/context_manager/history_tests.rs` 直接构造大 `FunctionCallOutput`、`CustomToolCallOutput`、`ToolSearchOutput`、`LocalShellCall` 结果
   - 验证 `record_items()/process_item()` 入 history 即完成微压缩，而不是只在 prompt 前临时替换
   - 断言 `raw_items()` 已是压缩后形态，`for_prompt(...)` 不再含大字段，`call_id`/locator 仍在，token 明显下降
   - 断言 `normalize_history(...)` 不会制造 orphan output、不会触发 synthetic aborted output、不会打乱 call/output 顺序
   - 断言 pin 区中的最近工作集不会被 Layer 1 提前压掉
2. **Layer 2 结构化记忆验证（state/core）**
   - Given `memory_mode = enabled`、满足 age/idle/watermark 条件的线程；When phase1 执行；Then 正确生成或更新 `stage1_output`
   - Given 超长 rollout；When 构造 phase1 输入；Then middle truncation 同时保留头尾证据，不退化成 latest-only tail
   - Given phase2 合并；Then `raw_memories.md` 与 `rollout_summaries/` 按 `selected ∪ previous_selected` 同步，forgetting 可删除本轮被踢出的条目
   - Given web search/MCP 导致 polluted；Then 线程进入 `polluted`，若上轮被选中过则 enqueue forgetting
   - Given no-output；Then 仅在之前存在旧 `stage1_output` 时删除并置脏 phase2，否则保持 clean
3. **Layer 3 完整压缩验证（compact/core）**
   - 覆盖手动、pre-turn、mid-turn 三类入口
   - 验证 compact 请求在送模型前已完成工具输出预瘦身
   - 验证 compact 请求自己超窗时，会按最老 history 分组有限次裁剪并重试
   - 验证 `analysis` 不进入最终上下文，`summary` 被保留，`replacement_history` 被持久化
   - 验证成功后 `reference_context_item` 被清空或重建，下个正常 turn 发生全量 reinject
   - 验证 resume/fork 遇到新 rollout 时优先使用 `replacement_history`；遇到 legacy rollout 时按退化语义恢复
4. **Layer 4 自动触发验证（调度/熔断）**
   - 验证 Trigger A(pre-turn)、Trigger B(model-switch)、Trigger C(mid-turn) 的触发条件与互斥顺序
   - 验证同一 turn 最多发生 1 次 pre-turn + 1 次 mid-turn 自动压缩
   - 模拟连续失败，确认第 4 次前后熔断生效，并进入 cooldown
   - 验证 `compact_job` / `memory_job` / review / realtime / 无 `model_context_window` 线程不会自触发压缩
   - 验证 `old_total_tokens/new_total_tokens/saved_tokens/trigger_source` 等指标可被记录
5. **Host/UI 契约与回归验证**
   - 仅靠 event、仅靠 poll、event 丢失后 reconcile 三条路径，最终消息/diff/summary/tokenUsage 一致
   - turn terminal 后 late diff/token 仍能被 drain 并展示
   - `last_micro_compaction_*` 等新字段缺省时兼容旧快照，存在时可正确透传到 `CodexBackendSnapshot`
   - approval 与 `request-user-input` 两套卡片/恢复逻辑不串线
   - workspace 只读/可写/权限撤销状态展示正确，session 恢复后绑定稳定
6. **端到端验证**
   - 使用 `libcodexhost-builder\build.ps1 debug x86_64` 构建原生库
   - 在 DevEco Studio 打开 `Agent/`，用 x86_64 模拟器跑长会话、微压缩、结构化记忆、完整压缩、重启恢复、MCP/WebSearch polluted、熔断恢复场景
   - 记录至少一次 local compact、一次 remote compact（若 provider 支持）、一次 model-switch compact 的完整链路
# Critical files to modify

- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\context_manager\history.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\compact.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\compact_remote.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\codex.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\codex\rollout_reconstruction.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\ohos-host\src\lib.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\runtime\threads.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\runtime\memories.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\extract.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\state\src\model\thread_metadata.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\memories\phase1.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\memories\phase2.rs`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\core\src\memories\storage.rs`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\ConsoleModels.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CodexBackend.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CodexNative.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\backend\CompactionPolicy.ets`
- `D:\code\harmony\ArkPilot\Agent\entry\src\main\ets\pages\Index.ets`
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\app-server-protocol\src\protocol\v2.rs`（如通知/请求 payload 需要扩展）
- `D:\code\harmony\ArkPilot\codex-main\codex-rs\app-server\src\bespoke_event_handling.rs`（如服务端事件需要扩展）
