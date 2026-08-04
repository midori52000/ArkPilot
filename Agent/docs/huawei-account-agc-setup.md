# 华为账号登录（Account Kit）接入与 AGC 配置指南

本应用（ArkPilot，bundleName：`com.originverse.arkpilot`）已通过 `@kit.AccountKit` 接入华为账号登录（Account Kit）。

登录流程为**启动强制门禁**：应用启动时若未登录则进入 `LoginPage`，使用官方 `LoginWithHuaweiIDButton` 完成授权；登录成功后进入主界面（`Index`），左侧面板底部显示脱敏账号并支持退出登录。

## 一、代码侧接入概览

| 文件 | 职责 |
|---|---|
| `entry/src/main/ets/account/AccountModels.ets` | 会话模型、账号脱敏、错误码→文案映射（纯逻辑，可单测） |
| `entry/src/main/ets/account/HuaweiAccountService.ets` | 单例服务：`preferences` 持久化、登录回调注册、AppStorage 同步 |
| `entry/src/main/ets/pages/LoginPage.ets` | 登录门禁页（官方 `LoginWithHuaweiIDButton`） |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 启动时初始化服务，按登录态分流 LoginPage / Index |
| `entry/src/main/ets/pages/Index.ets` | 左面板底部账号状态行 + 退出登录 |

代码侧**无需**额外 ohpm 依赖，也**无需**在 `module.json5` 声明任何权限。Account Kit 登录组件属于系统级能力。

## 二、AGC（AppGallery Connect）配置步骤（真机验收前置条件）

> 真实设备的授权登录必须完成以下配置，否则点击登录会返回错误码（见文末排查表）。

### 1. 注册应用

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)。
2. 新建项目并创建应用，**包名必须与工程 `AppScope/app.json5` 中的 `bundleName` 一致**：
   - `com.originverse.arkpilot`
3. 平台选择 **HarmonyOS**。

### 2. 开通「华为账号服务」

1. 进入应用的「增长 → 华为账号服务」（或「开发服务 → 认证服务」对应入口）。
2. 点击「开通」启用 **Account Kit（华为账号服务）**。
3. 按页面提示补充开发者资质信息。

### 3. 配置签名证书指纹（关键）

Account Kit 会校验应用包签名指纹，必须把发布/调试签名证书的 **SHA-256 指纹**配置到 AGC：

1. 在 DevEco Studio 中确认签名配置（File → Project Structure → Signing Configs），或使用密钥库导出指纹。
2. 获取 SHA-256 指纹：
   ```bat
   keytool -list -v -keystore <your.p12> -alias <alias> -storepass <password>
   ```
   复制输出中的 `SHA256:` 指纹值。
3. 在 AGC 应用「常规 → 应用信息 → 证书指纹」中点击「添加证书指纹」，粘贴该值。

### 4. 配置 Client ID（必做，否则报 1001502003）

> **报错 `1001502003`（参数错误）的根因就是 `client_id` 未配置或配置错误。**
> Account Kit 登录组件必须从工程 `module.json5` 读取 AGC 的 Client ID（OAuth 2.0 客户端 ID）。

1. 在 AGC 应用「常规 → 应用信息 → 凭据 → Client ID」中复制 **Client ID 值**（注意：不是 APP ID）。
2. 打开 `entry/src/main/module.json5`，在 `module` 下已添加：
   ```json5
   "metadata": [
     {
       "name": "client_id",
       "value": "REPLACE_WITH_AGC_CLIENT_ID"
     }
   ]
   ```
3. 把 `REPLACE_WITH_AGC_CLIENT_ID` 替换为上一步复制的 **Client ID 值**。

⚠️ 配置要点（配错仍报 1001502003）：
- `value` 必须是 **Client ID**，不能填 APP ID。
- `value` 必须**直接写字符串值**，不能写成 `"value": "$string:clientId"`。
- 整个 `module.json5` 中只能有**一个** `client_id` 配置。

### 5. 配置应用签名（必做，否则报 1001500001）

> **报错 `1001500001`（应用签名校验失败）的根因是 HAP 未签名，或签名证书指纹未登记到 AGC。**
> Account Kit 必须校验**已签名 HAP** 的证书指纹；未签名（`*-unsigned.hap`）或指纹不匹配都会被拒绝。

在 DevEco Studio 中配置签名（需要登录华为开发者账号）：

1. 打开工程 `Agent/`。
2. 菜单 **File → Project Structure → Signing Configs**。
3. 勾选 **Automatically generate signature**（自动签名），按提示登录/关联你的华为开发者账号。
4. DevEco Studio 会自动生成调试证书与密钥，并在 `build-profile.json5` 中写入 `signingConfigs` 与产品的 `signingConfig` 引用。
5. 确认后重新构建：此时产物应为 **`entry-default-signed.hap`**（不再是 `unsigned`）。

> 自动签名生成的调试证书指纹是**注册证书（AGC）识别该应用**的依据，必须与第 3 步「证书指纹」一致。
> 若你使用自定义证书（.cer/.p12/.p7b），则改为在 Signing Configs 中手动选择证书，并确保 SHA-256 指纹已添加到 AGC。

### 6. 打包并真机/模拟器安装验证

1. 使用与 AGC 指纹匹配的签名配置构建 HAP（Debug/Release 均可）。
2. 通过 DevEco Studio 部署到**已登录华为账号的设备**。
   - 模拟器：Account Kit **支持模拟器**，可先用于流程调试（登录能力与真机基本一致）。
   - 真机：作为最终验收环境。
3. 启动应用：未登录 → 进入登录页 → 点击「使用华为账号登录」完成授权 → 进入主界面。

## 三、真机验收清单

> 以下清单已在模拟器（Huawei HarmonyOS Emulator）上验证通过（✔ 标记为已验证项）。

- [x] ✔ 全新安装后启动，进入 `LoginPage` 登录门禁
- [x] ✔ 点击华为账号登录按钮，拉起授权页，输入/确认华为账号
- [x] ✔ 授权成功后自动进入主界面（`Index`）
- [x] ✔ 主界面左侧面板底部显示 `Huawei 账号 ****xxxx`（脱敏 unionID，实测 `****tDgU`）
- [x] ✔ 杀掉应用重新启动，保持已登录状态，直接进入主界面
- [x] ✔ 点击「退出登录」→ 二次确认 → 回到 `LoginPage`
- [x] ✔ 退出后重新启动，仍停留在 `LoginPage`（登录态已清除）
- [x] ✔ 退出确认对话框「取消」分支正常关闭并停留主界面
- [x] ✔ 退出后登录页显示「上次登录：****xxxx」脱敏账号信息
- [x] ✔ 点击「切换账号」弹出华为账号登录面板（`LoginPanel`），面板内登录可完成重新登录
- [x] ✔ 退出登录后（不退出软件）再次点击「华为账号登录」按钮可正常重新登录
- [ ] 在未登录华为账号的设备上点击登录，页面展示可读错误文案且不崩溃（真机补验）

## 四、常见错误码排查

| 错误码 | 含义 | 处理 |
|---|---|---|
| `1001500001` | 应用包签名指纹校验失败 | HAP 未签名或指纹不匹配：DevEco 配置自动签名（File → Project Structure → Signing Configs）→ 构建 signed HAP → 将签名证书 SHA-256 指纹添加到 AGC「常规 → 证书指纹」 |
| `1001502001` | 设备未登录华为账号 | 在设备「设置 → 华为账号」登录后再试 |
| `1001502002` | 应用未获得授权 | AGC 未开通「华为账号服务」，或应用尚未审核通过 |
| `1001502003` | 参数错误 | 检查是否误改登录参数（本应用使用默认 `LoginType.ID`） |
| `1001502005` | 网络错误 | 检查设备网络 |
| `1001502009` | 内部错误 | 稍后重试；持续失败联系华为技术支持 |
| `1001502012` | 用户取消授权 | 正常流程，用户主动取消 |
| `1001502014` | 缺少 scopes/权限 | AGC 侧检查账号服务权限配置 |
| `1005300001` | 用户未同意协议 | 正常流程，用户未勾选同意 |
| `801` / 异常 | 设备不支持该能力 | 真机验证；模拟器/2in1 可能不支持 `SystemCapability.AuthenticationServices.HuaweiID.UIComponent` |

## 五、数据与安全说明

- 登录成功后仅在本地 `preferences`（`arkpilot_account`）保存 `unionID / openID / authorizationCode / idToken / loginAt`，用于登录态持久化与脱敏展示。
- 未接入后端换取 access_token，也不会上传任何账号信息。
- 退出登录会清除本地会话并同步刷新 AppStorage 登录态。
