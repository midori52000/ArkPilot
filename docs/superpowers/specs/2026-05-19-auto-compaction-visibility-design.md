# 自动压缩可感知能力设计

日期：2026-05-19

## Context

当前仓库的压缩相关能力在后端已经存在，但前端对“自动压缩”仍然缺少完整感知。现状是：

- `codex-main` 后端已经具备自动压缩相关能力与状态字段；
- 仓库约束要求 `codex-main` 下只能修改 `lib.rs`，ArkTS 侧可自由修改；
- 这次不允许重做 `core/src/*.rs` 的压缩语义，只能通过转接层和 ArkTS 把现有能力正确用起来；
- 当前 ArkTS 已经能展示部分上下文与压缩历史，但自动压缩仍不够可见：用户看不到阈值是否启用、离触发还有多远、最近一次压缩是否为自动触发。

本设计的目标是：**在不修改 backend core 压缩语义的前提下，通过 `ohos-host/src/lib.rs` + ArkTS 集成，补齐“自动压缩可感知能力”。**

## Scope

本次只覆盖以下内容：

1. 在现有 token/context 卡片中显示：
   - 模型上下文窗口上限
   - 当前已用 tokens
   - 剩余比例 / 剩余空间
   - 自动压缩阈值是否启用
   - 自动压缩阈值是多少
   - 距离阈值还差多少 tokens
2. 在现有压缩历史区域中显示：
   - 最近一次完整压缩的触发来源（手动 / 预压缩 / 中途压缩 / 模型切换）
   - 微压缩历史
   - 失败记录 / 熔断器状态
3. 统一 `threadRead` 与 `turnPoll` 两条链路中的 `contextManagement` 语义。

本次不覆盖：

- 修改 `codex-main/codex-rs/core/src/compact.rs`
- 修改 `codex-main/codex-rs/core/src/compact_remote.rs`
- 修改 `codex-main/codex-rs/core/src/codex.rs`
- 新增 core 层自动压缩事件
- 改写自动压缩触发时机或失败恢复策略

## Existing capabilities to reuse

### Rust 转接层
文件：`codex-main/codex-rs/ohos-host/src/lib.rs`

已存在能力：
- `NativeContextManagementSnapshot`
- `resolve_thread_context_management(...)`
- `load_persisted_thread_context_management(...)`
- `build_context_management_payload(...)`
- `build_turn_poll_payload(...)`
- `build_thread_read_payload(...)`
- `model_auto_compact_token_limit` 配置读写链路
- `last_full_compaction_trigger`
- `last_micro_compaction_*`
- `compaction_failure_count`
- `compaction_circuit_open`

### ArkTS backend
文件：`Agent/entry/src/main/ets/backend/CodexBackend.ets`

已存在能力：
- `applyTokenUsagePayload(...)`
- `applyContextManagementPayload(...)`
- `cloneContextManagement(...)`
- `readThreadSnapshot(...)`
- `applyTurnPollResult(...)`
- `updateCompactionTokenDelta(...)`
- `pollCompactionUntilCompleted(...)`
- `completeCompaction(...)`
- `failCompaction(...)`

### ArkTS models
文件：`Agent/entry/src/main/ets/backend/ConsoleModels.ets`

已存在能力：
- `TurnTokenUsage`
  - `modelContextWindow`
  - `contextRemainingPercent`
- `CodexContextManagementSnapshot`
  - `lastMicroCompaction*`
  - `compactionFailureCount`
  - `compactionCircuitOpen`
  - `lastFullCompactionTrigger`
  - 其他压缩历史字段

### ArkTS UI
文件：`Agent/entry/src/main/ets/pages/Index.ets`

已存在能力：
- token/context 卡片：`tokenUsageCard()`
- 上下文辅助函数：
  - `contextWindow()`
  - `contextRemainingPct()`
  - `totalTokensUsed()`
  - `contextText()`
- 压缩历史文案函数：
  - `contextMicroCompactionText()`
  - `contextFullCompactionText()`
  - `contextCircuitBreakerText()`
  - `currentFullCompactionDetailText()`

## Recommended approach

### 1. Rust 转接层统一输出自动压缩相关信息

修改文件：`codex-main/codex-rs/ohos-host/src/lib.rs`

#### 目标
让 `threadRead` 与 `turnPoll` 返回的 `contextManagement` 以及自动压缩配置具有统一语义。

#### 方案
1. 保持 `contextManagement` 作为压缩历史与上下文辅助状态的统一出口。
2. 在 `resolve_thread_context_management(...)` 中继续输出统一后的 effective snapshot，确保：
   - persisted snapshot 是基础；
   - live thread state 作为补充；
   - 两条链路都走同一份有效快照。
3. 在 `threadRead` / `turnPoll` payload 中补充自动压缩阈值原始值：
   - 从当前生效配置中读取 `model_auto_compact_token_limit`
   - 将其作为单独字段输出给 ArkTS，而不是塞进历史快照字段里。

#### 设计原则
- 不新增 backend core 语义；
- 不改压缩触发逻辑；
- 只透传“当前配置值 + 现有历史信号”。

### 2. ArkTS backend 负责轻量派生，不猜 backend 语义

修改文件：
- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
- 必要时 `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
- `Agent/entry/src/main/ets/backend/CodexNative.ets` 仅在 bridge 类型需要补齐时修改

#### 目标
基于 native 返回的原始值，在 ArkTS 生成 UI 需要的自动压缩摘要。

#### 方案
1. 在现有 snapshot / result payload 中增加自动压缩阈值字段。
2. 在 `CodexBackend.ets` 中解析该字段，并与以下信息组合：
   - `tokenUsage.total.totalTokens`
   - `tokenUsage.modelContextWindow`
   - `tokenUsage.contextRemainingPercent`
   - `contextManagement.lastFullCompactionTrigger`
3. 派生出 UI 所需状态：
   - 自动压缩是否启用
   - 自动压缩阈值
   - 距离触发还差多少 tokens
   - 是否接近阈值

#### 计算规则
- 若 `model_auto_compact_token_limit <= 0`：视为未启用
- 若 `totalTokensUsed <= 0`：只显示阈值，不显示距离
- 若 `limit > used`：
  - remainingToAutoCompact = limit - used
- 若 `used >= limit`：
  - remainingToAutoCompact = 0
  - 视为已到达或超过阈值

#### 设计原则
- Rust 负责透出原始值；
- ArkTS 负责轻量派生展示；
- 避免在 Rust 与 ArkTS 两边重复编码 UI 逻辑。

### 3. 在现有 token/context 卡片中补齐自动压缩信息

修改文件：`Agent/entry/src/main/ets/pages/Index.ets`

#### 目标
在不新增大块 UI 的前提下，把自动压缩变成用户可见能力。

#### 展示位置
放入现有 `tokenUsageCard()` 中，和上下文窗口信息放在一起。

#### 展示内容
1. **上下文窗口**
   - 已存在，继续保留：
     - 模型上下文窗口上限
     - 已用 tokens
     - 剩余比例
2. **自动压缩**
   - 新增一行指标：
     - 未启用：`未启用`
     - 已启用：`阈值 96k`
     - 可计算剩余时：`阈值 96k（还差 8k）`
     - 超阈值时：`阈值 96k（已到达）`
3. **完整压缩历史**
   - 继续使用 `contextFullCompactionText()`
   - 当 detail 不完整时，弱化为：`手动触发过` / `预压缩触发过`
4. **微压缩 / 熔断器**
   - 继续复用现有字段
   - 保持中性文案，避免误报

#### 文案策略
- 自动压缩配置是当前态；
- 完整压缩 / 微压缩 / 熔断器是历史态；
- 当前态与历史态必须分层展示，不能混成一个结论。

### 4. 自动压缩展示与实时压缩状态的关系

#### 原则
- 手动压缩实时状态仍以 `compactionState` / `CompactionNotice` 为准；
- 自动压缩这次只补“可感知历史与阈值”，不承诺补出精确实时事件。

#### 原因
在不修改 core 语义前提下，当前系统并没有可靠的专门“自动压缩开始/结束”前端事件模型；强行伪造会误导。

#### 最终效果
用户能看到：
- 自动压缩是否启用
- 离自动压缩还有多远
- 最近一次压缩是否属于自动触发类型
- 是否存在失败记录或熔断

但不会伪装成：
- “自动压缩正在进行中”的专用实时状态机

## Data model changes

### 建议新增字段
在 ArkTS snapshot / backend state 中新增或补齐以下字段：
- `modelAutoCompactTokenLimit: number | null`
- `autoCompactEnabled: boolean`
- `remainingToAutoCompact: number | null`
- `autoCompactNearThreshold: boolean`

其中：
- `modelAutoCompactTokenLimit` 来自 native 原始透传
- 其余字段可在 ArkTS 派生，不必写回 native

### 为什么不把这些都放进 Rust
因为这些是展示派生值，不是 backend 语义本身。把它们留在 ArkTS 更利于后续调整显示规则。

## Error handling

### Native 层
- 若未读取到 `model_auto_compact_token_limit`：按未启用处理
- 若 `tokenUsage` 缺失：只显示阈值，不显示“还差多少”
- 若 `contextManagement` 缺失：历史压缩项回退到“暂无记录” / “正常”

### ArkTS 层
- 所有数值字段必须容错 `null` / `undefined` / NaN
- 阈值信息缺失时不报错，只降级文案
- 不使用推断值覆盖 backend 原始字段

## Testing / verification

### 1. threadRead / turnPoll 一致性
验证同一线程下：
- `modelAutoCompactTokenLimit` 一致
- `contextManagement.lastFullCompactionTrigger` 一致
- `compactionFailureCount` / `compactionCircuitOpen` 一致

### 2. token 卡片展示
验证以下场景：
- 未启用自动压缩
- 启用自动压缩，且距离阈值较远
- 启用自动压缩，且接近阈值
- 已达到阈值

### 3. 历史压缩文案
验证：
- detail 完整时显示完整文案
- 只有 trigger 时显示弱提示
- 没有记录时显示中性文案

### 4. 重开线程 / 重进应用
验证：
- 自动压缩阈值仍正确显示
- 历史压缩字段不发生 threadRead / turnPoll 语义漂移

## Critical files

- `codex-main/codex-rs/ohos-host/src/lib.rs`
- `Agent/entry/src/main/ets/backend/CodexBackend.ets`
- `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
- `Agent/entry/src/main/ets/backend/CodexNative.ets`（如需要补 bridge 类型）
- `Agent/entry/src/main/ets/pages/Index.ets`

## Out of scope

本次明确不做：
- 修改自动压缩触发策略
- 修改自动压缩失败恢复策略
- 修改 backend core compaction event 语义
- 新增独立“自动压缩运行中”事件系统

## Recommendation

按最小改动路径推进：
1. 先在 `ohos-host/src/lib.rs` 透出 `model_auto_compact_token_limit`
2. 再在 ArkTS backend 解析并派生展示值
3. 最后在现有 token/context 卡片中补齐自动压缩展示

这样能在最小风险下，把“自动压缩”从后台隐式能力变成前台可理解能力。