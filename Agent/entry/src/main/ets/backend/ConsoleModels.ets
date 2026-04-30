export type AiAppType = 'codex' | 'claude' | 'gemini' | 'opencode' | 'openclaw' | 'hermes';
export type ProviderMode = 'exclusive' | 'additive';
export type ProviderSyncStatus = 'synced' | 'dirty' | 'error';
export type McpSyncStatus = 'synced' | 'dirty' | 'error';
export type McpHealthStatus = 'unknown' | 'ok' | 'degraded' | 'error';
export type McpAuthStatus = 'notRequired' | 'required' | 'pending' | 'authenticated' | 'failed';
export type SidebarView = 'chat' | 'providers' | 'sessions' | 'usage' | 'mcp' | 'prompts' | 'skills' | 'openclaw' | 'hermes';
export type SettingsTab = 'mcp' | 'skills' | 'prompts' | 'api';

export class ProviderRecord {
  id: string;
  name: string;
  appType: AiAppType;
  mode: ProviderMode;
  baseUrl: string;
  apiKey: string;
  model: string;
  isActive: boolean;
  syncStatus: ProviderSyncStatus;
  updatedAt: string;

  constructor(
    id: string,
    name: string,
    appType: AiAppType,
    mode: ProviderMode,
    baseUrl: string,
    apiKey: string,
    model: string,
    isActive: boolean,
    syncStatus: ProviderSyncStatus,
    updatedAt: string
  ) {
    this.id = id;
    this.name = name;
    this.appType = appType;
    this.mode = mode;
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.model = model;
    this.isActive = isActive;
    this.syncStatus = syncStatus;
    this.updatedAt = updatedAt;
  }
}

export class ProviderCatalog {
  version: number;
  activeProviderId: string;
  providers: ProviderRecord[];
  updatedAt: string;

  constructor(version: number, activeProviderId: string, providers: ProviderRecord[], updatedAt: string) {
    this.version = version;
    this.activeProviderId = activeProviderId;
    this.providers = providers;
    this.updatedAt = updatedAt;
  }
}

export class McpServerRecord {
  id: string;
  name: string;
  enabled: boolean;
  transportType: string;
  command: string;
  argsText: string;
  url: string;
  envText: string;
  toolCount: number;
  resourceCount: number;
  healthStatus: McpHealthStatus;
  authStatus: McpAuthStatus;
  lastError: string;
  syncStatus: McpSyncStatus;
  updatedAt: string;

  constructor(
    id: string,
    name: string,
    enabled: boolean,
    transportType: string,
    command: string,
    argsText: string,
    url: string,
    envText: string,
    toolCount: number,
    resourceCount: number,
    healthStatus: McpHealthStatus,
    authStatus: McpAuthStatus,
    lastError: string,
    syncStatus: McpSyncStatus,
    updatedAt: string
  ) {
    this.id = id;
    this.name = name;
    this.enabled = enabled;
    this.transportType = transportType;
    this.command = command;
    this.argsText = argsText;
    this.url = url;
    this.envText = envText;
    this.toolCount = toolCount;
    this.resourceCount = resourceCount;
    this.healthStatus = healthStatus;
    this.authStatus = authStatus;
    this.lastError = lastError;
    this.syncStatus = syncStatus;
    this.updatedAt = updatedAt;
  }
}

export class SessionSummary {
  sessionId: string;
  title: string;
  workspaceRoot: string;
  messageCount: number;
  lastUpdatedAt: string;
  summaryTitle: string;
  status: string;
  changedFiles: string;

  constructor(
    sessionId: string,
    title: string,
    workspaceRoot: string,
    messageCount: number,
    lastUpdatedAt: string,
    summaryTitle: string,
    status: string,
    changedFiles: string
  ) {
    this.sessionId = sessionId;
    this.title = title;
    this.workspaceRoot = workspaceRoot;
    this.messageCount = messageCount;
    this.lastUpdatedAt = lastUpdatedAt;
    this.summaryTitle = summaryTitle;
    this.status = status;
    this.changedFiles = changedFiles;
  }
}

export class UsageSummary {
  sessionCount: number;
  activeTurnCount: number;
  turnCount: number;
  messageCount: number;
  diffLineCount: number;
  diffUpdateCount: number;
  lastTurnStatus: string;

  constructor(
    sessionCount: number,
    activeTurnCount: number,
    turnCount: number,
    messageCount: number,
    diffLineCount: number,
    diffUpdateCount: number,
    lastTurnStatus: string
  ) {
    this.sessionCount = sessionCount;
    this.activeTurnCount = activeTurnCount;
    this.turnCount = turnCount;
    this.messageCount = messageCount;
    this.diffLineCount = diffLineCount;
    this.diffUpdateCount = diffUpdateCount;
    this.lastTurnStatus = lastTurnStatus;
  }
}
