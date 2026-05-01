# OpenHarmony ArkPilot

这个仓库不是上游 `codex-main` 的完整分发，而是一个把 `codex-rs app-server`
嵌入到 OpenHarmony 图形应用里的工作区。当前工程已经稳定到下面这条链路：

- `Agent/`
  - 鸿蒙应用本体，负责 ArkTS UI、HAP 构建和最终打包
- `libcodexhost-builder/`
  - 独立 native builder，负责生成 `libcodexhost.so`
- `codex-main/codex-rs/`
  - 上游 Rust 工作区，提供真实的 `codex-ohos-host` 和 `app-server`

当前架构的关键点是：

- 主应用 `Agent` 不再内联编译 Rust/CMake
- `libcodexhost.so` 由 `libcodexhost-builder` 单独产出
- 第一阶段构建完成后会默认把 `.so` 自动拷贝到 `Agent`
- HAP 构建结束后会二次打包，把 `libcodexhost.so` 和 `libc++_shared.so` 注入最终包

## 当前目录边界

仓库里真正需要关注的是：

- `Agent/`
- `libcodexhost-builder/`
- `codex-main/codex-rs/`

目前已经明确不再依赖：

- `Agent/entry/src/main/cpp/` 旧的内联 Rust/CMake 构建链
- 上游 `codex-main` 顶层那些和鸿蒙构建无关的外围目录

## 现在的完整构建流程

### 1. 构建并安装 native so

```bat
libcodexhost-builder\build.bat debug x86_64
```

这一步会做这些事：

- 定位 `codex-main/codex-rs`
- 调用 CMake 配置 OHOS 工具链
- 调用 Cargo 交叉编译 `codex-ohos-host`
- 链接生成 `libcodexhost.so`
- 默认自动拷贝到：

```text
Agent\entry\src\main\libs\x86_64\libcodexhost.so
```

如果你只想构建、不想自动拷贝：

```bat
libcodexhost-builder\build.bat debug x86_64 --no-install
```

### 2. 构建 HAP

```bat
Agent\script\helpsetup\build.bat debug
```

这一步会做这些事：

- 自动定位 `Agent` 工程根目录
- 自动定位 DevEco SDK
- 自动生成 `Agent\local.properties`
- 缺依赖时执行 `ohpm install --all`
- 检查 `libcodexhost.so` 是否已经安装到 `Agent`
- 调用 `hvigor assembleHap`
- 构建结束后通过二次打包把 native 库重新注入 HAP

默认输出：

```text
Agent\entry\build\default\outputs\default\entry-default-unsigned.hap
```

## 运行时架构

应用启动后，链路是：

1. `EntryAbility.ets` 启动 embedded host
2. ArkTS 通过 `CodexHostNative.ets` 调 `libcodexhost.so`
3. `libcodexhost.so` 里的 NAPI bridge 调 Rust `codex-ohos-host`
4. Rust host 在应用内拉起 `codex-rs app-server`
5. 前端通过本地 WebSocket 连接：

```text
ws://127.0.0.1:7456
```

也就是说：

- native 层负责“把后端拉起来”
- 对话、plan、diff、approval 等真实协议走的是 WebSocket JSON-RPC

## 工作区权限

当前默认配置不是只读，而是：

- `approval_policy = "on-request"`
- `sandbox_mode = "workspace-write"`

但这里有一个容易混淆的点：

- 这个“workspace-write”写的是**设备内工作区**
- 不是你 Windows 主机上的 `C:\...` 仓库目录

如果你在鸿蒙虚拟机里看到“工作区只读”，通常是因为：

- 当前 `workspaceRoot` 为空
- 或者填了一个虚拟机里不存在/不可写的路径

比较稳妥的工作区路径应该放在应用沙箱里，例如：

```text
/data/storage/el2/base/files/project
```

## 清理构建产物

主项目清理：

```bat
Agent\script\helpsetup\build.bat clean
```

这会清掉：

- `Agent\.hvigor`
- `Agent\entry\build`
- `Agent\entry\.cxx`
- `Agent\.cargo-target`

独立 native builder 的缓存可以直接删除：

```text
libcodexhost-builder\out
```

影响是：

- 下次 HAP 构建会重新打包
- 下次 `.so` 构建会重新编 Rust，速度会明显变慢

## 在 DevEco 里怎么打开

应该打开：

- `OpenHarmony\Agent`

不要把整个 `OpenHarmony` 根目录直接当成 DevEco 工程打开。

## 当前保留的专项文档

如果你只想看更具体的脚本说明，保留这两份：

- `Agent/script/helpsetup/README.md`
- `libcodexhost-builder/README.md`

除此之外，根 README 已经覆盖了这个仓库当前有效的架构、构建流程和运行边界。
