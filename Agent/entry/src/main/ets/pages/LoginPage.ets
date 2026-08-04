import router from '@ohos.router';
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
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

  private loginParams: loginComponentManager.LoginWithHuaweiIDButtonParams = {
    style: loginComponentManager.Style.BUTTON_RED,
    borderRadius: 28,
    supportDarkMode: true,
    loginType: loginComponentManager.LoginType.ID,
    textAndIconStyle: true
  };

  aboutToAppear(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      huaweiAccountService.ensureInit(hostContext);
    } else {
      hilog.warn(LOGIN_DOMAIN, LOGIN_TAG, '%{public}s', 'host context unavailable, skip account init');
    }
    this.capabilitySupported = canIUse(HUAWEI_ID_LOGIN_SYSCAP);
    huaweiAccountService.setOnLoginStateChange(() => {
      this.onLoginStateChanged();
    });
    if (huaweiAccountService.isLoggedIn) {
      router.replaceUrl({ url: 'pages/Index' });
    }
  }

  aboutToDisappear(): void {
    huaweiAccountService.setOnLoginStateChange(() => {
    });
  }

  private onLoginStateChanged(): void {
    if (huaweiAccountService.isLoggedIn) {
      router.replaceUrl({ url: 'pages/Index' });
      return;
    }
    if (huaweiAccountService.lastErrorCode !== 0) {
      this.errorText = accountErrorMessage(huaweiAccountService.lastErrorCode);
    }
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
            controller: huaweiAccountService.loginController
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
    }
    .width('100%')
    .height('100%')
  }
}
