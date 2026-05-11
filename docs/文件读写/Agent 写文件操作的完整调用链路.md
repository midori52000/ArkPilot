# Agent 写文件操作完整调用链路

本文档描述 Agent 执行写文件操作时的完整调用链路，从用户输入到 UI 渲染。

---

## 整体架构图

```
用户输入
  → ArkTS UI (Index.ets)
    → CodexBackend.ets (业务层: startTurn)
      → CodexNative.ets (Native 桥接)
        → napi_init.cpp (NAPI 层)
          → libcodex_ohos_host.so (Rust FFI)
            → app-server (请求分发)
              → codex-core (LLM 交互 + 工具调度)
                → apply-patch crate (实际文件写入)
```

---

## 阶段 1：用户发起请求 → Rust 后端启动 Turn

1. **Index.ets** 用户输入消息，调用 `CodexBackend.startTurn()`
2. **CodexBackend.ets:1623** `startTurn()` 调用 `turnStartAsyncNative()` 发起新 turn
3. **CodexNative.ets** → **napi_init.cpp** → `codex_ohos_host_turn_start()` FFI 调用
4. **lib.rs:2348** 中通过 `RemoteAppServerClient` 向 app-server 发送 `TurnStart` 请求
5. app-server 将用户消息发送给 codex-core，codex-core 调用 LLM

---

## 阶段 2：LLM 决定写文件 → 生成 apply_patch 工具调用

6. **codex-core** 中 LLM 返回包含 `apply_patch` 工具调用的响应
7. **codex-core/apply_patch.rs** `apply_patch()` 函数被调用：
   - 调用 `assess_patch_safety()` 评估补丁安全性
   - `SafetyCheck::AutoApprove` → 自动批准，直接执行
   - `SafetyCheck::AskUser` → 需要用户审批
   - `SafetyCheck::Reject` → 拒绝执行

---

## 阶段 3：安全评估 → 审批流程（如需要）

8. **app-server** 处理 `ApplyPatchApprovalRequest` 事件：
   - 创建 `ThreadItem::FileChange { status: InProgress }`
   - 发送 `FileChangeRequestApproval` 请求

9. **lib.rs:2603** 在 ohos-host 中接收审批请求：
   - `codex_ohos_host_approval_poll()` → 返回 `pending_approval` 的 JSON
   - `codex_ohos_host_approval_approve()` → 批准请求
   - `codex_ohos_host_approval_decline()` → 拒绝请求

10. **CodexBackend.ets:2278-2312** 审批轮询：
    - `ensureApprovalPolling()` 启动定时器，每 1000ms 调用 `pollPendingApproval()`
    - `pollPendingApproval()` 调用 `approvalPollNative()` 获取待审批请求
    - 解析返回的 JSON，区分 `requestUserInput` 和普通审批请求
    - 设置 `this.pendingApproval` 或 `this.pendingRequestUserInput`

11. **Index.ets** 显示审批弹窗，用户点击"批准"

12. **CodexBackend.ets:1396-1409** `approvePendingRequest()`：
    - 构建 `ApprovalActionRequestPayload`
    - 调用 `approvalApproveNative(JSON.stringify(approveRequest))`
    - 回传审批结果给 app-server

---

## 阶段 4：审批通过 → 实际写文件

13. **app-server** 接收审批结果：
    - 如果批准：调用 `codex.submit(Op::PatchApproval { decision: Approved })`

14. **apply-patch crate** 执行实际文件写入：
    - `Hunk::AddFile` → `std::fs::create_dir_all()` + `std::fs::write(path, contents)`
    - `Hunk::DeleteFile` → `std::fs::remove_file(path)`
    - `Hunk::UpdateFile` → `derive_new_contents_from_chunks()` 计算新内容 → `std::fs::write(path, new_contents)`

15. **app-server** 收到 `EventMsg::PatchApplyEnd`：
    - 更新 `ThreadItem::FileChange { status: Completed }`

---

## 阶段 5：Rust → ArkTS 消息传递

16. **CodexBackend.ets:2676-2728** `pollTurnUntilCompleted()` 轮询机制：
    - **事件轮询**：每 200ms 调用 `turnEventsNative()` 获取实时事件
    - **心跳轮询**：每 500ms 调用 `turnPollAsyncNative()` 获取完整状态
    - 使用 `deadline` 机制防止无限轮询（超时 5 分钟）

17. **lib.rs:2470** `codex_ohos_host_turn_events()`：
    - 调用 `process_pending_events()` 处理待处理事件
    - 返回 `NativeTurnEvent` 数组，包含多种事件类型：
      - `Status` — 状态变更
      - `SummaryLine` — 摘要行
      - `MessageSnapshot` — 消息快照
      - `DiffSnapshot` — Diff 快照
      - `TokenUsage` — Token 使用量

18. **lib.rs:2500** `codex_ohos_host_turn_poll()`：
    - 调用 `build_turn_poll_payload()` 构建轮询响应
    - 返回包含 `messages`、`diff`、`status`、`summary` 等字段的 JSON

19. **lib.rs:4868** `build_turn_poll_payload()` 组装 JSON：
    - `messages`：包含所有 `NativeMessage`（包括 `role: "file"` 的文件变更消息）
    - `diff`：unified diff 文本
    - `status`：turn 状态
    - `summaryTitle`：摘要标题
    - `summary`：摘要点列表
    - `tokenUsage`：Token 使用统计

20. **lib.rs:366** `NativeMessage` 结构：
    ```rust
    NativeMessage {
        message_id: String,
        author: String,
        role: String,        // "file" 表示文件变更
        content: String,
        timestamp: String,
        item_type: Option<String>,  // Some("file")
        status: Option<String>,     // Some("completed")
        metadata: Option<Value>,    // 包含文件列表等
    }
    ```

---

## 阶段 6：ArkTS 解析 → UI 渲染紫色卡片

21. **CodexBackend.ets:2850-2903** `applyTurnEventBatch()` 处理事件批次：
    - `kind === 'status'` → 更新 `thread.lastTurnStatus`
    - `kind === 'summaryLine'` → 追加到 `thread.summaryPoints`
    - `kind === 'messageSnapshot'` → 合并到 `thread.messages`
    - `kind === 'diffSnapshot'` → 更新 `thread.diffLines` 和 `thread.diffStat`
    - `kind === 'tokenUsage'` → 更新 Token 使用统计

22. **CodexBackend.ets:2905-2967** `applyTurnPollResult()`：
    - 解析 `messages` 数组，每条消息提取 `role`、`itemType`、`status`、`metadata`
    - 解析 `diff` 字段，调用 `parseUnifiedDiff()` 生成 `CodexDiffLine[]`
    - 更新 `thread.changedFiles`、`thread.diffStat`

23. **Index.ets:5728-5818** `messageEventBlock()` 渲染紫色卡片：
    - `item.itemType === 'file'` 时触发文件卡片渲染
    - **颜色**：`accentBorderColor('file')` → `#A855F7`（紫色）
    - **背景**：`eventSoftBackground('file')` → `#F5F3FF`（浅紫）
    - **边框**：`eventBorderColor('file')` → `#DDD6FE`（浅紫边框）
    - **图标**：`messageIcon('file')` → `📄`
    - **标题**：`operationLabel('file')` → `文件`
    - **内容**：显示 `item.content`（即文件变更描述）

---

## 关键数据结构流转

| 层级 | 数据结构 | 关键字段 |
|------|----------|----------|
| **Rust 协议层** | `ThreadItem::FileChange` | `changes: Vec<FileUpdateChange>`, `status: PatchApplyStatus` |
| **Rust FFI 层** | `NativeMessage` | `role: "file"`, `item_type: "file"`, `content`, `metadata` |
| **Rust 事件层** | `NativeTurnEvent` | `MessageSnapshot { messages }`, `DiffSnapshot { diff }` |
| **ArkTS 业务层** | `CodexChatMessage` | `role`, `itemType`, `status`, `metadata` |
| **ArkTS UI 层** | `ChatMessage` | `itemType`, `status`, `metadata` |

---

## 两条写文件路径的区别

| 路径 | 触发场景 | 写入目标 | 链路 |
|------|----------|----------|------|
| **apply_patch** | Agent 修改用户代码文件 | 用户工作区任意文件 | LLM → codex-core → apply-patch crate → `std::fs::write` |
| **codex_ohos_host_*** | 配置管理（Provider/Skills/Prompts/MCP/AGENTS.md） | `codexHome` 下的配置文件 | ArkTS → NAPI → Rust FFI → `std::fs::write` |

紫色卡片对应的是 **apply_patch 路径**，即 Agent 修改用户代码文件时的完整链路。

---

## 轮询机制详解

### 双轨轮询

| 轮询类型 | 函数 | 间隔 | 用途 |
|----------|------|------|------|
| **事件轮询** | `turnEventsNative()` | 200ms | 获取实时事件流（状态、消息、Diff） |
| **心跳轮询** | `turnPollAsyncNative()` | 500ms | 获取完整状态快照（兜底） |
| **审批轮询** | `approvalPollNative()` | 1000ms | 检查待审批请求 |

### 事件类型

| 事件类型 | 说明 | 处理逻辑 |
|----------|------|----------|
| `status` | Turn 状态变更 | 更新 `thread.lastTurnStatus` |
| `summaryLine` | 摘要行 | 追加到 `thread.summaryPoints` |
| `messageSnapshot` | 消息快照 | 合并到 `thread.messages` |
| `diffSnapshot` | Diff 快照 | 更新 `thread.diffLines` |
| `tokenUsage` | Token 使用量 | 更新 `thread.tokenUsage` |

---

## 关键常量

```typescript
// CodexBackend.ets
const TURN_POLL_INTERVAL_MS = 200;           // 事件轮询间隔
const TURN_POLL_HEARTBEAT_INTERVAL_MS = 500; // 心跳轮询间隔
const TURN_POLL_TIMEOUT_MS = 300000;         // 轮询超时（5 分钟）
const APPROVAL_POLL_INTERVAL_MS = 1000;      // 审批轮询间隔
const TERMINAL_TURN_DRAIN_ATTEMPTS = 3;      // 终态排空尝试次数
const TERMINAL_TURN_DRAIN_INTERVAL_MS = 250; // 终态排空间隔
```

---

## UI 颜色配置

### 事件类型颜色映射

| 类型 | 主色 (`accentBorderColor`) | 背景 (`eventSoftBackground`) | 边框 (`eventBorderColor`) | 图标 | 标签 |
|------|---------------------------|------------------------------|---------------------------|------|------|
| `file` | `#A855F7` | `#F5F3FF` | `#DDD6FE` | `📄` | 文件 |
| `command` | `#10B981` | `#ECFDF5` | `#A7F3D0` | `⚡` | 命令 |
| `tool` | `#3B82F6` | `#EFF6FF` | `#BFDBFE` | `🔧` | 工具 |
| `reasoning` | `#F59E0B` | `#FFFBEB` | `#FDE68A` | `🧠` | 思考 |
| `search` | `#14B8A6` | `#F0FDFA` | `#99F6E4` | `🔍` | 搜索 |
| `plan` | `#F97316` | `#FFF7ED` | `#FED7AA` | `📋` | 计划 |
| `image` | `#EC4899` | `#FDF2F8` | `#FBCFE8` | `🖼️` | 图片 |
| `hook` | `#EAB308` | `#FEFCE8` | `#FDE68A` | `🪝` | 钩子 |
| `review` | `#FACC15` | `#FEF9C3` | `#FACC15` | `👁️` | 审查 |
