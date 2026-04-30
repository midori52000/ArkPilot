import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor, HvigorPlugin } from '@ohos/hvigor';

declare const require: (id: string) => any;

const { repackHapWithNative } = require('./script/helpsetup/repack_hap_with_native.js');

const NATIVE_PACKAGING_TASKS = new Set([
  'assembleApp',
  'assembleHap',
  'PackageApp',
  'PackageHap',
  'SignApp',
  'SignPackagesFromApp',
]);

let nativePackagerHookRegistered = false;

const nativeHapPackagerPlugin: HvigorPlugin = {
  pluginId: 'arkpilot-native-hap-packager',
  apply(node) {
    if (nativePackagerHookRegistered) {
      return;
    }

    const commandEntryTasks = hvigor.getCommandEntryTask() ?? [];
    const shouldRepack = commandEntryTasks.some((taskName) => NATIVE_PACKAGING_TASKS.has(taskName));

    if (!shouldRepack) {
      return;
    }

    nativePackagerHookRegistered = true;
    const projectDir = node.getNodePath();

    hvigor.buildFinished(async (result) => {
      if (result.getError()) {
        return;
      }

      await repackHapWithNative(projectDir);
    });
  }
};

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [nativeHapPackagerPlugin] /* Custom plugin to extend the functionality of Hvigor. */
}
