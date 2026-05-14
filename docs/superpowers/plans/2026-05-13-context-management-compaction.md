# Context Management and Compaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 ArkPilot 从“前端 200ms 全量轮询 + UI 固定阈值触发压缩”的方案，改造成“thread 级持久上下文快照 + hybrid `turn_events`/`turn_poll` + 后端主导自动压缩”的系统。

**Architecture:** 保持 app-server thread 作为模型上下文的真相源，不改 app-server 协议主干；将 ohos-host 升级为 durable adapter，在本地维护每个 thread 的最新 token/context 快照，并把现有 server notifications 整理成可消费的 `turn_events` 增量流。ArkTS 不再依赖 active turn 全量轮询来推测上下文状态，而是优先消费 `thread/read` 的 thread 级 snapshot，再由一个确定性的 compaction policy 决定何时压缩；最终把 core 已有的 `model_auto_compact_token_limit` 暴露到 UI，让后端自动压缩成为主路径，UI 自动压缩仅保留兜底。

**Tech Stack:** Rust (`codex-ohos-host`), codex app-server protocol v2, ArkTS/ArkUI, NAPI bridge, `@ohos/hypium`, PowerShell build scripts。

---

## 现行方案分析

### 1. 当前已经成熟、可以直接复用的后端接口

这些能力已经存在，足以支撑本次改造，**不需要改 app-server 协议**：

- `thread/list`：恢复 thread 列表
- `thread/read(includeTurns=true)`：恢复 thread 历史与 diff
- `thread/resume`：把持久 thread 恢复到运行态
- `turn/start`：发起新 turn
- `turn/poll`：获取权威 turn snapshot
- `thread/compact/start`：触发上下文压缩
- `ThreadTokenUsageUpdated`：后端已持续发送 token usage 更新
- `turnEvents` bridge：ArkTS ⇄ NAPI ⇄ ohos-host 的桥已经存在，但 ohos-host 当前返回空数组

### 2. 现行方案的优点

- thread 历史已经落盘，`persist_extended_history = true` 已开启，模型续接能力本身是成立的。
- 压缩入口已打通：ArkTS → NAPI → ohos-host → `thread/compact/start`。
- token usage 更新事件已经从 server 到达 ohos-host，只是没有被 thread 级持久化和暴露。
- bridge 层已有 `turnEvents` 函数签名，后续补实现时不需要再扩 NAPI surface。

### 3. 现行方案的主要问题

| 领域 | 当前实现 | 问题 | 本次改造策略 |
|---|---|---|---|
| 上下文真相源 | app-server thread 是真相源 | 正确，但 ArkTS 仍靠 active turn 轮询补状态 | 保持 thread 为真相源，补 thread 级 snapshot |
| token/context 恢复 | `thread/read` 不带 tokenUsage | 历史会话恢复后 context 条不可信 | 在 ohos-host 维护并返回 thread 级 token snapshot |
| 传输模型 | `turn_poll` 返回整份 thread messages | 长会话开销线性增长 | 先保留 `turn_poll` 兜底，再补 `turn_events` 增量流 |
| 自动压缩策略 | UI 看到 `<20%` 就直接压缩 | 与 active turn、cooldown、后端 auto-compact 冲突 | 提炼 deterministic policy，后端 auto-compact 优先 |
| 运行时内存 | thread/turn cache 只增不减 | 内存与日志膨胀 | 终态 turn 清理，thread snapshot 留存 |
| 摘要语义 | summary 更像操作日志 | 恢复时缺少“当前任务状态” | 本计划先稳定数据流，语义摘要统一延后 |

### 4. 改造边界

**本计划内：**
- thread 级 token/context snapshot
- hybrid `turn_events`/`turn_poll`
- deterministic compaction policy
- `model_auto_compact_token_limit` 暴露与接线
- turn cache 清理与日志降噪

**本计划外：**
- 改 app-server 协议 schema
- 改 core compaction prompt 模板
- 做层级记忆 / 语义记忆系统
- 全量重写 `CodexBackend.ets`

---

## 复用与补口清单

### 直接复用现有接口（不改 bridge surface）

- `thread/read`：继续作为历史恢复入口，但 payload 增加 `tokenUsage`
- `turn/poll`：继续作为权威快照与 fallback
- `thread/compact/start`：继续作为压缩执行入口
- `ThreadTokenUsageUpdated`：继续作为 token 更新来源
- `turnEvents`：继续沿用已有导出函数名与 d.ts，**只补 ohos-host 实现与 ArkTS 消费**

### 需要补的 ohos-host 本地能力（不改 app-server）

- thread 级 `latest_token_usage` 缓存
- `runtime/thread-context.json` 持久化
- `turn_events` 本地事件队列与 drain
- terminal turn cleanup
- `model_auto_compact_token_limit` 与 provider/config 同步

### 需要补的 ArkTS 能力

- `CompactionPolicy` 纯逻辑 helper
- 基于 `thread/read.tokenUsage` 的历史恢复
- `turn_events` reducer / fallback 轮询策略
- UI 自动压缩从“阈值即执行”改为“策略判断后执行”

---

## 文件结构与职责落点

### Rust / ohos-host

- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`
  - 维护 thread 级 token snapshot
  - 实现 `turn_events`
  - 清理终态 turn cache
  - 扩展 provider settings 持久化 `model_auto_compact_token_limit`
  - 为 `thread/read` 和 `turn/poll` 统一生成 `tokenUsage` payload

### ArkTS backend

- Create: `Agent/entry/src/main/ets/backend/CompactionPolicy.ets`
  - 封装“是否允许压缩”的纯逻辑
- Modify: `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
  - 增补 compaction policy / provider auto compact 相关字段
- Modify: `Agent/entry/src/main/ets/backend/CodexBackend.ets`
  - 恢复历史会话时读取 thread 级 token snapshot
  - 从 `turnEvents` 增量驱动 UI，`turnPoll` 作为 fallback
  - 控制 compaction 状态机与 cooldown
- Modify: `Agent/entry/src/main/ets/pages/Index.ets`
  - 移除直接 `<20%` 自动压缩逻辑，改为调用 backend policy

### Provider / settings UI（第三阶段）

- Modify: `Agent/entry/src/main/ets/backend/ProviderConfigStore.ets`
- Modify: `Agent/entry/src/main/ets/backend/ProviderCatalogService.ets`
- Modify: `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
- Modify: `Agent/entry/src/main/ets/apim/ApiManagementService.ets`
- Modify: `Agent/entry/src/main/ets/apim/ApiManagementViewModel.ets`
- Modify: `Agent/entry/src/main/ets/pages/AddProviderPage.ets`
  - 贯通 `model_auto_compact_token_limit` 的读写与展示

### Tests

- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs` (`#[cfg(test)] mod tests`)
- Create: `Agent/entry/src/test/CompactionPolicy.test.ets`

---

## 分阶段改造路线

### 阶段 1：修正确性（最小改动优先）

目标：让“恢复历史会话后的上下文状态”和“自动压缩触发时机”先变得可靠。

- 为 ohos-host 增加 thread 级 `latest_token_usage`
- `thread/read` 直接返回 thread 级 `tokenUsage`
- 历史恢复优先信任 `thread/read.tokenUsage`，缺失时才 fallback 到 `turn/poll`
- UI 自动压缩增加 `idle-only`、`cooldown`、`once-per-turn`
- 去掉大体积轮询日志

### 阶段 2：修成本（传输与内存）

目标：不改 app-server 的前提下，把“长会话越跑越重”的成本压下来。

- 实现 ohos-host `turn_events` 本地事件 drain
- ArkTS 轮询改为“events 优先，poll 保底”
- turn 结束后清理 `state.turns`，thread 只保留必要 snapshot
- 历史 thread 继续靠 `thread/read` 恢复，不在内存里常驻所有 turn

### 阶段 3：后端主导自动压缩

目标：把真正的自动压缩阈值交给 core 的 `model_auto_compact_token_limit`，UI 自动压缩降级为兜底策略。

- Provider settings 暴露 `auto_compact_token_limit`
- 同步到 `config.toml` 的 `model_auto_compact_token_limit`
- ArkTS 检测到后端已配置 auto compact 时，不再主动按 `<20%` 触发压缩
- 仅当后端 limit 缺失或 tokenUsage 不可用时，才使用 UI fallback policy

### 延后项（单独计划）

- 统一“会话恢复摘要”和“压缩摘要”的语义格式
- 把 summary 从“操作日志”升级为“任务状态 checkpoint”

---

## 实施任务

### Task 1: 在线程级别持久化 token/context snapshot

**Files:**
- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`
- Test: `codex-main/codex-rs/ohos-host/src/lib.rs` (`#[cfg(test)] mod tests`)

- [ ] **Step 1: 先写失败测试，锁定“历史恢复也能拿到 tokenUsage”**

```rust
#[test]
fn resolve_thread_token_usage_prefers_thread_snapshot_when_turn_state_is_missing() {
    let usage = NativeTokenUsage {
        total: NativeTokenUsageBreakdown {
            input_tokens: 240000,
            output_tokens: 4000,
            cached_input_tokens: 120000,
            reasoning_output_tokens: 800,
            total_tokens: 244000,
        },
        last: NativeTokenUsageBreakdown {
            input_tokens: 1000,
            output_tokens: 200,
            cached_input_tokens: 0,
            reasoning_output_tokens: 0,
            total_tokens: 1200,
        },
        model_context_window: Some(272000),
    };

    let mut state = NativeConversationState::default();
    state.threads.insert(
        "thread-1".to_string(),
        NativeThreadState {
            remote_thread_id: "thread-1".to_string(),
            cwd: None,
            messages: vec![],
            latest_token_usage: Some(usage.clone()),
            ..Default::default()
        },
    );

    let resolved = resolve_thread_token_usage(&state, "thread-1");
    assert_eq!(resolved.expect("usage should exist").total.total_tokens, 244000);
}
```

- [ ] **Step 2: 运行测试，确认当前实现失败**

Run:
```powershell
cargo test -p codex-ohos-host resolve_thread_token_usage_prefers_thread_snapshot_when_turn_state_is_missing -- --nocapture
```

Expected: FAIL，报 `latest_token_usage` 字段或 `resolve_thread_token_usage` 函数不存在。

- [ ] **Step 3: 写最小实现，把 token usage 提升到 thread 级别**

```rust
#[derive(Debug, Clone, Default)]
struct NativeThreadState {
    remote_thread_id: String,
    cwd: Option<PathBuf>,
    messages: Vec<NativeMessage>,
    latest_token_usage: Option<NativeTokenUsage>,
}

fn resolve_thread_token_usage(
    state: &NativeConversationState,
    thread_id: &str,
) -> Option<NativeTokenUsage> {
    state
        .threads
        .get(thread_id)
        .and_then(|thread| thread.latest_token_usage.clone())
        .or_else(|| {
            state
                .turns
                .values()
                .find(|turn| turn.thread_id == thread_id)
                .and_then(|turn| turn.token_usage.clone())
        })
}
```

并在 `ServerNotification::ThreadTokenUsageUpdated` 分支中补这段：

```rust
if let Some(thread) = state.threads.get_mut(&thread_id) {
    thread.latest_token_usage = Some(usage.clone());
}
```

- [ ] **Step 4: 统一 `thread/read` 和 `turn/poll` 的 token payload 生成**

```rust
fn build_token_usage_payload(tu: &NativeTokenUsage) -> serde_json::Value {
    let total_blended = ((tu.total.input_tokens - tu.total.cached_input_tokens.max(0)).max(0)
        + tu.total.output_tokens.max(0)).max(0);
    let last_blended = ((tu.last.input_tokens - tu.last.cached_input_tokens.max(0)).max(0)
        + tu.last.output_tokens.max(0)).max(0);
    let ctx_remaining_pct = tu.model_context_window.map(|w| {
        codex_protocol::protocol::TokenUsage {
            total_tokens: tu.total.total_tokens,
            input_tokens: tu.total.input_tokens,
            cached_input_tokens: tu.total.cached_input_tokens,
            output_tokens: tu.total.output_tokens,
            reasoning_output_tokens: tu.total.reasoning_output_tokens,
        }
        .percent_of_context_window_remaining(w)
    });

    serde_json::json!({
        "total": {
            "inputTokens": tu.total.input_tokens,
            "outputTokens": tu.total.output_tokens,
            "cachedInputTokens": tu.total.cached_input_tokens,
            "reasoningOutputTokens": tu.total.reasoning_output_tokens,
            "totalTokens": tu.total.total_tokens,
            "blendedTotal": total_blended,
        },
        "last": {
            "inputTokens": tu.last.input_tokens,
            "outputTokens": tu.last.output_tokens,
            "cachedInputTokens": tu.last.cached_input_tokens,
            "reasoningOutputTokens": tu.last.reasoning_output_tokens,
            "totalTokens": tu.last.total_tokens,
            "blendedTotal": last_blended,
        },
        "modelContextWindow": tu.model_context_window,
        "contextRemainingPercent": ctx_remaining_pct,
    })
}
```

然后：
- `build_turn_poll_payload()` 改为调用这个 helper
- `build_thread_read_payload()` 新增：

```rust
let token_usage = with_native_state(|state| {
    resolve_thread_token_usage(state, &thread.id).map(|tu| build_token_usage_payload(&tu))
});
```

并把 `tokenUsage` 放进返回 JSON。

- [ ] **Step 5: 重新运行测试，确认通过**

Run:
```powershell
cargo test -p codex-ohos-host resolve_thread_token_usage_prefers_thread_snapshot_when_turn_state_is_missing -- --nocapture
```

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add codex-main/codex-rs/ohos-host/src/lib.rs
git commit -m @'
fix: restore thread token usage from thread snapshots
'@
```

---

### Task 2: 持久化 thread context snapshot，并在终态清理 turn cache

**Files:**
- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`
- Test: `codex-main/codex-rs/ohos-host/src/lib.rs` (`#[cfg(test)] mod tests`)

- [ ] **Step 1: 先写失败测试，锁定 snapshot round-trip 与 terminal cleanup**

```rust
#[test]
fn thread_context_snapshot_round_trips() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("runtime").join("thread-context.json");

    let mut snapshots = ThreadContextSnapshotFile::default();
    snapshots.threads.insert(
        "thread-1".to_string(),
        ThreadContextSnapshot {
            updated_at: 1,
            latest_token_usage: Some(NativeTokenUsage {
                total: NativeTokenUsageBreakdown {
                    input_tokens: 10,
                    output_tokens: 20,
                    cached_input_tokens: 0,
                    reasoning_output_tokens: 0,
                    total_tokens: 30,
                },
                last: NativeTokenUsageBreakdown::default(),
                model_context_window: Some(1000),
            }),
        },
    );

    persist_thread_context_snapshots(&path, &snapshots).expect("persist");
    let loaded = load_thread_context_snapshots(&path).expect("load");
    assert_eq!(loaded.threads["thread-1"].latest_token_usage.as_ref().unwrap().total.total_tokens, 30);
}
```

```rust
#[test]
fn cleanup_terminal_turn_keeps_thread_snapshot_and_removes_turn_state() {
    let usage = NativeTokenUsage {
        total: NativeTokenUsageBreakdown { total_tokens: 55, ..Default::default() },
        last: NativeTokenUsageBreakdown::default(),
        model_context_window: Some(1000),
    };

    with_native_state(|state| {
        *state = NativeConversationState::default();
        state.threads.insert(
            "thread-1".to_string(),
            NativeThreadState {
                remote_thread_id: "thread-1".to_string(),
                cwd: None,
                messages: vec![],
                latest_token_usage: Some(usage.clone()),
                ..Default::default()
            },
        );
        state.turns.insert(
            "turn-1".to_string(),
            NativeTurnState {
                thread_id: "thread-1".to_string(),
                status: "completed".to_string(),
                token_usage: Some(usage),
                ..Default::default()
            },
        );
    });

    cleanup_terminal_turn_state("turn-1");

    with_native_state(|state| {
        assert!(state.turns.get("turn-1").is_none());
        assert_eq!(
            state.threads["thread-1"]
                .latest_token_usage
                .as_ref()
                .unwrap()
                .total
                .total_tokens,
            55
        );
    });
}
```

- [ ] **Step 2: 运行测试，确认当前实现失败**

Run:
```powershell
cargo test -p codex-ohos-host thread_context_snapshot_round_trips cleanup_terminal_turn_keeps_thread_snapshot_and_removes_turn_state -- --nocapture
```

Expected: FAIL，报 snapshot 结构或 cleanup helper 不存在。

- [ ] **Step 3: 实现 snapshot 文件与 terminal cleanup**

```rust
#[derive(Default, Clone, Serialize, Deserialize)]
struct ThreadContextSnapshot {
    updated_at: i64,
    latest_token_usage: Option<NativeTokenUsage>,
}

#[derive(Default, Clone, Serialize, Deserialize)]
struct ThreadContextSnapshotFile {
    threads: HashMap<String, ThreadContextSnapshot>,
}

fn thread_context_snapshot_path(codex_home: &Path) -> PathBuf {
    codex_home.join("runtime").join("thread-context.json")
}
```

并新增：
- `load_thread_context_snapshots()`
- `persist_thread_context_snapshots()`
- `store_thread_context_snapshot(thread_id, usage)`
- `cleanup_terminal_turn_state(turn_id)`

约束：
- 只保存 thread 级 token/context，不保存完整 messages
- thread archive 时同步删除 snapshot entry
- app 启动时懒加载，不要求初始化阶段全量读入 turn

- [ ] **Step 4: 在 `ThreadTokenUsageUpdated` 和 terminal 路径接线**

在 `ThreadTokenUsageUpdated` 分支里，在更新内存后调用：

```rust
let codex_home = resolve_codex_home(None);
store_thread_context_snapshot(&codex_home, &payload.thread_id, &usage)?;
```

在 terminal 状态已 drain 完毕后调用：

```rust
cleanup_terminal_turn_state(&payload.turn_id);
```

要求：只在 `completed` / `failed` / `interrupted` 且 diff/token usage 已完成最终刷新后清理，避免抢跑。

- [ ] **Step 5: 重新运行测试并跑现有 ohos-host 测试集**

Run:
```powershell
cargo test -p codex-ohos-host thread_context_snapshot_round_trips cleanup_terminal_turn_keeps_thread_snapshot_and_removes_turn_state -- --nocapture
cargo test -p codex-ohos-host --lib
```

Expected: 两个新增测试 PASS；现有 ohos-host 单测不回归。

- [ ] **Step 6: 提交**

```powershell
git add codex-main/codex-rs/ohos-host/src/lib.rs
git commit -m @'
fix: persist thread context snapshots and clean terminal turn state
'@
```

---

### Task 3: 用确定性策略替代 UI 直接阈值压缩

**Files:**
- Create: `Agent/entry/src/main/ets/backend/CompactionPolicy.ets`
- Create: `Agent/entry/src/test/CompactionPolicy.test.ets`
- Modify: `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
- Modify: `Agent/entry/src/main/ets/backend/CodexBackend.ets`
- Modify: `Agent/entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: 先写失败测试，锁定策略的三个护栏**

```ts
import { describe, it, expect } from '@ohos/hypium';
import {
  CompactionDecisionInput,
  shouldStartCompaction,
} from '../main/ets/backend/CompactionPolicy';

export default function compactionPolicyTest() {
  describe('compactionPolicyTest', () => {
    it('blocks_when_turn_is_active', 0, () => {
      const input: CompactionDecisionInput = {
        contextRemainingPercent: 12,
        hasTokenUsage: true,
        activeTurnId: 'turn-1',
        lastCompactionTurnId: '',
        cooldownMs: 60000,
        lastCompactionAtMs: 0,
        nowMs: 100000,
        backendAutoCompactEnabled: false,
      };
      expect(shouldStartCompaction(input)).assertFalse();
    });

    it('blocks_when_same_turn_already_compacted', 0, () => {
      const input: CompactionDecisionInput = {
        contextRemainingPercent: 12,
        hasTokenUsage: true,
        activeTurnId: '',
        currentTurnId: 'turn-2',
        lastCompactionTurnId: 'turn-2',
        cooldownMs: 60000,
        lastCompactionAtMs: 0,
        nowMs: 100000,
        backendAutoCompactEnabled: false,
      };
      expect(shouldStartCompaction(input)).assertFalse();
    });

    it('blocks_when_backend_auto_compact_is_enabled', 0, () => {
      const input: CompactionDecisionInput = {
        contextRemainingPercent: 12,
        hasTokenUsage: true,
        activeTurnId: '',
        currentTurnId: 'turn-3',
        lastCompactionTurnId: '',
        cooldownMs: 60000,
        lastCompactionAtMs: 0,
        nowMs: 100000,
        backendAutoCompactEnabled: true,
      };
      expect(shouldStartCompaction(input)).assertFalse();
    });
  });
}
```

- [ ] **Step 2: 在 DevEco 本地单测运行器中确认失败**

Run:
- DevEco Studio → `Agent/entry/src/test/CompactionPolicy.test.ets` → Run Local Unit Test

Expected: FAIL，报 helper / type 不存在。

- [ ] **Step 3: 提炼纯策略 helper，避免把条件散在 `Index.ets` 和 `CodexBackend.ets`**

```ts
export interface CompactionDecisionInput {
  contextRemainingPercent: number;
  hasTokenUsage: boolean;
  activeTurnId?: string;
  currentTurnId?: string;
  lastCompactionTurnId: string;
  cooldownMs: number;
  lastCompactionAtMs: number;
  nowMs: number;
  backendAutoCompactEnabled: boolean;
}

export function shouldStartCompaction(input: CompactionDecisionInput): boolean {
  if (!input.hasTokenUsage) return false;
  if (input.backendAutoCompactEnabled) return false;
  if (input.contextRemainingPercent < 0 || input.contextRemainingPercent >= 20) return false;
  if ((input.activeTurnId ?? '').trim().length > 0) return false;
  if ((input.currentTurnId ?? '') === input.lastCompactionTurnId) return false;
  if (input.lastCompactionAtMs > 0 && (input.nowMs - input.lastCompactionAtMs) < input.cooldownMs) return false;
  return true;
}
```

- [ ] **Step 4: 在 `CodexBackend.ets` 和 `Index.ets` 接线**

1. `CodexBackend` 为每个 thread 增加：
```ts
lastCompactionAtMs: number = 0;
lastCompactionTurnId: string = '';
backendAutoCompactEnabled: boolean = false;
```

2. `loadThreadHistory()` 优先吃 `thread/read.tokenUsage`，只有缺失时才 fallback：
```ts
if (snapshot.thread.tokenUsage === null) {
  await this.hydrateThreadTokenUsage(snapshot.thread, snapshot.lastTurnId);
}
```

3. `compactThread()` 增加硬保护：
```ts
if (thread.activeTurn !== null) {
  throw new Error('当前 turn 尚未结束，暂不允许压缩。');
}
```

4. `Index.applyBackendSnapshot()` 不再直接 `<20%` 即 `retryCurrentCompaction()`，改为调用 backend 提供的策略判断。

- [ ] **Step 5: 重新运行本地单测，并做一次历史会话恢复手测**

Run:
- DevEco Studio → `Agent/entry/src/test/CompactionPolicy.test.ets` → Run Local Unit Test

Manual check:
1. 启动 app
2. 进入已有历史会话
3. 确认 context 条可直接显示，不需要先发新消息
4. 在 active turn 期间确认不会触发压缩

Expected:
- Local Unit Test PASS
- 历史恢复后 context 条可见
- active turn 期间无自动压缩

- [ ] **Step 6: 提交**

```powershell
git add Agent/entry/src/main/ets/backend/CompactionPolicy.ets Agent/entry/src/test/CompactionPolicy.test.ets Agent/entry/src/main/ets/backend/ConsoleModels.ets Agent/entry/src/main/ets/backend/CodexBackend.ets Agent/entry/src/main/ets/pages/Index.ets
git commit -m @'
fix: gate auto compaction with deterministic policy
'@
```

---

### Task 4: 把 `turn_events` 做成增量通道，并改成 events-first / poll-fallback

**Files:**
- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`
- Modify: `Agent/entry/src/main/ets/backend/CodexBackend.ets`

- [ ] **Step 1: 先写失败测试，锁定 `turn_events` drain 语义**

```rust
#[test]
fn turn_events_drains_queue_once() {
    with_native_state(|state| {
        *state = NativeConversationState::default();
        state.turns.insert(
            "turn-1".to_string(),
            NativeTurnState {
                thread_id: "thread-1".to_string(),
                pending_events: vec![
                    NativeTurnEvent::Status { status: "inProgress".to_string(), summary_title: "执行中".to_string() },
                    NativeTurnEvent::SummaryLine { line: "开始压缩上下文。".to_string() },
                ],
                ..Default::default()
            },
        );
    });

    let first = with_native_state(|state| drain_turn_events(state, "turn-1"));
    let second = with_native_state(|state| drain_turn_events(state, "turn-1"));

    assert_eq!(first.len(), 2);
    assert_eq!(second.len(), 0);
}
```

- [ ] **Step 2: 运行测试，确认当前实现失败**

Run:
```powershell
cargo test -p codex-ohos-host turn_events_drains_queue_once -- --nocapture
```

Expected: FAIL，报 `pending_events` / `NativeTurnEvent` / `drain_turn_events` 不存在。

- [ ] **Step 3: 在 ohos-host 内部实现本地事件队列**

```rust
#[derive(Clone, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum NativeTurnEvent {
    Status { status: String, summary_title: String },
    SummaryLine { line: String },
    MessageSnapshot { messages: Vec<NativeMessage> },
    DiffSnapshot { diff: String, diff_stat: String, changed_files_text: String },
    TokenUsage { token_usage: serde_json::Value },
}

#[derive(Clone, Default)]
struct NativeTurnState {
    thread_id: String,
    status: String,
    messages: Vec<NativeMessage>,
    summary: Vec<String>,
    summary_title: String,
    diff: String,
    diff_authoritative: bool,
    error_message: String,
    cwd: Option<PathBuf>,
    local_diff_tracker: Option<Arc<AsyncMutex<TurnDiffTracker>>>,
    token_usage: Option<NativeTokenUsage>,
    pending_events: Vec<NativeTurnEvent>,
}
```

在这些位置 push 事件：
- `append_assistant_delta()`
- `append_reasoning_delta()`
- `push_turn_summary()`
- `append_turn_diff()`
- terminal status 更新
- `ThreadTokenUsageUpdated`

`codex_ohos_host_turn_events()` 改为：

```rust
pub extern "C" fn codex_ohos_host_turn_events(
    _thread_id: *const c_char,
    turn_id: *const c_char,
) -> *const c_char {
    let turn_id = ffi_string(turn_id).unwrap_or_default();
    let json = with_native_state(|state| {
        serde_json::to_string(&drain_turn_events(state, &turn_id)).unwrap_or_else(|_| "[]".to_string())
    });
    write_cstring(&LAST_TURN_EVENTS_JSON, &json)
}
```

- [ ] **Step 4: 让 ArkTS 变成 events-first / poll-fallback**

在 `CodexBackend.pollTurnUntilCompleted()` 内：

```ts
const eventPayload: Object[] = parseJsonText(
  turnEventsNative(thread.remoteThreadId, pendingTurn.turnId),
  [] as Object
) as Object[];
if (eventPayload.length > 0) {
  const nextSnapshot = this.applyTurnEventBatch(thread, pendingTurn.turnId, eventPayload);
  this.emitTurnUpdate(thread, pendingTurn, nextSnapshot);
  if (nextSnapshot.status !== 'inProgress') {
    // terminal path 与现有 drain/recoverDiff 逻辑复用
    ...
  }
}
```

保留 `turnPollAsyncNative()` 作为三类 fallback：
1. 每隔 500ms 做一次权威 heartbeat
2. events 连续为空但 turn 仍在运行
3. terminal 阶段做最终 diff/tokenUsage drain

同时把大对象日志从：
```ts
this.logInfo(`turnPoll thread=${thread.remoteThreadId} turn=${pendingTurn.turnId} payload=${JSON.stringify(pollObject)}`);
```
改为：
```ts
this.logInfo(`turnPoll thread=${thread.remoteThreadId} turn=${pendingTurn.turnId} status=${nextSnapshot.status} messageCount=${thread.messages.length}`);
```

- [ ] **Step 5: 重新运行 Rust 测试，并做长会话手测**

Run:
```powershell
cargo test -p codex-ohos-host turn_events_drains_queue_once -- --nocapture
cargo test -p codex-ohos-host --lib
```

Manual check:
1. 启动 emulator / app
2. 发起一个包含命令输出、diff、reasoning 的长 turn
3. 观察 UI 是否持续更新
4. 观察日志不再输出整包 JSON
5. 观察结束后内存状态不再累积历史 turn

Expected:
- 新增 Rust 测试 PASS
- UI 仍然连续刷新
- 日志明显变小
- 长会话延迟下降

- [ ] **Step 6: 提交**

```powershell
git add codex-main/codex-rs/ohos-host/src/lib.rs Agent/entry/src/main/ets/backend/CodexBackend.ets
git commit -m @'
perf: use incremental turn events before full turn polling
'@
```

---

### Task 5: 暴露 `model_auto_compact_token_limit`，把后端 auto-compact 变成主路径

**Files:**
- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`
- Modify: `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
- Modify: `Agent/entry/src/main/ets/backend/ProviderConfigStore.ets`
- Modify: `Agent/entry/src/main/ets/backend/ProviderCatalogService.ets`
- Modify: `Agent/entry/src/main/ets/apim/ApiManagementService.ets`
- Modify: `Agent/entry/src/main/ets/apim/ApiManagementViewModel.ets`
- Modify: `Agent/entry/src/main/ets/pages/AddProviderPage.ets`
- Modify: `Agent/entry/src/main/ets/backend/CodexBackend.ets`
- Modify: `Agent/entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: 先写 Rust 失败测试，锁定 provider settings 对 auto compact limit 的持久化**

```rust
#[test]
fn render_config_toml_writes_auto_compact_limit() {
    let config = render_config_toml(&ProviderSettings {
        base_url: "https://example.com/v1".to_string(),
        api_key: "secret".to_string(),
        model: "test-model".to_string(),
        context_window: Some(200000),
        auto_compact_token_limit: Some(160000),
    });

    assert!(config.contains("model_auto_compact_token_limit = 160000"));
}
```

- [ ] **Step 2: 运行测试，确认当前实现失败**

Run:
```powershell
cargo test -p codex-ohos-host render_config_toml_writes_auto_compact_limit -- --nocapture
```

Expected: FAIL，报字段不存在。

- [ ] **Step 3: 扩展 provider settings 与 config 同步**

在 `ProviderSettings`、`ProviderCatalogRecord` 里增加：

```rust
#[serde(default)]
auto_compact_token_limit: Option<i64>,
```

在 `persist_provider_settings()` 中追加：

```rust
if let Some(limit) = settings.auto_compact_token_limit {
    if limit > 0 {
        edits.push(ConfigEdit::SetPath {
            segments: vec!["model_auto_compact_token_limit".to_string()],
            value: toml_edit::value(limit),
        });
    }
}
```

在 `sync_config_toml_to_provider_settings()` 中回读：

```rust
let auto_compact_token_limit = doc
    .get("model_auto_compact_token_limit")
    .and_then(|v| v.as_integer());
```

- [ ] **Step 4: 在 ArkTS provider 模型与设置页接线**

新增字段：

```ts
export class ProviderRecord {
  ...
  autoCompactTokenLimit: number;
}
```

在 `ProviderConfigStore.ets` 写入：
```ts
if (def.autoCompactTokenLimit > 0) {
  result += `auto_compact_token_limit = ${def.autoCompactTokenLimit}\n`;
}
```

在 `AddProviderPage.ets` 增加一个数值输入：
- 标签：`Auto compact token limit`
- 占位：`例如：160000（留空表示不启用后端自动压缩）`

- [ ] **Step 5: 把 UI 自动压缩降级为 fallback**

在 `CodexBackend` / `Index` 中：
- 读取 active provider 的 `autoCompactTokenLimit`
- `backendAutoCompactEnabled = autoCompactTokenLimit > 0`
- 当该值为真时：
  - 不再由 UI 主动发起 `<20%` 自动压缩
  - 仅展示 token/context 与 compaction 结果
- 当该值为假时：
  - 使用 Task 3 的 fallback compaction policy

- [ ] **Step 6: 运行 Rust 测试并做配置链路手测**

Run:
```powershell
cargo test -p codex-ohos-host render_config_toml_writes_auto_compact_limit -- --nocapture
cargo test -p codex-ohos-host --lib
```

Manual check:
1. 在 AddProviderPage 设置 `Auto compact token limit = 160000`
2. 保存 provider
3. 检查 `codexHome/config.toml` 中出现 `model_auto_compact_token_limit = 160000`
4. 发起长会话，确认 compaction 由后端自动触发
5. 确认 UI 不再主动重复触发一次压缩

Expected:
- Rust 测试 PASS
- config 同步正确
- 后端 auto-compact 生效
- UI fallback 不重复触发

- [ ] **Step 7: 提交**

```powershell
git add codex-main/codex-rs/ohos-host/src/lib.rs Agent/entry/src/main/ets/backend/ConsoleModels.ets Agent/entry/src/main/ets/backend/ProviderConfigStore.ets Agent/entry/src/main/ets/backend/ProviderCatalogService.ets Agent/entry/src/main/ets/apim/ApiManagementService.ets Agent/entry/src/main/ets/apim/ApiManagementViewModel.ets Agent/entry/src/main/ets/pages/AddProviderPage.ets Agent/entry/src/main/ets/backend/CodexBackend.ets Agent/entry/src/main/ets/pages/Index.ets
git commit -m @'
feat: expose backend auto compaction limit in provider settings
'@
```

---

## 风险与规避

### 1. `turn_events` 与 `turn_poll` 状态漂移

**风险：** 增量事件 reducer 漏掉某一类通知，导致 UI 状态与权威快照不一致。

**规避：**
- 保留 `turn_poll` heartbeat
- terminal 阶段必须执行一次权威 `turn_poll`
- `turn_events` 只做加速，不做唯一真相源

### 2. 自动压缩重复触发

**风险：** 后端 auto-compact 与 UI fallback 同时触发。

**规避：**
- provider 配置里只要 `autoCompactTokenLimit > 0`，UI 自动压缩一律禁用
- `lastCompactionTurnId` + cooldown 双保险

### 3. 历史 token snapshot 过期

**风险：** 本地 snapshot 与最新 thread 实际状态不一致。

**规避：**
- `thread/read` 优先使用内存 snapshot，次优先使用落盘 snapshot
- 一旦收到新的 `ThreadTokenUsageUpdated`，立刻覆盖旧值
- thread archive 时删除 snapshot

### 4. 内存清理过早导致 diff/token 丢失

**风险：** terminal turn 过早清理，最终 diff 或 token drain 失败。

**规避：**
- cleanup 仅在 `drainLateTurnUpdates()` / `drainCompactionTokenUsage()` 完成后进行
- 先把 token usage 同步到 thread snapshot，再删 turn state

---

## 验证矩阵

### 自动化验证

- `cargo test -p codex-ohos-host --lib`
- 针对新增测试名跑 targeted tests：
  - `resolve_thread_token_usage_prefers_thread_snapshot_when_turn_state_is_missing`
  - `thread_context_snapshot_round_trips`
  - `cleanup_terminal_turn_keeps_thread_snapshot_and_removes_turn_state`
  - `turn_events_drains_queue_once`
  - `render_config_toml_writes_auto_compact_limit`

### 手动验证

1. **历史会话恢复**
   - 重启 app
   - 打开旧 thread
   - context 条立即显示，不用先发送新消息

2. **active turn 期间自动压缩保护**
   - 发起长 turn
   - 在 turn 完成前确认没有压缩请求

3. **长会话事件流**
   - 观察 UI 更新连续性
   - 观察日志不再输出整包 poll payload

4. **内存/缓存**
   - 多轮对话后切换会话
   - 确认 inactive turn state 不无限累积

5. **后端 auto-compact**
   - provider 配置 limit
   - 确认 core 自动触发压缩，UI 不重复触发

---

## 实施顺序建议

1. **Task 1**：thread 级 token snapshot（必须先做）
2. **Task 2**：snapshot 落盘 + terminal cleanup（保证恢复与内存稳定）
3. **Task 3**：deterministic compaction policy（先止损）
4. **Task 4**：`turn_events` 增量流（主要性能收益）
5. **Task 5**：后端 auto-compact 接管（最终形态）

这个顺序的原因是：
- Task 1-3 就能修掉“恢复不准、压缩乱触发”的 correctness 问题
- Task 4 再解决传输与性能
- Task 5 最后切主路径，避免把策略迁移和传输改造混在一起调试

---

## 完成标准

以下条件全部满足时，这个计划可视为完成：

- 历史会话恢复后，context 条与 tokenUsage 立即可用
- active turn 期间不会触发自动压缩
- UI 自动压缩不会与后端 auto-compact 重复触发
- 长会话不再依赖 200ms 全量 snapshot 更新 UI
- terminal turn state 会被回收，但 thread 上下文状态不会丢
- provider 配置能够读写 `model_auto_compact_token_limit`

---

Plan complete and saved to `docs/superpowers/plans/2026-05-13-context-management-compaction.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
