# OpenHarmony Codex Agent Workspace

- `ARCHITECTURE_zh.md`
  - detailed software architecture and build pipeline for this workspace

> Current workspace note: for the HarmonyOS build flow, the required upstream
> source is `codex-main/codex-rs/`. The rest of the original `codex-main`
> top-level tree has been trimmed away.

这个仓库的目标不是单独发布上游 `codex-main`，而是把真实的 `codex-rs app-server` 嵌入到鸿蒙桌面应用里。

仓库包含两部分：

- `Agent/`
  - 鸿蒙应用工程
  - 包含 ArkTS 前端、N-API 桥接、native 构建和应用内启动逻辑
- `codex-main/`
  - 上游 Codex 源码镜像
  - 真实后端位于 `codex-main/codex-rs/`

这份 README 重点解决一件事：

- 别人在新机器上 clone 仓库后，如何按仓库内脚本直接编出 `debug HAP`

## 当前默认支持

当前仓库默认支持：

- fresh clone 后在 Windows 上构建 `unsigned debug HAP`
- 不依赖提交者本机固定的 Cargo 路径
- 不依赖提交者本机固定的 DevEco SDK 路径
- 不依赖提交者本机私有的签名材料路径

默认输出：

- `Agent\entry\build\default\outputs\default\entry-default-unsigned.hap`

## 前置环境

新机器至少需要：

1. Windows
2. DevEco Studio，并安装 HarmonyOS/OpenHarmony SDK
3. Rust 与 `rustup`
4. Git
5. 能访问 `ohpm` 和 Rust target 下载源

建议工具链：

- DevEco Studio 默认安装目录，或手动设置 `DEVECO_SDK_HOME`
- Rust `1.93.x`

## clone 后如何构建 debug HAP

### 1. clone 仓库

仓库已经包含：

- `Agent/`
- `codex-main/`

不需要额外再下载 `codex-main`。

### 2. 运行项目内初始化脚本

在仓库根目录执行：

```bat
Agent\script\helpsetup\setup_env.bat
```

这个脚本会：

- 自动定位 `Agent` 工程根目录
- 自动定位 DevEco SDK
- 生成 `Agent\local.properties`
- 如果缺少 `oh_modules`，自动运行 `ohpm install --all`
- 确保 Rust OHOS targets 已安装
- 清理 stale hvigor user cache
- 停掉 hvigor daemon，避免旧 SDK 路径缓存

### 3. 构建 debug HAP

```bat
Agent\script\helpsetup\build.bat debug
```

默认输出：

```text
Agent\entry\build\default\outputs\default\entry-default-unsigned.hap
```

### 4. 清理构建产物

```bat
Agent\script\helpsetup\build.bat clean
```

## 如果 DevEco 不在默认目录

如果 DevEco Studio SDK 不在默认路径，先设置：

```powershell
$env:DEVECO_SDK_HOME='D:\path\to\DevEco Studio\sdk'
```

然后再运行：

```bat
Agent\script\helpsetup\build.bat debug
```

当前脚本会优先读取 `DEVECO_SDK_HOME`。

## 在 DevEco 里打开工程

应当打开：

- `OpenHarmony\Agent`

不要把整个 `OpenHarmony` 根目录直接当成 DevEco 工程打开。

## 为可移植构建做了哪些调整

### 1. native Rust 构建脚本不再绑定提交者电脑

已修正：

- `libcodexhost-builder/native/build_codex_ohos_host.cmd`

现在它会：

- 自动查找 `cargo`
- 优先读取 `DEVECO_SDK_HOME`
- 自动设置 `OHOS_NDK_HOME` / `OHOS_SDK_NATIVE` / `SDK_NATIVE`
- 同时导出 hyphen 和 underscore 两套 target-specific CMake 变量
- 清掉会污染宿主依赖构建的全局 `CC / AR / RANLIB`
- 正确使用 `CARGO_TARGET_DIR`

### 2. Rust toolchain wrapper 不再写死 SDK 根目录

已修正：

- `codex-main/codex-rs/toolchains/ohos-aarch64-clang.cmd`
- `codex-main/codex-rs/toolchains/ohos-aarch64-clangxx.cmd`
- `codex-main/codex-rs/toolchains/ohos-x86_64-clang.cmd`
- `codex-main/codex-rs/toolchains/ohos-x86_64-clangxx.cmd`

这些包装器现在会优先读取：

- `OHOS_NATIVE`
- `OHOS_SDK_NATIVE`
- `OHOS_NDK_HOME`
- `SDK_NATIVE`
- `DEVECO_SDK_HOME`

只有都不存在时，才回退到默认安装路径。

### 3. helper scripts 已正式纳入项目

仓库正式包含：

- `Agent/script/helpsetup/setup_env.bat`
- `Agent/script/helpsetup/build.bat`
- `Agent/script/helpsetup/README.md`

不再依赖本地未提交的“编译不成功的日志”目录。

这些脚本现在默认走 DevEco 的 `hvigorw.bat` wrapper，而不是直接调用内部 `hvigor.js`。

### 4. debug HAP 不再依赖提交者本机签名材料

已调整：

- `Agent/build-profile.json5`

仓库默认不再提交本机私有的：

- `.cer`
- `.p12`
- `.p7b`

也不再把默认产品绑定到某台机器 `C:\Users\...\ .ohos\config\...` 的签名配置。

这意味着 fresh clone 后，别人可以先稳定产出：

- `unsigned debug HAP`

而不是一上来就卡在签名路径不存在。

## 当前默认不解决的事情

下面这些仍然是每台机器自己的本地配置：

- 本机签名证书
- 本机 `.p12/.p7b/.cer`
- DevEco Studio 自己的 IDE 配置
- 模拟器 / 真机运行配置

如果你需要：

- 签名包
- `Build APP(s)`
- DevEco 里直接安装运行带签名的包

那就需要在每台机器上单独配置本地签名。

## 常用命令

初始化：

```bat
Agent\script\helpsetup\setup_env.bat
```

构建 debug HAP：

```bat
Agent\script\helpsetup\build.bat debug
```

清理构建产物：

```bat
Agent\script\helpsetup\build.bat clean
```

## 已知边界

- 当前 helper script 重点保证的是 `debug HAP`，不是签名发布包
- 如果 DevEco SDK 被移动过，建议重新运行 `setup_env.bat`
- 如果 `ohpm` 或 Rust target 下载失败，需要先解决本机网络或镜像源问题
- 仓库里仍然可能有你的本地开发改动，例如 `Agent/entry/build-profile.json5` 的 ABI 切换

## 相关文件

- `Agent/script/helpsetup/README.md`
- `libcodexhost-builder/native/build_codex_ohos_host.cmd`
- `Agent/build-profile.json5`
- `codex-main/codex-rs/toolchains/`
