export interface NativeCodexHostStatus {
  code: number;
  running: boolean;
  serverUrl: string;
  message: string;
}

export interface NativeCodexProviderConfig {
  baseUrl?: string;
  base_url?: string;
  apiKey?: string;
  api_key?: string;
  model?: string;
}

export interface NativeCodexProviderRecord {
  id?: string;
  name?: string;
  appType?: string;
  mode?: string;
  baseUrl?: string;
  base_url?: string;
  apiKey?: string;
  api_key?: string;
  model?: string;
  isActive?: boolean;
  syncStatus?: string;
  updatedAt?: string;
}

export interface NativeCodexProviderCatalog {
  version?: number;
  activeProviderId?: string;
  providers?: NativeCodexProviderRecord[];
  updatedAt?: string;
}

interface NativeCodexHostModule {
  startHost: (codexHome?: string, serverUrl?: string) => NativeCodexHostStatus;
  getStatus: () => NativeCodexHostStatus;
  isHostRunning: () => boolean;
  getLastMessage: () => string;
  getServerUrl: () => string;
  getProviderConfig: (codexHome?: string) => string;
  saveProviderConfig: (codexHome?: string, baseUrl?: string, apiKey?: string, model?: string) => string;
  getProviderCatalog: (codexHome?: string) => string;
  saveProviderCatalog: (codexHome?: string, catalogJson?: string) => string;
}

declare const codexHost: NativeCodexHostModule;

export default codexHost;
