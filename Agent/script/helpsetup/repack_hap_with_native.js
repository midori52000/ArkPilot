'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function parsePropertiesFile(filePath) {
  const properties = {};
  const raw = fs.readFileSync(filePath, 'utf8');

  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim();
    properties[key] = value;
  }

  return properties;
}

function resolveSdkDir(projectDir) {
  const localPropertiesPath = path.join(projectDir, 'local.properties');

  if (fs.existsSync(localPropertiesPath)) {
    const properties = parsePropertiesFile(localPropertiesPath);
    const sdkDir = properties['sdk.dir'];
    if (sdkDir) {
      return sdkDir.replace(/\//g, path.sep);
    }
  }

  if (process.env.DEVECO_SDK_HOME) {
    return process.env.DEVECO_SDK_HOME;
  }

  throw new Error(`Failed to resolve sdk.dir from ${localPropertiesPath}.`);
}

function resolveJavaBinary(studioHome) {
  const candidates = [
    process.env.JAVA_HOME ? path.join(process.env.JAVA_HOME, 'bin', 'java.exe') : '',
    process.env.JAVA_HOME ? path.join(process.env.JAVA_HOME, 'bin', 'java') : '',
    path.join(studioHome, 'jbr', 'bin', 'java.exe'),
    path.join(studioHome, 'jbr', 'bin', 'java'),
    'java',
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (candidate === 'java' || fs.existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(`Failed to locate a usable Java runtime under ${studioHome}.`);
}

function ensureFile(filePath, description) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${description} not found: ${filePath}`);
  }
}

function stageFile(sourcePath, targetPath) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.copyFileSync(sourcePath, targetPath);
}

function repackHapWithNative(projectDir) {
  const moduleDir = path.join(projectDir, 'entry');
  const outputDir = path.join(moduleDir, 'build', 'default', 'outputs', 'default');
  const outputHap = path.join(outputDir, 'entry-default-unsigned.hap');
  const prebuiltSo = path.join(moduleDir, 'src', 'main', 'libs', 'x86_64', 'libcodexhost.so');
  const sdkDir = resolveSdkDir(projectDir);
  const nativeSdkDir = path.join(sdkDir, 'default', 'openharmony', 'native');
  const cppSharedSo = path.join(nativeSdkDir, 'llvm', 'lib', 'x86_64-linux-ohos', 'libc++_shared.so');
  const stageRoot = path.join(moduleDir, 'build', 'manual-lib-pack');
  const stageDir = path.join(stageRoot, 'x86_64');
  const stagedSo = path.join(stageDir, 'libcodexhost.so');
  const stagedCppSharedSo = path.join(stageDir, 'libc++_shared.so');
  const moduleJson = path.join(moduleDir, 'build', 'default', 'intermediates', 'package', 'default', 'module.json');
  const resourcesDir = path.join(moduleDir, 'build', 'default', 'intermediates', 'res', 'default', 'resources');
  const resourcesIndex = path.join(moduleDir, 'build', 'default', 'intermediates', 'res', 'default', 'resources.index');
  const packInfo = path.join(outputDir, 'pack.info');
  const etsDir = path.join(moduleDir, 'build', 'default', 'intermediates', 'loader_out', 'default', 'ets');
  const pkgContextInfo = path.join(moduleDir, 'build', 'default', 'intermediates', 'loader', 'default', 'pkgContextInfo.json');

  ensureFile(outputHap, 'Unsigned HAP');
  ensureFile(prebuiltSo, 'Prebuilt native library');
  ensureFile(cppSharedSo, 'C++ shared runtime library');
  ensureFile(moduleJson, 'module.json');
  ensureFile(resourcesIndex, 'resources.index');
  ensureFile(packInfo, 'pack.info');
  ensureFile(pkgContextInfo, 'pkgContextInfo.json');

  stageFile(prebuiltSo, stagedSo);
  stageFile(cppSharedSo, stagedCppSharedSo);

  const studioHome = path.dirname(sdkDir);
  const javaBinary = resolveJavaBinary(studioHome);
  const appPackingTool = path.join(sdkDir, 'default', 'openharmony', 'toolchains', 'lib', 'app_packing_tool.jar');

  ensureFile(appPackingTool, 'app_packing_tool.jar');

  const args = [
    '-jar',
    appPackingTool,
    '--mode', 'hap',
    '--force', 'true',
    '--lib-path', stageRoot,
    '--json-path', moduleJson,
    '--resources-path', resourcesDir,
    '--index-path', resourcesIndex,
    '--pack-info-path', packInfo,
    '--out-path', outputHap,
    '--ets-path', etsDir,
    '--pkg-context-path', pkgContextInfo,
  ];

  const result = spawnSync(javaBinary, args, {
    cwd: projectDir,
    stdio: 'inherit',
    windowsHide: true,
  });

  if (result.status !== 0) {
    throw new Error(`app_packing_tool failed with exit code ${result.status ?? 'unknown'}.`);
  }

  return outputHap;
}

async function main() {
  const projectDir = path.resolve(process.argv[2] || path.join(__dirname, '..', '..'));
  const outputHap = repackHapWithNative(projectDir);
  console.log(`[OK] Repacked HAP with native library: ${outputHap}`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`[ERROR] ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  repackHapWithNative,
};
