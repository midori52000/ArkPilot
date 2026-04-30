import codexHost, {
  NativeCodexHostStatus,
  NativeCodexProviderCatalog,
  NativeCodexProviderConfig,
  NativeCodexProviderRecord
} from 'libcodexhost.so';
import { ProviderCatalog, ProviderRecord } from './ConsoleModels';

export class CodexHostStatus {
  code: number;
  running: boolean;
  serverUrl: string;
  message: string;

  constructor(code: number, running: boolean, serverUrl: string, message: string) {
    this.code = code;
    this.running = running;
    this.serverUrl = serverUrl;
    this.message = message;
  }
}

export class CodexProviderConfig {
  baseUrl: string;
  apiKey: string;
  model: string;

  constructor(baseUrl: string, apiKey: string, model: string) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.model = model;
  }
}

function missingNativeModuleStatus(): CodexHostStatus {
  return new CodexHostStatus(
    1,
    false,
    '',
    'libcodexhost.so failed to load. Check whether the native library was packaged into the HAP.'
  );
}

function nativeModuleUnavailable(): boolean {
  return codexHost === undefined || codexHost === null;
}

function normalizeProviderRecord(rawRecord: NativeCodexProviderRecord | undefined): ProviderRecord {
  const appType = (rawRecord?.appType ?? 'codex') === 'codex' ? 'codex' : 'codex';
  const mode = (rawRecord?.mode ?? 'exclusive') === 'additive' ? 'additive' : 'exclusive';
  const syncStatusRaw: string = rawRecord?.syncStatus ?? 'synced';
  const syncStatus = syncStatusRaw === 'dirty' ? 'dirty' : (syncStatusRaw === 'error' ? 'error' : 'synced');
  return new ProviderRecord(
    rawRecord?.id ?? '',
    rawRecord?.name ?? '未命名 Provider',
    appType,
    mode,
    rawRecord?.baseUrl ?? rawRecord?.base_url ?? '',
    rawRecord?.apiKey ?? rawRecord?.api_key ?? '',
    rawRecord?.model ?? '',
    rawRecord?.isActive === true,
    syncStatus,
    rawRecord?.updatedAt ?? ''
  );
}

function normalizeProviderCatalog(rawCatalog: NativeCodexProviderCatalog | undefined): ProviderCatalog {
  if (rawCatalog === undefined) {
    return new ProviderCatalog(1, '', [], '');
  }
  const providers: ProviderRecord[] = rawCatalog.providers === undefined
    ? []
    : rawCatalog.providers.map((provider: NativeCodexProviderRecord) => normalizeProviderRecord(provider));
  return new ProviderCatalog(
    rawCatalog.version ?? 1,
    rawCatalog.activeProviderId ?? '',
    providers,
    rawCatalog.updatedAt ?? ''
  );
}

function normalizeStatus(rawStatus: NativeCodexHostStatus | undefined): CodexHostStatus {
  if (rawStatus === undefined) {
    return new CodexHostStatus(1, false, '', 'native codex host returned no status');
  }

  return new CodexHostStatus(
    rawStatus.code ?? 0,
    rawStatus.running === true,
    rawStatus.serverUrl ?? '',
    rawStatus.message ?? ''
  );
}

function normalizeProviderConfig(rawConfig: NativeCodexProviderConfig | undefined): CodexProviderConfig {
  if (rawConfig === undefined) {
    return new CodexProviderConfig('', '', '');
  }

  return new CodexProviderConfig(
    rawConfig.baseUrl ?? rawConfig.base_url ?? '',
    rawConfig.apiKey ?? rawConfig.api_key ?? '',
    rawConfig.model ?? ''
  );
}

function parseProviderConfig(rawValue: string): CodexProviderConfig {
  if (rawValue.trim().length === 0) {
    return new CodexProviderConfig('', '', '');
  }

  try {
    const rawConfig: NativeCodexProviderConfig = JSON.parse(rawValue) as NativeCodexProviderConfig;
    return normalizeProviderConfig(rawConfig);
  } catch (_err) {
    return new CodexProviderConfig('', '', '');
  }
}

function parseProviderCatalog(rawValue: string): ProviderCatalog {
  if (rawValue.trim().length === 0) {
    return new ProviderCatalog(1, '', [], '');
  }

  try {
    const rawCatalog: NativeCodexProviderCatalog = JSON.parse(rawValue) as NativeCodexProviderCatalog;
    return normalizeProviderCatalog(rawCatalog);
  } catch (_err) {
    return new ProviderCatalog(1, '', [], '');
  }
}

export function startEmbeddedCodexHost(codexHome: string, serverUrl: string): CodexHostStatus {
  if (nativeModuleUnavailable()) {
    return missingNativeModuleStatus();
  }

  try {
    return normalizeStatus(codexHost.startHost(codexHome, serverUrl));
  } catch (_err) {
    return missingNativeModuleStatus();
  }
}

export function getEmbeddedCodexHostStatus(): CodexHostStatus {
  if (nativeModuleUnavailable()) {
    return missingNativeModuleStatus();
  }

  try {
    return normalizeStatus(codexHost.getStatus());
  } catch (_err) {
    return missingNativeModuleStatus();
  }
}

export function getEmbeddedCodexProviderConfig(): CodexProviderConfig {
  if (nativeModuleUnavailable()) {
    return new CodexProviderConfig('', '', '');
  }

  try {
    return parseProviderConfig(codexHost.getProviderConfig(''));
  } catch (_err) {
    return new CodexProviderConfig('', '', '');
  }
}

export function saveEmbeddedCodexProviderConfig(baseUrl: string, apiKey: string, model: string): CodexProviderConfig {
  if (nativeModuleUnavailable()) {
    return new CodexProviderConfig('', '', '');
  }

  try {
    return parseProviderConfig(codexHost.saveProviderConfig('', baseUrl, apiKey, model));
  } catch (_err) {
    return new CodexProviderConfig('', '', '');
  }
}

export function getEmbeddedCodexProviderCatalog(): ProviderCatalog {
  if (nativeModuleUnavailable()) {
    return new ProviderCatalog(1, '', [], '');
  }

  try {
    return parseProviderCatalog(codexHost.getProviderCatalog(''));
  } catch (_err) {
    return new ProviderCatalog(1, '', [], '');
  }
}

export function saveEmbeddedCodexProviderCatalog(catalog: ProviderCatalog): ProviderCatalog {
  if (nativeModuleUnavailable()) {
    return new ProviderCatalog(1, '', [], '');
  }

  try {
    return parseProviderCatalog(codexHost.saveProviderCatalog('', JSON.stringify(catalog)));
  } catch (_err) {
    return new ProviderCatalog(1, '', [], '');
  }
}

// ========== Skills Management ==========

export function getSkillsRegistry(codexHome: string): string {
  if (nativeModuleUnavailable()) {
    return '{"version":1,"skills":[],"updatedAt":"0"}';
  }
  try {
    const result = codexHost.getSkillsRegistry(codexHome);
    return (result !== undefined && result !== null && result.length > 0) ? result : '{"version":1,"skills":[],"updatedAt":"0"}';
  } catch (_err) {
    return '{"version":1,"skills":[],"updatedAt":"0"}';
  }
}

export function saveSkillsRegistry(codexHome: string, registryJson: string): boolean {
  if (nativeModuleUnavailable()) {
    return false;
  }
  try {
    const code = codexHost.saveSkillsRegistry(codexHome, registryJson);
    return code === 0;
  } catch (_err) {
    return false;
  }
}

export function getSkillsRepos(codexHome: string): string {
  if (nativeModuleUnavailable()) {
    return '{"version":1,"repos":[]}';
  }
  try {
    const result = codexHost.getSkillsRepos(codexHome);
    return (result !== undefined && result !== null && result.length > 0) ? result : '{"version":1,"repos":[]}';
  } catch (_err) {
    return '{"version":1,"repos":[]}';
  }
}

export function saveSkillsRepos(codexHome: string, reposJson: string): boolean {
  if (nativeModuleUnavailable()) {
    return false;
  }
  try {
    const code = codexHost.saveSkillsRepos(codexHome, reposJson);
    return code === 0;
  } catch (_err) {
    return false;
  }
}

export function computeDirHash(dirPath: string): string {
  if (nativeModuleUnavailable()) {
    return '';
  }
  try {
    const result = codexHost.computeDirHash(dirPath);
    return (result !== undefined && result !== null) ? result : '';
  } catch (_err) {
    return '';
  }
}

export function getSkillsBackups(codexHome: string): string {
  if (nativeModuleUnavailable()) {
    return '[]';
  }
  try {
    const result = codexHost.getSkillsBackups(codexHome);
    return (result !== undefined && result !== null && result.length > 0) ? result : '[]';
  } catch (_err) {
    return '[]';
  }
}

export function createSkillBackup(codexHome: string, skillDir: string, skillJson: string): string {
  if (nativeModuleUnavailable()) {
    return 'error:native module unavailable';
  }
  try {
    const result = codexHost.createSkillBackup(codexHome, skillDir, skillJson);
    return (result !== undefined && result !== null) ? result : 'error:empty result';
  } catch (_err) {
    return 'error:exception';
  }
}

export function deleteSkillBackup(codexHome: string, backupId: string): boolean {
  if (nativeModuleUnavailable()) {
    return false;
  }
  try {
    const code = codexHost.deleteSkillBackup(codexHome, backupId);
    return code === 0;
  } catch (_err) {
    return false;
  }
}

// ========== Prompts Management ==========

export function getPromptsRegistry(codexHome: string): string {
  if (nativeModuleUnavailable()) {
    return '{"version":1,"prompts":[],"updatedAt":"0"}';
  }
  try {
    const result = codexHost.getPromptsRegistry(codexHome);
    return (result !== undefined && result !== null && result.length > 0) ? result : '{"version":1,"prompts":[],"updatedAt":"0"}';
  } catch (_err) {
    return '{"version":1,"prompts":[],"updatedAt":"0"}';
  }
}

export function savePromptsRegistry(codexHome: string, registryJson: string): boolean {
  if (nativeModuleUnavailable()) {
    return false;
  }
  try {
    const code = codexHost.savePromptsRegistry(codexHome, registryJson);
    return code === 0;
  } catch (_err) {
    return false;
  }
}

export function readAgentsMd(codexHome: string): string {
  if (nativeModuleUnavailable()) {
    return '';
  }
  try {
    const result = codexHost.readAgentsMd(codexHome);
    return (result !== undefined && result !== null) ? result : '';
  } catch (_err) {
    return '';
  }
}

export function writeAgentsMd(codexHome: string, content: string): boolean {
  if (nativeModuleUnavailable()) {
    return false;
  }
  try {
    const code = codexHost.writeAgentsMd(codexHome, content);
    return code === 0;
  } catch (_err) {
    return false;
  }
}
