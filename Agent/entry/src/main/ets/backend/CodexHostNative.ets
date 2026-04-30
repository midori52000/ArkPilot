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
  return normalizeStatus(codexHost.startHost(codexHome, serverUrl));
}

export function getEmbeddedCodexHostStatus(): CodexHostStatus {
  return normalizeStatus(codexHost.getStatus());
}

export function getEmbeddedCodexProviderConfig(): CodexProviderConfig {
  return parseProviderConfig(codexHost.getProviderConfig(''));
}

export function saveEmbeddedCodexProviderConfig(baseUrl: string, apiKey: string, model: string): CodexProviderConfig {
  return parseProviderConfig(codexHost.saveProviderConfig('', baseUrl, apiKey, model));
}

export function getEmbeddedCodexProviderCatalog(): ProviderCatalog {
  return parseProviderCatalog(codexHost.getProviderCatalog(''));
}

export function saveEmbeddedCodexProviderCatalog(catalog: ProviderCatalog): ProviderCatalog {
  return parseProviderCatalog(codexHost.saveProviderCatalog('', JSON.stringify(catalog)));
}
