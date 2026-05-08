# Skill 预览区启用状态即时刷新设计

## 背景

当前 Skills 管理界面中，左侧列表与右侧预览区都展示已安装 Skill 的启用状态。点击右侧预览区的“启用/禁用”按钮后，后端切换流程可以成功执行，但右侧预览区的按钮文案与状态标签不会立即更新，导致界面反馈滞后。

## 目标

- 点击右侧预览区的启用状态按钮后，界面立即切换到目标状态。
- 如果后端切换失败，界面回滚到原状态，并给出错误提示。
- 保持现有后端调用链路与页面结构不变。
- 采用最小化改动，仅修复 Skills 预览区状态同步问题。

## 现状分析

`SettingsPage.ets` 中已安装 Skill 列表使用 `installedSkills` 渲染，右侧预览区使用 `selectedSkillDetail` 渲染。当前 `toggleSkillEnabled()` 已对 `skillsVM.state.installed` 做乐观更新，再通过 `syncSkillsStateFromViewModel()` 回填本地状态。

问题在于：右侧预览区依赖独立的 `selectedSkillDetail` 对象引用。即使列表数据已经更新，预览区使用的选中对象也可能没有在同一时刻同步到最新启用状态，因此出现“后端成功但前端反馈不及时”的现象。

## 方案对比

### 方案 A：在切换时同步更新 `selectedSkillDetail`（推荐）

在 `toggleSkillEnabled()` 中，除了更新 `skillsVM.state.installed`，还同步更新当前选中的 `selectedSkillDetail.enabled`。后端成功后继续以返回结果覆盖；后端失败时回滚选中项状态。

优点：
- 改动最小。
- 不改变现有页面结构与状态模型。
- 能直接满足“点下即切换”的交互要求。

代价：
- 页面仍然维护列表状态与选中态两份引用，需要继续保持同步。

### 方案 B：只保存 `selectedSkillId`

将右侧预览区改为通过 `selectedSkillId` 从 `installedSkills` 中实时查找当前 Skill，不再直接保存 `selectedSkillDetail` 对象。

优点：
- 状态源单一，更稳定。

代价：
- 需要调整预览区和弹窗中多处读取逻辑。
- 超出本次“最小化改动”的范围。

### 方案 C：取消乐观更新，仅在后端成功后刷新

点击后等待后端返回，再刷新右侧预览区状态。

优点：
- 逻辑简单。

代价：
- 不符合“立即更新”的交互要求。
- 用户感知仍然偏慢。

## 最终设计

采用方案 A。

### 修改范围

仅修改：
- `Agent/entry/src/main/ets/pages/SettingsPage.ets`

不修改：
- `SkillsViewModel.ets`
- `SkillsBackendService.ets`
- Native / Rust 后端切换逻辑

### 具体做法

1. 在 `toggleSkillEnabled(skillId)` 中记录切换前状态。
2. 执行现有的乐观更新逻辑，更新 `skillsVM.state.installed`。
3. 若当前 `selectedSkillDetail` 的 `id` 与 `skillId` 相同，则立即同步其 `enabled` 字段，让右侧预览区按钮、标签和样式同帧刷新。
4. 调用现有 `skillsVM.toggleEnabled(skillId, enabled)`。
5. 成功时继续执行现有同步逻辑，用 ViewModel 中的结果覆盖页面状态。
6. 失败时将 `skillsVM.state.installed` 与 `selectedSkillDetail` 一并回滚到切换前状态，再展示错误提示。

## 数据流

1. 用户点击右侧预览区“启用/禁用”按钮。
2. `SettingsPage.toggleSkillEnabled()` 计算目标状态。
3. 页面本地状态立即切换：
   - `skillsVM.state.installed`
   - `installedSkills`
   - `selectedSkillDetail`（若当前选中）
4. 页面立即重绘右侧预览区。
5. 后端异步执行真实切换。
6. 成功则保留新状态；失败则恢复旧状态并提示。

## 错误处理

- 若找不到目标 Skill，直接返回，不新增额外分支。
- 若后端切换失败，必须回滚：
  - 左侧列表状态
  - 右侧预览区状态
- 继续复用现有 `skillsStatusText` 与 `triggerFeedback()` 提示机制，不新增 UI 元素。

## 测试与验收

### 手动验收

1. 进入 Skills 管理界面，选择一个已安装 Skill。
2. 点击右侧预览区启用状态按钮。
3. 验证按钮文案、状态 pill、边框颜色立即变化。
4. 验证左侧列表状态与右侧预览区保持一致。
5. 再次点击切回，验证状态仍立即变化。
6. 若制造后端失败场景，验证左右两侧状态都会回滚，并出现错误提示。

### 回归关注点

- 左侧列表中的“打开”与“删除”行为不受影响。
- Skill 详情弹窗中的状态展示不应被破坏。
- 从列表切换选中项后，右侧预览区仍显示正确状态。

## 实施原则

- 最小化改动。
- 不重构状态模型。
- 不新增抽象层。
- 只修复本次前端反馈不及时的问题。
