结论：你这次 `apply_patch` 失败的第一根因不是 patch 语法，而是 **OHOS 进程内执行 apply_patch 时没有切到工作目录 `cwd`**。另外，你的工作区路径如果来自 `DocumentViewPicker` 的 `/storage/Users/currentUser/...`，后续还可能踩到 HarmonyOS 沙箱/URI 权限问题。

## 1. 直接根因：OHOS 分支忽略了 `req.action.cwd`

你的调用是：

```json
"name": "apply_patch",
"input": "*** Begin Patch\n*** Add File: hello_word.py\n+print(\"hello_word\")\n*** End Patch\n"
```

这里 `hello_word.py` 是相对路径。正常情况下应该写到当前 turn 的工作目录：

```text
/storage/Users/currentUser/appdata/el2/base/com.Arkpilot.agent/files/243/hello_word.py
```

但代码里 OHOS 分支是这样执行的：

- `codex-main/codex-rs/core/src/tools/runtimes/apply_patch.rs:219-223`

```rust
#[cfg(target_env = "ohos")]
{
    let _ = (attempt, ctx);
    return run_apply_patch_in_process(req);
}
```

- `codex-main/codex-rs/core/src/tools/runtimes/apply_patch.rs:243-249`

```rust
fn run_apply_patch_in_process(req: &ApplyPatchRequest) -> Result<ExecToolCallOutput, ToolError> {
    ...
    codex_apply_patch::apply_patch(&req.action.patch, &mut stdout, &mut stderr)
        .map_err(|err| ToolError::Rejected(format!("apply_patch failed: {err}")))?;
```

这里 **没有使用 `req.action.cwd`**，也没有 `set_current_dir()`。

对比非 OHOS 路径，正常会把 cwd 传给 sandbox command：

- `codex-main/codex-rs/core/src/tools/runtimes/apply_patch.rs:102-110`

```rust
SandboxCommand {
    ...
    cwd: req.action.cwd.clone(),
    ...
}
```

所以非 OHOS 下 `hello_word.py` 会相对 `req.action.cwd` 写入；OHOS 下会相对 **当前进程 cwd** 写入。HarmonyOS 应用进程的 cwd 很可能是 `/` 或其它不可写目录，于是 `std::fs::write("hello_word.py", ...)` 触发：

```text
Permission denied (os error 13)
```

这和你看到的错误完全吻合。

### `req.action.cwd` 是 **本次 `apply_patch` 应该相对执行的工作目录**，类型是 `PathBuf`。

在你的链路里，它通常就是 ArkTS 发起 turn 时传给 Rust 的 `cwd`，也就是当前会话绑定的 workspace root，例如你提到的：

```text
/storage/Users/currentUser/appdata/el2/base/com.Arkpilot.agent/files/243
```

#### 它怎么来的

大致链路是：

```text
ArkTS workspace.rootPath
→ turnStart 请求里的 cwd
→ ohos-host TurnStartParams.cwd
→ codex-core tool ctx cwd
→ maybe_parse_apply_patch_verified(argv, cwd)
→ ApplyPatchAction.cwd
→ ApplyPatchRequest.action.cwd
```

关键代码：

1. ArkTS 发起 turn 时设置 cwd：

`Agent/entry/src/main/ets/backend/CodexBackend.ets:1645`

```ts
turnRequest.cwd = workspace.rootPath.trim().length > 0 ? workspace.rootPath.trim() : undefined;
```

2. OHOS host 接收 turn/start 请求：

`codex-main/codex-rs/ohos-host/src/lib.rs:2365-2369`

```rust
let cwd = request
    .cwd
    .filter(|value| !value.trim().is_empty())
    .map(PathBuf::from);
params.cwd = cwd.clone();
```

3. `apply_patch` 识别阶段会用当前 turn 的 cwd 解析相对路径：

`codex-main/codex-rs/apply-patch/src/invocation.rs:132`

```rust
pub fn maybe_parse_apply_patch_verified(argv: &[String], cwd: &Path) -> MaybeApplyPatchVerified
```

然后生成 `effective_cwd`：

`codex-main/codex-rs/apply-patch/src/invocation.rs:152-162`

```rust
let effective_cwd = workdir
    .as_ref()
    .map(|dir| {
        let path = Path::new(dir);
        if path.is_absolute() {
            path.to_path_buf()
        } else {
            cwd.join(path)
        }
    })
    .unwrap_or_else(|| cwd.to_path_buf());
```

最后写进：

`codex-main/codex-rs/apply-patch/src/invocation.rs:207-211`

```rust
MaybeApplyPatchVerified::Body(ApplyPatchAction {
    changes,
    patch,
    cwd: effective_cwd,
})
```

所以：

- 如果工具调用只是 `apply_patch "*** Add File: hello_word.py ..."`，没有 `cd xxx && apply_patch`，那么 `req.action.cwd = turn 的 cwd`。
- 如果工具调用是 `cd subdir && apply_patch ...`，那么 `req.action.cwd = turn cwd/subdir`。
- 如果 `cd /absolute/path && apply_patch ...`，那么 `req.action.cwd = /absolute/path`。

#### 你的场景中它应该是什么

对于：

```patch
*** Begin Patch
*** Add File: hello_word.py
+print("hello_word")
*** End Patch
```

如果当前会话 workspace 是：

```text
/storage/Users/currentUser/appdata/el2/base/com.Arkpilot.agent/files/243
```

那么预期：

```text
req.action.cwd = /storage/Users/currentUser/appdata/el2/base/com.Arkpilot.agent/files/243
```

实际写入目标应是：

```text
/storage/Users/currentUser/appdata/el2/base/com.Arkpilot.agent/files/243/hello_word.py
```

之前失败就是因为 OHOS 执行阶段没有切到这个 `req.action.cwd`，导致 `hello_word.py` 被尝试写到进程当前目录。

## 2. 为什么审批/安全检查没发现？

因为解析阶段其实知道 cwd。

- `codex-main/codex-rs/apply-patch/src/invocation.rs:152-165`

```rust
let effective_cwd = workdir
    ...
    .unwrap_or_else(|| cwd.to_path_buf());

for hunk in hunks {
    let path = hunk.resolve_path(&effective_cwd);
```

- `codex-main/codex-rs/apply-patch/src/parser.rs:79-84`

```rust
pub fn resolve_path(&self, cwd: &Path) -> PathBuf {
    match self {
        Hunk::AddFile { path, .. } => cwd.join(path),
```

也就是说：**验证/审批阶段把 `hello_word.py` 解析成了 cwd 下的绝对路径，但真正执行阶段又拿原始 patch 文本重新解析并按进程 cwd 写文件**。

实际写文件发生在：

- `codex-main/codex-rs/apply-patch/src/lib.rs:289-298`

```rust
Hunk::AddFile { path, contents } => {
    ...
    std::fs::write(path, contents)
```

此时 `path` 仍是 patch 里的 `hello_word.py`，因为 OHOS 分支没有切 cwd。

## 3. 第二个潜在问题：`/storage/Users/currentUser/...` 可能不是应用内可直接写路径

你给的工作区是：

```text
/storage/Users/currentUser/appdata/el2/base/com.Arkpilot.agent/files/243/hello_word.py
```

HarmonyOS 文档里强调：

- 应用沙箱内，应用默认只能访问自己的应用文件和运行所需系统文件；
- 应用视角的沙箱路径和 hdc / 文件管理器看到的物理路径不同；
- 推荐用 `Context` 获取路径，不要手拼低层路径；
- 应用沙箱路径常见形式是 `/data/storage/el2/base/files/...`，物理路径会映射到 `/data/app/el2/<USERID>/base/<PACKAGENAME>/...`。

你项目里应用内项目目录的 fallback 是正确方向：

- `Agent/entry/src/main/ets/pages/Index.ets:1728-1742`

```ts
const basePath: string = `${context.filesDir}/codex-home/projects`;
...
fileIo.mkdirSync(candidatePath, true);
return candidatePath;
```

但目录选择器这里比较可疑：

- `Agent/entry/src/main/ets/pages/Index.ets:1760-1766`

```ts
const selectedUri: string = selectedUris[0];
const parsedUri = new uri.URI(selectedUri);
const candidatePath: string = decodeURIComponent(parsedUri.path ?? '');
...
return new WorkspaceDirectorySelection(candidatePath, selectedUri);
```

如果 `DocumentViewPicker` 返回的是 `file://docs/storage/Users/currentUser/...` 这类 URI，直接取 `parsedUri.path` 变成 `/storage/Users/currentUser/...`，再交给 Rust 当普通 POSIX 路径写，可能不具备普通 `std::fs::write` 权限。文档建议基于 URI 使用 File APIs，或者做权限持久化/激活，而不是把 URI path 当成裸路径随便传给 native 写。

## 4. 建议修复优先级

### 必修：修 OHOS `apply_patch` 不使用 cwd

最小修法是在 `run_apply_patch_in_process()` 内临时切换 cwd：

```rust
#[cfg(target_env = "ohos")]
fn run_apply_patch_in_process(req: &ApplyPatchRequest) -> Result<ExecToolCallOutput, ToolError> {
    let previous_cwd = std::env::current_dir()
        .map_err(|err| ToolError::Rejected(format!("failed to read current dir: {err}")))?;
    std::env::set_current_dir(&req.action.cwd)
        .map_err(|err| ToolError::Rejected(format!("failed to set apply_patch cwd to {}: {err}", req.action.cwd.display())))?;

    let result = {
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let apply_result = codex_apply_patch::apply_patch(&req.action.patch, &mut stdout, &mut stderr)
            .map_err(|err| ToolError::Rejected(format!("apply_patch failed: {err}")));

        (apply_result, stdout, stderr)
    };

    let restore_result = std::env::set_current_dir(previous_cwd);

    ...
}
```

但这有一个并发隐患：`current_dir` 是进程级全局状态。如果同进程里可能并发执行多个工具，最好不要用裸 `set_current_dir()`，而是：

1. 给 OHOS apply_patch 加一个全局 mutex，确保同一时刻只有一个 patch 修改 cwd；或
2. 更干净地在 `codex_apply_patch` crate 增加一个 `apply_patch_with_cwd(patch, cwd, stdout, stderr)`，解析后把每个 hunk 的路径解析成绝对路径再写，不改进程 cwd。

我更推荐第 2 个方案。

### 次修：不要把 Picker URI 的 path 直接当工作区路径

`Index.ets:1761-1766` 这段需要重新评估。对于应用内项目，优先使用 `context.filesDir` 得到的 `/data/storage/...` 沙箱路径；对于外部目录，应该保留 URI，并通过 HarmonyOS 文件访问框架/URI 权限来读写，而不是直接传 `/storage/Users/currentUser/...` 给 Rust `std::fs`。

### 立刻验证

你可以加日志验证：

1. 在 OHOS `run_apply_patch_in_process()` 打印：
   - `std::env::current_dir()`
   - `req.action.cwd`
   - `req.action.patch`

2. 再让模型创建 `hello_word.py`。

如果日志里 `current_dir` 不是你的工作区，而 `req.action.cwd` 是工作区，就能坐实这个根因。

## 5. 本次失败最可能的完整链路

```text
LLM 生成 Add File: hello_word.py
→ 解析/审批阶段按 cwd 认为目标是工作区/hello_word.py
→ OHOS 执行阶段 run_apply_patch_in_process()
→ 没有切到 req.action.cwd
→ codex_apply_patch::apply_patch() 按进程 cwd 写 hello_word.py
→ 进程 cwd 不可写
→ std::fs::write() 返回 Permission denied (os error 13)
```

Sources:
- [OpenHarmony Application Sandbox](https://raw.githubusercontent.com/openharmony-rs/openharmony-docs/master/en/application-dev/file-management/app-sandbox-directory.md)
- [HarmonyOS File URI APIs](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-fileuri)
- [Persisting Temporary Permissions](https://raw.githubusercontent.com/pablezhang/harmonyOS/master/en/application-dev/file-management/file-persistPermission.md)
- [Selecting User Files / Picker temporary permission](https://www.seaxiang.com/blog/383d9c558b174e54bbe693789677970c)