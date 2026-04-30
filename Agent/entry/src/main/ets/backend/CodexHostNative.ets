import codexHost, { NativeCodexHostStatus, NativeCodexProviderConfig } from 'libcodexhost.so';

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
