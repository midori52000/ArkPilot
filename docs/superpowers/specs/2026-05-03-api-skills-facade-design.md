# API / Skills 统一 façade 前端收口设计

日期：2026-05-03

## 1. 背景

当前仓库已经同时存在：

- 独立的 `SettingsPage.ets` 前端 mock 控制台
- 真实持久化倾向较强的 API 管理路径
- 仍然包含正式目录写入职责的 Skills 路径

这导致页面层虽然都在做“配置管理”，但调用语义、错误表达和状态边界并不统一。

本轮目标不是接通真实后端，也不是完成统一 registry ABI，而是先完成前端层面的 A1 + A2 + A4：

1. 定义统一配置管理 façade contract
2. 让 API 页面接入统一 façade
3. 让 Skills 页面接入统一 façade

## 2. 本轮范围

### 2.1 In scope

- 仅收口 `provider` 与 `skill` 两类对象
- 新增统一 `ConfigKind` / `action` / `result` 结构
- 在 ArkTS 层提供统一 façade 入口
- `ApiManagementPage.ets`、`ApiManagementViewModel.ets` 改为只通过 façade 操作
- `SkillsViewModel.ets` 改为只通过 façade 操作
- 保留前端先行语义：按压缩放、轻粒子反馈、自动消散提示
- 未接入真实后端的动作明确提示“当前仅前端模拟”

### 2.2 Out of scope

- 不改 Rust host
- 不改 NAPI ABI
- 不改 Prompt / MCP 页面主逻辑
- 不把本轮新入口直接接到真实持久化写入
- 不删除现有 provider / skills 的旧 service 能力

## 3. 设计目标

1. 页面与 ViewModel 统一只认 façade，不再直连对象特化保存细节。
2. 统一动作语义：`list/get/add/update/remove/enable/disable/setActive`。
3. 统一返回结构：`{ ok, data, error }`。
4. 维持“纯前端先行”的当前节奏，不让本轮实现反向绑定真实后端。
5. 为后续阶段 B/C/D 预留稳定替换点：将来优先替换 façade 内部 action 实现，而不是重写页面结构。

## 4. 总体方案

本轮采用“薄 façade + 兼容 adapter”方案。

- `CodexBackend.ets` 新增统一 façade 定义与分发入口。
- façade 只统一上层管理语义，不强行统一 provider 与 skill 的底层数据结构。
- façade 本轮默认工作在 **mock-first** 模式：新页面路径通过 façade 操作前端态，不直接落真实后端写入。
- 现有 `ApiManagementService.ets` 与 `SkillsBackendService.ets` 保留为 legacy adapter / 兼容实现，不再作为页面主入口。

这意味着本轮统一的是“入口”和“返回口径”，不是一次性统一所有底层实现。

## 5. façade contract

### 5.1 ConfigKind

```ts
export type ConfigKind = 'provider' | 'skill';
```

### 5.2 通用 action 语义

```ts
export type ConfigAction =
  | 'list'
  | 'get'
  | 'add'
  | 'update'
  | 'remove'
  | 'enable'
  | 'disable'
  | 'setActive';
```

### 5.3 通用返回结构

```ts
export interface ConfigActionResult<T = Object> {
  ok: boolean;
  data: T | null;
  error: ConfigActionError | null;
}

export interface ConfigActionError {
  code: string;
  message: string;
  details?: string;
}
```

### 5.4 请求结构

```ts
export interface ConfigActionRequest {
  kind: ConfigKind;
  action: ConfigAction;
  id?: string;
  scope?: string;
  payload?: Object;
}
```

说明：

- `provider` 直接使用统一 action。
- `skill` 仍保留 installed / repos / backups 等集合差异，使用 `scope` 区分，而不是本轮拆成多个新 kind。

## 6. 文件职责

### 6.1 `Agent/entry/src/main/ets/backend/CodexBackend.ets`

新增：

- `ConfigKind`
- `ConfigAction`
- `ConfigActionRequest`
- `ConfigActionResult`
- `ConfigManagerFacade`
- façade dispatcher
- provider / skill mock store 或 façade state holder

职责：

- 接收统一 request
- 按 kind 分发到 provider / skill adapter
- 把对象特化异常整理成统一错误结构
- 对页面暴露稳定 façade API

不承担：

- Rust host 正式持久化
- NAPI ABI 设计
- 复杂业务文件系统操作

### 6.2 `Agent/entry/src/main/ets/backend/CodexNative.ets`

本轮原则：

- 不新增统一 native ABI
- 保留现有 provider / skills 相关 native 能力
- 继续作为 legacy 能力来源，不再让页面直接依赖其细节

### 6.3 `Agent/entry/src/main/ets/apim/ApiManagementService.ets`

改造方向：

- 从页面主 service 调整为 provider adapter / legacy capability wrapper
- 现有 provider 校验、转换、异常说明逻辑保留
- 不再作为页面直接入口暴露给 ViewModel

### 6.4 `Agent/entry/src/main/ets/skills/SkillsBackendService.ets`

改造方向：

- 从页面主 service 调整为 skill adapter / legacy capability wrapper
- 目录写入、备份、卸载、更新等旧能力保留在兼容层
- 本轮显式标记这些正式目录写入边界，不让新页面主路径直接依赖

## 7. 页面与 ViewModel 改造方式

### 7.1 API 路径

涉及文件：

- `Agent/entry/src/main/ets/pages/ApiManagementPage.ets`
- `Agent/entry/src/main/ets/apim/ApiManagementViewModel.ets`
- `Agent/entry/src/main/ets/apim/ApiManagementService.ets`

改造后：

- `loadProviders()` → façade `list(kind='provider')`
- `saveEditing()` → façade `add/update(kind='provider')`
- `activateProvider()` → façade `setActive(kind='provider')`
- `deleteProvider()` → façade `remove(kind='provider')`

本轮特殊处理：

- `validateProvider()`
- `testSpeed()`
- `discoverModels()`
- `queryUsage()`

这些动作不属于统一 registry CRUD，本轮先统一走 mock/pending 提示，不重新回绑真实网络与真实持久化语义。

### 7.2 Skills 路径

涉及文件：

- `Agent/entry/src/main/ets/skills/SkillsViewModel.ets`
- `Agent/entry/src/main/ets/skills/SkillsBackendService.ets`

改造后：

- `loadInstalled()` → façade `list(kind='skill', scope='installed')`
- `toggleEnabled()` → façade `enable/disable(kind='skill', scope='installed')`
- `uninstall()` → façade `remove(kind='skill', scope='installed')`
- `loadRepos()` / `addRepo()` / `removeRepo()` → façade `list/add/remove(kind='skill', scope='repos')`
- `loadBackups()` / `deleteBackup()` → façade `list/remove(kind='skill', scope='backups')`

本轮特殊处理：

- `installFromGithub()`
- `updateSkill()`
- `restoreBackup()`
- `importFromLocal()`
- `scanUnmanaged()`
- `loadDiscoverable()`
- `searchSkillsSh()`

这些动作仍保留对象特化概念，但页面统一只通过 façade 发起；若尚未切到前端 mock 版本，则返回 `MOCK_ONLY` 或 `NOT_IMPLEMENTED`。

## 8. 错误语义

本轮先统一到页面可消费的最小错误集：

- `NOT_FOUND`
- `INVALID_DRAFT`
- `MOCK_ONLY`
- `NOT_IMPLEMENTED`
- `DIRECTORY_CONFLICT`
- `SYNC_FAILED`

要求：

- 页面只消费统一 result，不再解析对象特化异常格式
- 所有未接入真实后端的动作必须显式返回可提示错误，不允许静默失败
- `SettingsPage.ets` 现有“当前仅前端模拟”提示语义继续沿用

## 9. 兼容策略

本轮兼容原则：

1. 旧 provider / skills service 不删除。
2. 旧真实能力保留在 adapter 层备用。
3. 新页面路径默认通过 mock façade 工作。
4. 后续若接真实后端，优先替换 façade 内部 action 实现，不推翻页面结构与视觉层级。

这保证了当前前端先行约束与未来真实接入路径不冲突。

## 10. 验收标准

本轮完成后，应满足：

1. `ApiManagementPage.ets` 与 `SkillsViewModel.ets` 的主操作统一通过 façade 发起。
2. 页面层不再直接依赖 provider catalog / skills registry 的保存细节。
3. 所有主 CTA 都保留按压缩放、轻反馈和自动消散提示。
4. 未接后端动作明确提示为前端模拟。
5. Prompt / MCP 不纳入本轮改造，且无回归。

## 11. 实施顺序

推荐按以下顺序落地：

1. 在 `CodexBackend.ets` 定义 façade contract 与 provider / skill dispatcher
2. 先接 `ApiManagementViewModel.ets` 与 `ApiManagementPage.ets`
3. 再接 `SkillsViewModel.ets`
4. 把 `ApiManagementService.ets` / `SkillsBackendService.ets` 调整为 adapter 角色
5. 回归 `SettingsPage.ets` 的提示语义与交互一致性

## 12. 风险与控制

### 风险 1：API 页面已有真实保存路径，与本轮 mock-first 目标冲突

控制：

- 新入口只走 façade
- legacy service 保留但不作为页面主入口

### 风险 2：Skills 业务面过宽，容易把 discover / update / backup / repo 一次性做深

控制：

- 本轮只统一入口和返回口径
- 复杂动作允许先返回 `MOCK_ONLY` / `NOT_IMPLEMENTED`

### 风险 3：后续真实接入时再次推翻页面结构

控制：

- 从现在开始固定 façade 边界
- 后续只替换 action 实现，不重写页面结构

## 13. 结论

本轮 API / Skills 收口的关键，不是立刻打通真实统一持久化，而是先把 ArkTS 前端稳定到统一 façade 语义上。

这样既符合当前“纯前端设计、后端接口预留”的节奏，也为后续阶段 B/C/D 的 backend、bridge、host 收敛提供稳定替换点。