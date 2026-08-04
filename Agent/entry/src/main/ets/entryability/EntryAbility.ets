import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { startEmbeddedCodexHost } from '../backend/CodexNative';
import { PromptsBackendService } from '../prompts/PromptsBackendService';
import { installBundledSkills } from '../skills/BundledSkills';
import { SkillsBackendService } from '../skills/SkillsBackendService';
import { ReconcileResult } from '../skills/SkillTypes';
import { huaweiAccountService } from '../account/HuaweiAccountService';

const DOMAIN = 0x0000;
const TAG = 'CodexHost';
const DEFAULT_SERVER_URL = 'ws://127.0.0.1:7456';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      const codexHome: string = `${this.context.filesDir}/codex-home`;
      AppStorage.setOrCreate<string>('codexHome', codexHome);
      const status = startEmbeddedCodexHost(codexHome, DEFAULT_SERVER_URL);
      hilog.info(
        DOMAIN,
        TAG,
        'Embedded host start result: code=%{public}d running=%{public}s url=%{public}s message=%{public}s',
        status.code,
        status.running ? 'true' : 'false',
        status.serverUrl,
        status.message
      );

      // 首次启动自动导入已有 AGENTS.md
      const promptsService = new PromptsBackendService(codexHome);
      promptsService.autoImportOnFirstLaunch().catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Prompt auto import failed: %{public}s', JSON.stringify(err));
      });

      // 首次启动安装预设 bundled skills
      installBundledSkills(codexHome);

      // Skill 一致性检查：修复 registry 与 SSOT 目录的不一致
      const skillsService = new SkillsBackendService(codexHome);
      skillsService.reconcileSkills().then((result: ReconcileResult) => {
        if (result.removed.length > 0 || result.registered.length > 0) {
          hilog.info(
            DOMAIN, TAG,
            'Skills reconciled: removed=%{public}d registered=%{public}d',
            result.removed.length, result.registered.length
          );
        }
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Skills reconcile failed: %{public}s', JSON.stringify(err));
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start embedded app-server. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      huaweiAccountService.init(this.context);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to init huawei account service. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    // 设置沉浸式窗口
    windowStage.getMainWindow((err: BusinessError, windowClass: window.Window) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to get main window. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      // 设置沉浸式布局
      let isLayoutFullScreen = true;
      try {
        windowClass.setWindowLayoutFullScreen(isLayoutFullScreen).then(() => {
          hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in setting the window layout to full-screen mode.');

          // 隐藏状态栏和导航栏
          let names: Array<'status' | 'navigation'> = [];
          windowClass.setWindowSystemBarEnable(names).then(() => {
            hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in hiding the system bar.');
          }).catch((err: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'Failed to hide the system bar. Cause: %{public}s', JSON.stringify(err));
          });
        }).catch((err: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'Failed to set the window layout to full-screen mode. Cause: %{public}s', JSON.stringify(err));
        });
      } catch (exception) {
        hilog.error(DOMAIN, TAG, 'Failed to set the window layout to full-screen mode. Cause: %{public}s', JSON.stringify(exception));
      }
    });

    const loggedIn: boolean = (AppStorage.get<boolean>('arkPilotLoggedIn') ?? false);
    const initialPage: string = loggedIn ? 'pages/Index' : 'pages/LoginPage';
    windowStage.loadContent(initialPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
