import router from '@ohos.router';
import { LoginPanel, LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { huaweiAccountService } from '../account/HuaweiAccountService';
import { accountErrorMessage } from '../account/AccountModels';

const LOGIN_DOMAIN = 0x0ff4;
const LOGIN_TAG = 'LoginPage';
const HUAWEI_ID_LOGIN_SYSCAP: string = 'SystemCapability.AuthenticationServices.HuaweiID.UIComponent';

@Entry
@Component
struct LoginPage {
  @StorageProp('arkPilotThemeMode') themeMode: string = 'light';
  @State private errorText: string = '';
  @State private capabilitySupported: boolean = true;
  @State private lastAccount: string = '';
  @State private loginBusy: boolean = false;
  @State private showSwitchPanel: boolean = false;

  private loginController: loginComponentManager.LoginWithHuaweiIDButtonController = new loginComponentManager.LoginWithHuaweiIDButtonController();
  private switchPanelController: loginComponentManager.LoginPanelController = new loginComponentManager.LoginPanelController();
  private loginCallbackRegistered: boolean = false;
  private switchPanelCallbackRegistered: boolean = false;

  private loginParams: loginComponentManager.LoginWithHuaweiIDButtonParams = {
    style: loginComponentManager.Style.BUTTON_RED,
    borderRadius: 28,
    supportDarkMode: true,
    loginType: loginComponentManager.LoginType.ID,
    textAndIconStyle: true
  };

  private switchPanelParams: loginComponentManager.LoginPanelParams = {
    appInfo: {
      appIcon: $r('app.media.layered_image'),
      appName: 'ArkPilot'
    },
    loginType: loginComponentManager.LoginType.ID
  };

  aboutToAppear(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      huaweiAccountService.ensureInit(hostContext);
    } else {
      hilog.warn(LOGIN_DOMAIN, LOGIN_TAG, '%{public}s', 'host context unavailable, skip account init');
    }
    this.capabilitySupported = canIUse(HUAWEI_ID_LOGIN_SYSCAP);
    this.lastAccount = huaweiAccountService.lastAccountMasked();
    this.registerLoginCallback();
    this.registerSwitchPanelCallback();
    if (huaweiAccountService.isLoggedIn) {
      router.replaceUrl({ url: 'pages/Index' });
    }
  }

  aboutToDisappear(): void {
    this.loginBusy = false;
    this.showSwitchPanel = false;
    this.unregisterLoginCallback();
    this.unregisterSwitchPanelCallback();
  }

  private registerLoginCallback(): void {
    if (this.loginCallbackRegistered) {
      return;
    }
    this.loginCallbackRegistered = true;
    this.loginController.onClickLoginWithHuaweiIDButton((err: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
      if (this.loginBusy) {
        return;
      }
      if (err !== null && err !== undefined) {
        this.loginBusy = false;
        this.errorText = accountErrorMessage(err.code);
        return;
      }
      this.handleLoginSuccess(credential);
    });
  }

  private unregisterLoginCallback(): void {
    this.loginCallbackRegistered = false;
  }

  private registerSwitchPanelCallback(): void {
    if (this.switchPanelCallbackRegistered) {
      return;
    }
    this.switchPanelCallbackRegistered = true;
    this.switchPanelController.onClickLoginWithHuaweiIDButton((err: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
      if (this.loginBusy) {
        return;
      }
      if (err !== null && err !== undefined) {
        this.loginBusy = false;
        this.showSwitchPanel = false;
        this.errorText = accountErrorMessage(err.code);
        return;
      }
      this.showSwitchPanel = false;
      this.handleLoginSuccess(credential);
    });
  }

  private unregisterSwitchPanelCallback(): void {
    this.switchPanelCallbackRegistered = false;
  }

  private handleLoginSuccess(credential: loginComponentManager.HuaweiIDCredential): void {
    this.loginBusy = true;
    huaweiAccountService.applyCredential(credential);
    router.replaceUrl({ url: 'pages/Index' });
  }

  private openSwitchAccount(): void {
    if (this.loginBusy) {
      return;
    }
    this.errorText = '';
    this.showSwitchPanel = true;
  }

  private isDarkMode(): boolean {
    return this.themeMode === 'dark';
  }

  private themeColor(light: string, dark: string): string {
    return this.isDarkMode() ? dark : light;
  }

  private textPrimary(): string {
    return this.themeColor('#0F172A', '#F8FAFC');
  }

  private textSecondary(): string {
    return this.themeColor('#475569', '#CBD5E1');
  }

  private textMuted(): string {
    return this.themeColor('#64748B', '#A8B3C2');
  }

  private surface(): string {
    return this.themeColor('#FFFFFF', '#1E293B');
  }

  build() {
    Stack() {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeColor('#EEF2F7', '#121212'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        Text('ArkPilot')
          .copyOption(CopyOptions.None)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary())

        Text('登录后使用全部功能')
          .copyOption(CopyOptions.None)
          .fontSize(14)
          .fontColor(this.textSecondary())
          .margin({ top: 10 })

        if (this.capabilitySupported) {
          LoginWithHuaweiIDButton({
            params: this.loginParams,
            controller: this.loginController
          })
            .width('100%')
            .height(48)
            .margin({ top: 36 })
        } else {
          Column() {
            Text('当前设备不支持华为账号登录')
              .copyOption(CopyOptions.None)
              .fontSize(14)
              .fontColor(this.textPrimary())
            Text('需要支持 SystemCapability.AuthenticationServices.HuaweiID.UIComponent 能力的设备。')
              .copyOption(CopyOptions.None)
              .fontSize(12)
              .fontColor(this.textMuted())
              .lineHeight(18)
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.themeColor('#FFFFFF', '#252526'))
          .borderRadius(16)
          .margin({ top: 36 })
        }

        if (this.lastAccount.length > 0) {
          Row() {
            Text(`上次登录：${this.lastAccount}`)
              .copyOption(CopyOptions.None)
              .fontSize(12)
              .fontColor(this.textSecondary())

            Blank()
              .layoutWeight(1)

            Text('切换账号')
              .copyOption(CopyOptions.None)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeColor('#2563EB', '#60A5FA'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.openSwitchAccount();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 12, bottom: 12 })
          .backgroundColor(this.themeColor('#F5F7FA', '#252526'))
          .borderRadius(14)
          .margin({ top: 18 })
        }

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .copyOption(CopyOptions.None)
            .fontSize(13)
            .fontColor('#B91C1C')
            .textAlign(TextAlign.Center)
            .lineHeight(19)
            .width('100%')
            .margin({ top: 20 })
        }

        Text('登录即代表同意华为相关服务协议与隐私政策')
          .copyOption(CopyOptions.None)
          .fontSize(11)
          .fontColor(this.textMuted())
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 40 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 380 })
      .padding({ left: 28, right: 28, top: 48, bottom: 48 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.surface())
      .borderRadius(24)
      .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 })

      if (this.showSwitchPanel) {
        LoginPanel({
          show: this.showSwitchPanel,
          params: this.switchPanelParams,
          controller: this.switchPanelController
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
