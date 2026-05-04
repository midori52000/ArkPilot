import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { startEmbeddedCodexHost } from '../backend/CodexNative';
import { PromptsBackendService } from '../prompts/PromptsBackendService';
import { installBundledSkills } from '../skills/BundledSkills';
import { SkillsBackendService } from '../skills/SkillsBackendService';
import { ReconcileResult } from '../skills/SkillTypes';
import fileIo from '@ohos.file.fs';

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
      const defaultWorkspaceRoot: string = `${this.context.filesDir}/workspace-default`;
      AppStorage.setOrCreate<string>('codexHome', codexHome);
      AppStorage.setOrCreate<string>('defaultWorkspaceRoot', defaultWorkspaceRoot);
      try {
        fileIo.mkdirSync(defaultWorkspaceRoot, true);
      } catch (mkdirErr) {
        const mkdirErrText: string = JSON.stringify(mkdirErr);
        if (!mkdirErrText.includes('"code":13900015')) {
          hilog.error(DOMAIN, TAG, 'Failed to prepare workspace directory. Cause: %{public}s', mkdirErrText);
          throw new Error(mkdirErrText);
        }
        hilog.info(DOMAIN, TAG, 'Workspace directory already exists: %{public}s', defaultWorkspaceRoot);
      }
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
      promptsService.autoImportOnFirstLaunch();

      // 预设 bundled skills（幂等，已存在则跳过）
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
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
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
