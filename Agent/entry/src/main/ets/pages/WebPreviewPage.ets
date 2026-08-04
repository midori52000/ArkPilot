import router from '@ohos.router';
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { common, Want, wantConstant } from '@kit.AbilityKit';

@Entry
@Component
struct WebPreviewPage {
  @State private src: string = '';
  @State private title: string = '网页预览';
  @State private errorText: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const rawParams: Object = router.getParams();
    if (rawParams === undefined || rawParams === null) {
      return;
    }
    const params = rawParams as Record<string, string>;
    const nextSrc: string | undefined = params['src'];
    const nextTitle: string | undefined = params['title'];
    if (nextSrc !== undefined && nextSrc.length > 0) {
      this.src = nextSrc;
    }
    if (nextTitle !== undefined && nextTitle.length > 0) {
      this.title = nextTitle;
    }
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message.length > 0 ? err.message : '操作失败，请稍后重试';
    }
    return '操作失败，请稍后重试';
  }

  private currentAbilityContext(): common.UIAbilityContext | null {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      return null;
    }
    return hostContext as common.UIAbilityContext;
  }

  private openWithSystem(): void {
    if (this.src.length === 0) {
      promptAction.showToast({ message: '没有可打开的网页地址', duration: 1600 });
      return;
    }
    const context: common.UIAbilityContext | null = this.currentAbilityContext();
    if (context === null) {
      promptAction.showToast({ message: '当前页面上下文不可用', duration: 2000 });
      return;
    }
    const parameters: Record<string, Object> = {};
    parameters[wantConstant.Params.CONTENT_TITLE_KEY] = this.title;
    parameters[wantConstant.Params.PARAMS_STREAM] = [this.src];
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: this.src,
      type: 'text/html',
      parameters: parameters,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    try {
      context.startAbility(want)
        .then(() => {
          promptAction.showToast({ message: '已尝试用系统应用打开', duration: 1400 });
        })
        .catch((err: Object) => {
          promptAction.showToast({ message: `系统打开失败: ${this.describeError(err)}`, duration: 2600 });
        });
    } catch (err) {
      promptAction.showToast({ message: `系统打开失败: ${this.describeError(err)}`, duration: 2600 });
    }
  }

  @Builder
  private iconButton(label: string, onClick: () => void) {
    Button() {
      Text(label)
        .fontSize(16)
        .fontColor('#0F172A')
    }
    .width(38)
    .height(38)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#D8E1EE' })
    .borderRadius(8)
    .onClick(onClick)
  }

  @Builder
  private topBar() {
    Row() {
      this.iconButton('←', () => {
        router.back();
      })

      Column() {
        Text(this.title)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.src)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#64748B')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10, right: 10 })

      this.iconButton('↻', () => {
        try {
          this.controller.refresh();
        } catch (err) {
          promptAction.showToast({ message: `刷新失败: ${this.describeError(err)}`, duration: 2000 });
        }
      })

      Blank()
        .width(8)

      this.iconButton('↗', () => {
        this.openWithSystem();
      })
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#F8FAFC')
    .border({ width: 0.5, color: '#E2E8F0' })
  }

  build() {
    Column() {
      this.topBar()

      if (this.src.length === 0) {
        Column() {
          Text('没有可预览的网页文件')
            .fontSize(14)
            .fontColor('#64748B')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Stack() {
          Web({ src: this.src, controller: this.controller })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .onlineImageAccess(true)
            .darkMode(WebDarkMode.Off)
            .forceDarkAccess(false)
            .zoomAccess(true)
            .textZoomRatio(100)
            .onPageBegin(() => {
              this.errorText = '';
            })
            .onErrorReceive((event) => {
              if (event !== undefined && event.error !== undefined) {
                this.errorText = event.error.getErrorInfo();
              }
            })
            .width('100%')
            .height('100%')

          if (this.errorText.length > 0) {
            Column() {
              Text('网页加载失败')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B91C1C')
              Text(this.errorText)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(12)
                .fontColor('#7F1D1D')
                .lineHeight(18)
                .margin({ top: 8 })
            }
            .width('88%')
            .padding(14)
            .backgroundColor('#FEF2F2')
            .border({ width: 1, color: '#FECACA' })
            .borderRadius(8)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
