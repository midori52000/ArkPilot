export type AiAppType = 'codex' | 'claude' | 'gemini' | 'opencode' | 'openclaw' | 'hermes';
export type ProviderMode = 'exclusive' | 'additive';
export type ProviderSyncStatus = 'synced' | 'dirty' | 'error';
export type McpSyncStatus = 'synced' | 'dirty' | 'error';
export type McpHealthStatus = 'unknown' | 'ok' | 'warning' | 'degraded' | 'error';
export type McpAuthStatus = 'notRequired' | 'required' | 'pending' | 'authenticated' | 'failed';
export type SidebarView = 'chat' | 'providers' | 'sessions' | 'usage' | 'mcp' | 'prompts' | 'skills' | 'openclaw' | 'hermes';
export type SettingsTab = 'mcp' | 'skills' | 'prompts' | 'api';

export type ApiWireFormat = 'responses' | 'chat' | 'anthropic';
export type ProviderCategory = 'official' | 'third_party' | 'cloud_provider' | 'aggregator' | 'custom';
export type WorkspaceAccessKind = 'sandbox' | 'user_granted' | 'readonly' | 'unknown';
export type WorkspacePermissionState = 'writable' | 'readonly' | 'unavailable' | 'revoked';

export class WorkspaceDescriptor {
  id: string;
  name: string;
  rootPath: string;
  accessKind: WorkspaceAccessKind;
  permissionState: WorkspacePermissionState;
  sourceUri: string;
  writableRoots: string[];
  grantedAt: number;
  lastCheckedAt: number;

  constructor(
    id: string,
    name: string,
    rootPath: string,
    accessKind: WorkspaceAccessKind,
    permissionState: WorkspacePermissionState,
    sourceUri: string,
    writableRoots: string[],
    grantedAt: number,
    lastCheckedAt: number
  ) {
    this.id = id;
    this.name = name;
    this.rootPath = rootPath;
    this.accessKind = accessKind;
    this.permissionState = permissionState;
    this.sourceUri = sourceUri;
    this.writableRoots = writableRoots;
    this.grantedAt = grantedAt;
    this.lastCheckedAt = lastCheckedAt;
  }
}

export class EndpointEntry {
  url: string;
  addedAt: number;
  lastUsed: number;
  latencyMs: number;
  isActive: boolean;

  constructor(url: string, addedAt: number, lastUsed: number, latencyMs: number, isActive: boolean) {
    this.url = url;
    this.addedAt = addedAt;
    this.lastUsed = lastUsed;
    this.latencyMs = latencyMs;
    this.isActive = isActive;
  }
}

export class CustomHeadersEntry {
  key: string;
  value: string;

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

export class UsageScriptEntry {
  enabled: boolean;
  scriptType: string;
  code: string;
  queryUrl: string;
  headers: CustomHeadersEntry[];
  autoQueryIntervalMin: number;

  constructor(
    enabled: boolean, scriptType: string, code: string,
    queryUrl: string, headers: CustomHeadersEntry[], autoQueryIntervalMin: number
  ) {
    this.enabled = enabled;
    this.scriptType = scriptType;
    this.code = code;
    this.queryUrl = queryUrl;
    this.headers = headers;
    this.autoQueryIntervalMin = autoQueryIntervalMin;
  }
}

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
  authMode: string;
  customHeaders: CustomHeadersEntry[];
  wireApi: ApiWireFormat;
  category: ProviderCategory;
  description: string;
  websiteUrl: string;
  icon: string;
  iconColor: string;
  endpoints: EndpointEntry[];
  healthStatus: string;
  healthLatencyMs: number;
  lastValidatedAt: number;
  usageScript: UsageScriptEntry | null;
  createdAt: number;

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
    updatedAt: string,
    authMode?: string,
    customHeaders?: CustomHeadersEntry[],
    wireApi?: ApiWireFormat,
    category?: ProviderCategory,
    description?: string,
    websiteUrl?: string,
    icon?: string,
    iconColor?: string,
    endpoints?: EndpointEntry[],
    healthStatus?: string,
    healthLatencyMs?: number,
    lastValidatedAt?: number,
    usageScript?: UsageScriptEntry | null,
    createdAt?: number
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
    this.authMode = authMode ?? 'apiKey';
    this.customHeaders = customHeaders ?? [];
    this.wireApi = wireApi ?? 'responses';
    this.category = category ?? 'custom';
    this.description = description ?? '';
    this.websiteUrl = websiteUrl ?? '';
    this.icon = icon ?? '';
    this.iconColor = iconColor ?? '';
    this.endpoints = endpoints ?? [];
    this.healthStatus = healthStatus ?? 'unknown';
    this.healthLatencyMs = healthLatencyMs ?? 0;
    this.lastValidatedAt = lastValidatedAt ?? 0;
    this.usageScript = usageScript ?? null;
    this.createdAt = createdAt ?? Date.now();
  }

  getHeaderValue(key: string): string {
    for (let i = 0; i < this.customHeaders.length; i++) {
      if (this.customHeaders[i].key === key) {
        return this.customHeaders[i].value;
      }
    }
    return '';
  }

  setHeader(key: string, value: string): void {
    for (let i = 0; i < this.customHeaders.length; i++) {
      if (this.customHeaders[i].key === key) {
        this.customHeaders[i].value = value;
        return;
      }
    }
    this.customHeaders.push(new CustomHeadersEntry(key, value));
  }

  copyHeaders(): CustomHeadersEntry[] {
    const result: CustomHeadersEntry[] = [];
    for (let i = 0; i < this.customHeaders.length; i++) {
      const h = this.customHeaders[i];
      result.push(new CustomHeadersEntry(h.key, h.value));
    }
    return result;
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

export class ProviderDefinition {
  id: string;
  name: string;
  baseUrl: string;
  model: string;
  wireApi: string;
  isActive: boolean;
  appType: string;
  mode: string;
  syncStatus: string;
  updatedAt: string;

  constructor(
    id: string, name: string, baseUrl: string, model: string,
    wireApi: string, isActive: boolean, appType: string, mode: string,
    syncStatus: string, updatedAt: string
  ) {
    this.id = id;
    this.name = name;
    this.baseUrl = baseUrl;
    this.model = model;
    this.wireApi = wireApi;
    this.isActive = isActive;
    this.appType = appType;
    this.mode = mode;
    this.syncStatus = syncStatus;
    this.updatedAt = updatedAt;
  }
}

export class ModelsCacheEntry {
  slug: string;
  displayName: string;
  description: string;
  contextWindow: number;

  constructor(slug: string, displayName: string, description: string, contextWindow: number) {
    this.slug = slug;
    this.displayName = displayName;
    this.description = description;
    this.contextWindow = contextWindow;
  }
}

export class ModelsCache {
  fetchedAt: string;
  etag: string;
  providerId: string;
  models: ModelsCacheEntry[];

  constructor(fetchedAt: string, etag: string, providerId: string, models: ModelsCacheEntry[]) {
    this.fetchedAt = fetchedAt;
    this.etag = etag;
    this.providerId = providerId;
    this.models = models;
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
  httpHeadersText: string;
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
    httpHeadersText: string,
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
    this.httpHeadersText = httpHeadersText;
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
  workspaceId: string;
  workspaceName: string;
  workspaceRoot: string;
  workspacePermissionState: WorkspacePermissionState;
  workspaceAccessKind: WorkspaceAccessKind;
  messageCount: number;
  lastUpdatedAt: string;
  summaryTitle: string;
  status: string;
  changedFiles: string;

  constructor(
    sessionId: string,
    title: string,
    workspaceId: string,
    workspaceName: string,
    workspaceRoot: string,
    workspacePermissionState: WorkspacePermissionState,
    workspaceAccessKind: WorkspaceAccessKind,
    messageCount: number,
    lastUpdatedAt: string,
    summaryTitle: string,
    status: string,
    changedFiles: string
  ) {
    this.sessionId = sessionId;
    this.title = title;
    this.workspaceId = workspaceId;
    this.workspaceName = workspaceName;
    this.workspaceRoot = workspaceRoot;
    this.workspacePermissionState = workspacePermissionState;
    this.workspaceAccessKind = workspaceAccessKind;
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

export class TokenUsageBreakdown {
  inputTokens: number;
  outputTokens: number;
  cachedInputTokens: number;
  reasoningOutputTokens: number;
  totalTokens: number;

  constructor(
    inputTokens: number, outputTokens: number, cachedInputTokens: number,
    reasoningOutputTokens: number, totalTokens: number
  ) {
    this.inputTokens = inputTokens;
    this.outputTokens = outputTokens;
    this.cachedInputTokens = cachedInputTokens;
    this.reasoningOutputTokens = reasoningOutputTokens;
    this.totalTokens = totalTokens;
  }
}

export class TurnTokenUsage {
  total: TokenUsageBreakdown;
  last: TokenUsageBreakdown;
  modelContextWindow: number;

  constructor(total: TokenUsageBreakdown, last: TokenUsageBreakdown, modelContextWindow: number) {
    this.total = total;
    this.last = last;
    this.modelContextWindow = modelContextWindow;
  }
}

export class TokenUsageAggregate {
  today: number;
  thisWeek: number;
  thisMonth: number;

  constructor(today: number, thisWeek: number, thisMonth: number) {
    this.today = today;
    this.thisWeek = thisWeek;
    this.thisMonth = thisMonth;
  }
}
