import webSocket from '@ohos.net.webSocket';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { McpAuthStatus, McpHealthStatus, McpServerRecord, McpSyncStatus, SessionSummary, UsageSummary } from './ConsoleModels';

export type CodexMessageRole = 'user' | 'assistant' | 'system';
export type CodexTurnStatus = 'completed' | 'failed' | 'inProgress' | 'interrupted';
export type CodexDiffKind = 'add' | 'delete' | 'context';
export type CodexConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';
export type CodexApprovalKind = 'command' | 'fileChange' | 'permissions';
export type CodexAuthMode = 'none' | 'apiKey' | 'chatgpt' | 'chatgptAuthTokens' | 'unknown';
export type CodexTurnUpdateHandler = (result: CodexTurnResult) => void;
type BackendListener = (snapshot: CodexBackendSnapshot) => void;

const DEFAULT_SERVER_URL: string = 'ws://127.0.0.1:7456';
const BACKEND_LOG_DOMAIN: number = 0x0ff1;
const BACKEND_LOG_TAG: string = 'CodexBackend';

class EmptyPayload {}

class RpcErrorPayload {
  code: number = 0;
  message: string = '';

  constructor(code: number = 0, message: string = '') {
    this.code = code;
    this.message = message;
  }
}

class RpcEnvelope {
  id?: string | number;
  method?: string;
  params?: Object;
  result?: Object;
  error?: RpcErrorPayload;
}

class RpcRequestEnvelope {
  id: string | number;
  method: string;
  params?: Object;

  constructor(id: string | number, method: string, params?: Object) {
    this.id = id;
    this.method = method;
    this.params = params;
  }
}

class RpcNotificationEnvelope {
  method: string;
  params?: Object;

  constructor(method: string, params?: Object) {
    this.method = method;
    this.params = params;
  }
}

class RpcResultEnvelope {
  id: string | number;
  result: Object;

  constructor(id: string | number, result: Object) {
    this.id = id;
    this.result = result;
  }
}

class RpcErrorEnvelope {
  id: string | number;
  error: RpcErrorPayload;

  constructor(id: string | number, error: RpcErrorPayload) {
    this.id = id;
    this.error = error;
  }
}

class InitializeClientInfo {
  name: string = '';
  title: string = '';
  version: string = '';
}

class InitializeCapabilities {
  experimentalApi: boolean = true;
}

class InitializeRequestParams {
  clientInfo: InitializeClientInfo = new InitializeClientInfo();
  capabilities: InitializeCapabilities = new InitializeCapabilities();
}

class InitializeResultPayload {
  platformOs?: string;
}

class LoginApiKeyRequestParams {
  type: string = 'apiKey';
  apiKey: string = '';

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }
}

class AccountPayload {
  type?: string;
  email?: string;
  planType?: string;
}

class GetAccountRequestParams {
  refreshToken: boolean = false;
}

class GetAccountResponsePayload {
  account?: AccountPayload;
  requiresOpenaiAuth: boolean = true;
}

class AccountUpdatedParams {
  authMode?: string;
  planType?: string;
}

class AccountLoginCompletedParams {
  loginId?: string;
  success: boolean = false;
  error?: string;
}

class McpConfigReadParams {
  includeLayers: boolean = false;
}

class McpConfigBatchEdit {
  keyPath: string = '';
  value: Object | string | number | boolean | null = null;
  mergeStrategy: string = 'replace';

  constructor(keyPath: string, value: Object | string | number | boolean | null, mergeStrategy: string = 'replace') {
    this.keyPath = keyPath;
    this.value = value;
    this.mergeStrategy = mergeStrategy;
  }
}

class McpConfigBatchWriteParams {
  edits: McpConfigBatchEdit[] = [];
  reloadUserConfig: boolean = false;
}

class McpConfigValueWriteParams {
  keyPath: string = '';
  value: Object | string | number | boolean | null = null;
  mergeStrategy: string = 'replace';

  constructor(keyPath: string, value: Object | string | number | boolean | null, mergeStrategy: string = 'replace') {
    this.keyPath = keyPath;
    this.value = value;
    this.mergeStrategy = mergeStrategy;
  }
}

class McpStatusListParams {
  cursor?: string;
  limit?: number;
}

class McpToolPayload {}

class McpResourcePayload {}

class McpServerStatusPayload {
  name: string = '';
  tools: Record<string, McpToolPayload> = {};
  resources: McpResourcePayload[] = [];
  resourceTemplates: Object[] = [];
  authStatus: string = 'unsupported';
}

class McpStatusListResponsePayload {
  data: McpServerStatusPayload[] = [];
  nextCursor: string | null = null;
}

class McpOauthLoginRequestParams {
  name: string = '';

  constructor(serverName: string) {
    this.name = serverName;
  }
}

class McpOauthLoginCompletedParams {
  name: string = '';
  success: boolean = false;
  error?: string;
}

class McpServerStatusUpdatedParams {
  name: string = '';
  status: string = 'starting';
  error: string | null = null;
}

class ThreadPayload {
  id: string = '';
}

class TurnErrorPayload {
  message?: string;
}

class TurnPayload {
  id: string = '';
  status: string = '';
  error?: TurnErrorPayload;
}

class ThreadStartRequestParams {
  cwd?: string;
  model?: string;
}

class ThreadStartResultPayload {
  thread: ThreadPayload = new ThreadPayload();
}

class TextInputPayload {
  type: string = 'text';
  text: string = '';

  constructor(text: string) {
    this.text = text;
  }
}

class TurnStartRequestParams {
  threadId: string = '';
  input: TextInputPayload[] = [];
  cwd?: string;
  model?: string;
  effort?: string;
}

class TurnStartResultPayload {
  turn: TurnPayload = new TurnPayload();
}

class PermissionNetworkPayload {
  enabled?: boolean;

  static cloneFrom(source?: PermissionNetworkPayload): PermissionNetworkPayload | undefined {
    if (source === undefined) {
      return undefined;
    }
    const target: PermissionNetworkPayload = new PermissionNetworkPayload();
    target.enabled = source.enabled;
    return target;
  }
}

class PermissionFileSystemPayload {
  read?: string[];
  write?: string[];

  static cloneFrom(source?: PermissionFileSystemPayload): PermissionFileSystemPayload | undefined {
    if (source === undefined) {
      return undefined;
    }
    const target: PermissionFileSystemPayload = new PermissionFileSystemPayload();
    target.read = source.read === undefined ? undefined : [...source.read];
    target.write = source.write === undefined ? undefined : [...source.write];
    return target;
  }
}

class PermissionsProfilePayload {
  network?: PermissionNetworkPayload;
  fileSystem?: PermissionFileSystemPayload;
}

class PermissionsResponsePayload {
  permissions: PermissionsProfilePayload = new PermissionsProfilePayload();
  scope: string = 'turn';
}

class DecisionResponsePayload {
  decision: string = '';

  constructor(decision: string) {
    this.decision = decision;
  }
}

class ItemPayload {
  type: string = '';
  id: string = '';
  text?: string;
  summary?: string[];
  command?: string;
  cwd?: string;
  status?: string;
  aggregatedOutput?: string;
}

class ItemNotificationParams {
  item: ItemPayload = new ItemPayload();
  threadId: string = '';
  turnId: string = '';
}

class AgentMessageDeltaParams {
  threadId: string = '';
  turnId: string = '';
  itemId: string = '';
  delta: string = '';
}

class RawResponseContentPayload {
  type?: string;
  text?: string;
}

class RawResponseItemPayload {
  type: string = '';
  id?: string;
  role?: string;
  content?: RawResponseContentPayload[];
}

class RawResponseItemCompletedParams {
  threadId: string = '';
  turnId: string = '';
  item: RawResponseItemPayload = new RawResponseItemPayload();
}

class TurnDiffUpdatedParams {
  threadId: string = '';
  turnId: string = '';
  diff: string = '';
}

class PlanStepPayload {
  step: string = '';
  status: string = '';
}

class TurnPlanUpdatedParams {
  threadId: string = '';
  turnId: string = '';
  explanation?: string;
  plan: PlanStepPayload[] = [];
}

class TurnCompletedParams {
  threadId: string = '';
  turn: TurnPayload = new TurnPayload();
}

class CommandApprovalParams {
  threadId: string = '';
  turnId: string = '';
  itemId: string = '';
  reason?: string;
  command?: string;
  cwd?: string;
}

class FileChangeApprovalParams {
  threadId: string = '';
  turnId: string = '';
  itemId: string = '';
  reason?: string;
  grantRoot?: string;
}

class PermissionsApprovalParams {
  threadId: string = '';
  turnId: string = '';
  itemId: string = '';
  reason?: string;
  permissions: PermissionsProfilePayload = new PermissionsProfilePayload();
}

class ParsedDiff {
  lines: CodexDiffLine[] = [];
  diffStat: string = '+0 -0';
  changedFiles: string = '尚未识别变更文件';
}

export class CodexChatMessage {
  messageId: string;
  sequence: number;
  author: string;
  role: CodexMessageRole;
  content: string;
  timestamp: string;

  constructor(
    messageId: string,
    sequence: number,
    author: string,
    role: CodexMessageRole,
    content: string,
    timestamp: string
  ) {
    this.messageId = messageId;
    this.sequence = sequence;
    this.author = author;
    this.role = role;
    this.content = content;
    this.timestamp = timestamp;
  }
}

export class CodexDiffLine {
  lineId: string;
  sequence: number;
  lineNumber: string;
  sign: string;
  content: string;
  kind: CodexDiffKind;

  constructor(
    lineId: string,
    sequence: number,
    lineNumber: string,
    sign: string,
    content: string,
    kind: CodexDiffKind
  ) {
    this.lineId = lineId;
    this.sequence = sequence;
    this.lineNumber = lineNumber;
    this.sign = sign;
    this.content = content;
    this.kind = kind;
  }
}

export class CodexTurnRequest {
  threadKey: string;
  title: string;
  workspaceRoot: string;
  model: string;
  reasoningEffort: string;
  prompt: string;

  constructor(
    threadKey: string,
    title: string,
    workspaceRoot: string,
    model: string,
    reasoningEffort: string,
    prompt: string
  ) {
    this.threadKey = threadKey;
    this.title = title;
    this.workspaceRoot = workspaceRoot;
    this.model = model;
    this.reasoningEffort = reasoningEffort;
    this.prompt = prompt;
  }
}

export class CodexTurnResult {
  threadId: string;
  turnId: string;
  status: CodexTurnStatus;
  messages: CodexChatMessage[];
  diffLines: CodexDiffLine[];
  summaryTitle: string;
  summaryPoints: string[];
  changedFiles: string;
  diffStat: string;

  constructor(
    threadId: string,
    turnId: string,
    status: CodexTurnStatus,
    messages: CodexChatMessage[],
    diffLines: CodexDiffLine[],
    summaryTitle: string,
    summaryPoints: string[],
    changedFiles: string,
    diffStat: string
  ) {
    this.threadId = threadId;
    this.turnId = turnId;
    this.status = status;
    this.messages = messages;
    this.diffLines = diffLines;
    this.summaryTitle = summaryTitle;
    this.summaryPoints = summaryPoints;
    this.changedFiles = changedFiles;
    this.diffStat = diffStat;
  }
}

export class CodexApprovalRequest {
  requestId: string | number;
  kind: CodexApprovalKind;
  title: string;
  detail: string;
  threadId: string;
  turnId: string;
  itemId: string;
  grantedPermissions?: PermissionsProfilePayload;

  constructor(
    requestId: string | number,
    kind: CodexApprovalKind,
    title: string,
    detail: string,
    threadId: string,
    turnId: string,
    itemId: string
  ) {
    this.requestId = requestId;
    this.kind = kind;
    this.title = title;
    this.detail = detail;
    this.threadId = threadId;
    this.turnId = turnId;
    this.itemId = itemId;
  }
}

export class CodexBackendSnapshot {
  serverUrl: string;
  connectionState: CodexConnectionState;
  connectionText: string;
  pendingApproval: CodexApprovalRequest | null;
  authMode: CodexAuthMode;
  requiresOpenAIAuth: boolean;
  authStatusText: string;
  planTypeText: string;
  mcpStatusText: string;
  mcpServerCount: number;
  mcpErrorText: string;

  constructor(
    serverUrl: string,
    connectionState: CodexConnectionState,
    connectionText: string,
    pendingApproval: CodexApprovalRequest | null,
    authMode: CodexAuthMode,
    requiresOpenAIAuth: boolean,
    authStatusText: string,
    planTypeText: string,
    mcpStatusText: string,
    mcpServerCount: number,
    mcpErrorText: string
  ) {
    this.serverUrl = serverUrl;
    this.connectionState = connectionState;
    this.connectionText = connectionText;
    this.pendingApproval = pendingApproval;
    this.authMode = authMode;
    this.requiresOpenAIAuth = requiresOpenAIAuth;
    this.authStatusText = authStatusText;
    this.planTypeText = planTypeText;
    this.mcpStatusText = mcpStatusText;
    this.mcpServerCount = mcpServerCount;
    this.mcpErrorText = mcpErrorText;
  }
}

class PendingRpcRequest {
  resolve: (value: Object) => void;
  reject: (reason: string) => void;

  constructor(resolve: (value: Object) => void, reject: (reason: string) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

class PendingTurnState {
  threadKey: string;
  turnId: string = '';
  listener?: CodexTurnUpdateHandler;
  completion: Promise<CodexTurnResult>;
  resolveCompletion: (result: CodexTurnResult) => void;

  constructor(threadKey: string, listener?: CodexTurnUpdateHandler) {
    this.threadKey = threadKey;
    this.listener = listener;
    this.resolveCompletion = (_result: CodexTurnResult): void => {};
    this.completion = new Promise<CodexTurnResult>((resolve) => {
      this.resolveCompletion = resolve;
    });
  }
}

class CodexThreadRecord {
  localKey: string;
  title: string;
  remoteThreadId: string = '';
  cwd: string = '';
  messages: CodexChatMessage[] = [];
  diffLines: CodexDiffLine[] = [];
  summaryTitle: string = '等待 Codex 响应';
  summaryPoints: string[] = ['连接成功后会在这里显示计划、摘要和关键步骤。'];
  changedFiles: string = '尚未产生文件改动';
  diffStat: string = '+0 -0';
  activeTurn: PendingTurnState | null = null;
  turnCount: number = 0;
  diffUpdateCount: number = 0;
  lastTurnStatus: CodexTurnStatus = 'inProgress';
  updatedAt: string = '';

  constructor(localKey: string, title: string) {
    this.localKey = localKey;
    this.title = title;
    this.updatedAt = this.currentTimestamp();
  }

  private currentTimestamp(): string {
    const now: Date = new Date();
    const hours: string = now.getHours().toString().padStart(2, '0');
    const minutes: string = now.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }
}

export class CodexBackend {
  private socket: webSocket.WebSocket | null = null;
  private initialized: boolean = false;
  private connectionState: CodexConnectionState = 'disconnected';
  private connectionText: string = '未连接';
  private readonly pendingRequests: Map<string, PendingRpcRequest> = new Map();
  private readonly listeners: Map<number, BackendListener> = new Map();
  private readonly threads: Map<string, CodexThreadRecord> = new Map();
  private readonly threadKeysByRemoteId: Map<string, string> = new Map();
  private serverUrl: string = DEFAULT_SERVER_URL;
  private requestSequence: number = 1;
  private listenerSequence: number = 1;
  private connectPromise: Promise<void> | null = null;
  private pendingApproval: CodexApprovalRequest | null = null;
  private authMode: CodexAuthMode = 'none';
  private requiresOpenAIAuth: boolean = true;
  private authStatusText: string = '未登录';
  private planTypeText: string = '';
  private mcpServersCache: McpServerRecord[] = [];
  private readonly mcpConfigByName: Map<string, Object> = new Map();
  private readonly mcpStartupStateByName: Map<string, string> = new Map();
  private readonly mcpStartupErrorByName: Map<string, string> = new Map();
  private mcpStatusText: string = '尚未加载 MCP 状态';
  private mcpErrorText: string = '';

  private logInfo(message: string): void {
    hilog.info(BACKEND_LOG_DOMAIN, BACKEND_LOG_TAG, '%{public}s', message);
  }

  private messagePreview(text: string, maxLength: number = 120): string {
    const normalized: string = text.replace(/\s+/g, ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return `${normalized.slice(0, maxLength)}...`;
  }

  subscribe(listener: BackendListener): number {
    const subscriptionId: number = this.listenerSequence;
    this.listenerSequence += 1;
    this.listeners.set(subscriptionId, listener);
    return subscriptionId;
  }

  unsubscribe(subscriptionId: number): void {
    this.listeners.delete(subscriptionId);
  }

  snapshot(): CodexBackendSnapshot {
    return new CodexBackendSnapshot(
      this.serverUrl,
      this.connectionState,
      this.connectionText,
      this.cloneApproval(this.pendingApproval),
      this.authMode,
      this.requiresOpenAIAuth,
      this.authStatusText,
      this.planTypeText,
      this.mcpStatusText,
      this.mcpServersCache.length,
      this.mcpErrorText
    );
  }

  sessionSummaries(): SessionSummary[] {
    const sessions: SessionSummary[] = [];
    this.threads.forEach((thread: CodexThreadRecord) => {
      const lastMessageTimestamp: string = thread.messages.length > 0
        ? thread.messages[thread.messages.length - 1].timestamp
        : thread.updatedAt;
      sessions.push(
        new SessionSummary(
          thread.localKey,
          thread.title,
          thread.cwd,
          thread.messages.length,
          lastMessageTimestamp,
          thread.summaryTitle,
          thread.lastTurnStatus,
          thread.changedFiles
        )
      );
    });
    return sessions.sort((left: SessionSummary, right: SessionSummary) => {
      if (left.lastUpdatedAt === right.lastUpdatedAt) {
        return left.title.localeCompare(right.title);
      }
      return left.lastUpdatedAt < right.lastUpdatedAt ? 1 : -1;
    });
  }

  usageSummary(): UsageSummary {
    let activeTurnCount: number = 0;
    let turnCount: number = 0;
    let messageCount: number = 0;
    let diffLineCount: number = 0;
    let diffUpdateCount: number = 0;
    let lastTurnStatus: string = '尚无会话';
    this.threads.forEach((thread: CodexThreadRecord) => {
      if (thread.activeTurn !== null) {
        activeTurnCount += 1;
      }
      turnCount += thread.turnCount;
      messageCount += thread.messages.length;
      diffLineCount += thread.diffLines.length;
      diffUpdateCount += thread.diffUpdateCount;
      lastTurnStatus = thread.lastTurnStatus;
    });
    return new UsageSummary(
      this.threads.size,
      activeTurnCount,
      turnCount,
      messageCount,
      diffLineCount,
      diffUpdateCount,
      lastTurnStatus
    );
  }

  resultForThreadKey(threadKey: string): CodexTurnResult | null {
    const thread: CodexThreadRecord | undefined = this.threads.get(threadKey);
    if (thread === undefined) {
      return null;
    }
    return this.snapshotForThread(thread, thread.lastTurnStatus);
  }

  mcpServers(): McpServerRecord[] {
    return this.mcpServersCache.map((server: McpServerRecord) => this.cloneMcpServer(server));
  }

  mcpConfig(serverName: string): Object | null {
    return this.mcpConfigByName.get(serverName) ?? null;
  }

  async refreshMcpServers(): Promise<McpServerRecord[]> {
    await this.ensureConnected();
    await this.readMcpConfig();
    const params: McpStatusListParams = new McpStatusListParams();
    params.limit = 100;
    const payload: Object = await this.sendRpcRequest(
      new RpcRequestEnvelope(this.nextRequestId(), 'mcpServerStatus/list', params)
    );
    const response: McpStatusListResponsePayload = payload as McpStatusListResponsePayload;
    this.mcpServersCache = response.data.map((item: McpServerStatusPayload) => this.buildMcpServerRecord(item));
    this.mcpStatusText = this.mcpServersCache.length > 0
      ? `已加载 ${this.mcpServersCache.length} 个 MCP server`
      : '当前没有已配置的 MCP server';
    this.mcpErrorText = '';
    this.notifyListeners();
    return this.mcpServers();
  }

  async reloadMcpServers(): Promise<void> {
    await this.ensureConnected();
    await this.sendRpcRequest(new RpcRequestEnvelope(this.nextRequestId(), 'config/mcpServer/reload', new EmptyPayload()));
    this.mcpStatusText = 'MCP 配置已重载';
    this.mcpErrorText = '';
    await this.refreshMcpServers();
  }

  async writeMcpConfigValue(keyPath: string, value: Object | string | number | boolean | null): Promise<void> {
    await this.ensureConnected();
    await this.sendRpcRequest(
      new RpcRequestEnvelope(this.nextRequestId(), 'config/value/write', new McpConfigValueWriteParams(keyPath, value))
    );
    this.mcpStatusText = `已更新 ${keyPath}`;
    this.mcpErrorText = '';
    this.notifyListeners();
  }

  async batchWriteMcpConfig(edits: McpConfigBatchEdit[]): Promise<void> {
    await this.ensureConnected();
    const params: McpConfigBatchWriteParams = new McpConfigBatchWriteParams();
    params.edits = edits;
    params.reloadUserConfig = true;
    await this.sendRpcRequest(new RpcRequestEnvelope(this.nextRequestId(), 'config/batchWrite', params));
    this.mcpStatusText = 'MCP 配置已保存';
    this.mcpErrorText = '';
    this.notifyListeners();
  }

  async saveMcpServerConfig(
    serverName: string,
    enabled: boolean,
    transportType: string,
    command: string,
    argsText: string,
    url: string,
    envText: string
  ): Promise<void> {
    await this.ensureConnected();
    await this.readMcpConfig();
    const existingConfig: Record<string, Object> = this.copyConfigObject(
      (this.mcpConfigByName.get(serverName) as Record<string, Object> | undefined) ?? {}
    );
    const nextConfig: Record<string, Object> = this.copyConfigObject(existingConfig);
    nextConfig['enabled'] = enabled;
    const parsedArgs: Object = this.parseJsonText(argsText, JSON.parse('[]') as Object);
    const parsedEnv: Object = this.parseJsonText(envText, JSON.parse('{}') as Object);
    nextConfig['args'] = parsedArgs;
    nextConfig['env'] = parsedEnv;
    if (transportType === 'http') {
      nextConfig['url'] = url.trim();
      nextConfig['command'] = '';
    } else {
      nextConfig['command'] = command.trim();
      nextConfig['url'] = '';
    }
    await this.batchWriteMcpConfig([
      new McpConfigBatchEdit(`mcp_servers.${serverName}`, nextConfig)
    ]);
    await this.reloadMcpServers();
  }

  async startMcpOAuthLogin(serverName: string): Promise<void> {
    await this.ensureConnected();
    await this.sendRpcRequest(
      new RpcRequestEnvelope(this.nextRequestId(), 'mcpServer/oauth/login', new McpOauthLoginRequestParams(serverName))
    );
    this.mcpStatusText = `已为 ${serverName} 发起 OAuth 登录`;
    this.mcpErrorText = '';
    this.notifyListeners();
  }

  configureServerUrl(serverUrl: string): void {
    const nextServerUrl: string = serverUrl.trim();
    this.serverUrl = nextServerUrl.length > 0 ? nextServerUrl : DEFAULT_SERVER_URL;
    this.notifyListeners();
  }

  async connect(): Promise<void> {
    await this.ensureConnected();
  }

  async disconnect(): Promise<void> {
    this.connectPromise = null;
    this.initialized = false;
    this.rejectAllPendingRequests('WebSocket 已断开。');
    if (this.socket !== null) {
      try {
        await this.socket.close();
      } catch (_err) {
      }
      this.socket = null;
    }
    this.updateConnectionState('disconnected', '已断开连接');
  }

  async loginWithApiKey(apiKey: string): Promise<void> {
    const trimmedApiKey: string = apiKey.trim();
    if (trimmedApiKey.length === 0) {
      throw new Error('è¯·è¾“å…¥æœ‰æ•ˆçš„ OpenAI API Keyã€‚');
    }

    await this.ensureConnected();
    await this.sendRpcRequest(
      new RpcRequestEnvelope(
        this.nextRequestId(),
        'account/login/start',
        new LoginApiKeyRequestParams(trimmedApiKey)
      )
    );
    await this.refreshAccountState();
  }

  async approvePendingRequest(): Promise<void> {
    if (this.pendingApproval === null) {
      return;
    }

    const request: CodexApprovalRequest = this.pendingApproval;
    this.pendingApproval = null;
    this.notifyListeners();

    if (request.kind === 'permissions') {
      const response: PermissionsResponsePayload = new PermissionsResponsePayload();
      response.permissions = request.grantedPermissions ?? new PermissionsProfilePayload();
      await this.sendServerRequestResult(new RpcResultEnvelope(request.requestId, response));
      return;
    }

    await this.sendServerRequestResult(
      new RpcResultEnvelope(request.requestId, new DecisionResponsePayload('accept'))
    );
  }

  async declinePendingRequest(): Promise<void> {
    if (this.pendingApproval === null) {
      return;
    }

    const request: CodexApprovalRequest = this.pendingApproval;
    this.pendingApproval = null;
    this.notifyListeners();

    if (request.kind === 'permissions') {
      await this.sendServerRequestResult(
        new RpcResultEnvelope(request.requestId, new PermissionsResponsePayload())
      );
      return;
    }

    await this.sendServerRequestResult(
      new RpcResultEnvelope(request.requestId, new DecisionResponsePayload('decline'))
    );
  }

  async startTurn(request: CodexTurnRequest, onUpdate?: CodexTurnUpdateHandler): Promise<CodexTurnResult> {
    await this.ensureConnected();
    if (this.requiresOpenAIAuth && this.authMode === 'none') {
      throw new Error('å½“å‰åŽç«¯å°šæœªç™»å½• OpenAIã€‚è¯·å…ˆå¡«å†™ API Key å¹¶ç™»å½•ã€‚');
    }
    const thread: CodexThreadRecord = await this.ensureRemoteThread(request);
    const pendingTurn: PendingTurnState = new PendingTurnState(request.threadKey, onUpdate);
    thread.activeTurn = pendingTurn;
    if (request.workspaceRoot.trim().length > 0) {
      thread.cwd = request.workspaceRoot.trim();
    }

    const startedSnapshot: CodexTurnResult = this.beginLocalTurn(thread, request.prompt);
    this.emitTurnUpdate(thread, pendingTurn, startedSnapshot);

    const params: TurnStartRequestParams = new TurnStartRequestParams();
    params.threadId = thread.remoteThreadId;
    params.input = [new TextInputPayload(request.prompt)];
    if (request.workspaceRoot.trim().length > 0) {
      params.cwd = request.workspaceRoot.trim();
    }
    if (request.model !== 'default') {
      params.model = request.model;
    }
    if (request.reasoningEffort !== 'default') {
      params.effort = request.reasoningEffort;
    }

    try {
      const payload: Object = await this.sendRpcRequest(new RpcRequestEnvelope(this.nextRequestId(), 'turn/start', params));
      const result: TurnStartResultPayload = payload as TurnStartResultPayload;
      if (result.turn !== undefined && result.turn.id.length > 0) {
        pendingTurn.turnId = result.turn.id;
      }
      return await pendingTurn.completion;
    } catch (err) {
      return this.failTurn(thread, pendingTurn, this.describeError(err));
    }
  }

  private async ensureConnected(): Promise<void> {
    if (this.initialized && this.socket !== null) {
      return;
    }
    if (this.connectPromise !== null) {
      await this.connectPromise;
      return;
    }

    this.connectPromise = this.openSocketAndInitialize();
    try {
      await this.connectPromise;
    } finally {
      this.connectPromise = null;
    }
  }

  private async openSocketAndInitialize(): Promise<void> {
    this.updateConnectionState('connecting', `连接中：${this.serverUrl}`);
    const socket: webSocket.WebSocket = webSocket.createWebSocket();
    this.bindSocket(socket);
    this.socket = socket;

    try {
      await socket.connect(this.serverUrl);
      const initializeParams: InitializeRequestParams = new InitializeRequestParams();
      initializeParams.clientInfo.name = 'codex_harmony_agent';
      initializeParams.clientInfo.title = 'Codex Harmony Agent';
      initializeParams.clientInfo.version = '0.1.0';
      initializeParams.capabilities.experimentalApi = true;
      const initializeResultObject: Object = await this.sendRpcRequest(
        new RpcRequestEnvelope(this.nextRequestId(), 'initialize', initializeParams)
      );
      await this.sendNotification(new RpcNotificationEnvelope('initialized'));
      this.initialized = true;
      await this.refreshAccountState();
      const initializeResult: InitializeResultPayload = initializeResultObject as InitializeResultPayload;
      const platformOs: string = initializeResult.platformOs ?? 'unknown';
      this.updateConnectionState('connected', `已连接 · ${platformOs}`);
    } catch (err) {
      this.initialized = false;
      this.updateConnectionState('error', `连接失败：${this.describeError(err)}`);
      if (this.socket !== null) {
        try {
          await this.socket.close();
        } catch (_closeErr) {
        }
      }
      this.socket = null;
      throw new Error(this.describeError(err));
    }
  }

  private bindSocket(socket: webSocket.WebSocket): void {
    socket.on('message', (_err, data) => {
      if (typeof data !== 'string') {
        return;
      }
      this.handleSocketMessage(data);
    });
    socket.on('close', (_err, result) => {
      this.initialized = false;
      this.socket = null;
      this.rejectAllPendingRequests('WebSocket 连接已关闭。');
      const closeReason: string = result !== undefined && result.reason.length > 0 ? result.reason : '连接关闭';
      this.updateConnectionState('disconnected', closeReason);
    });
    socket.on('error', (err) => {
      this.initialized = false;
      this.rejectAllPendingRequests('WebSocket 出现错误。');
      this.updateConnectionState('error', `连接异常：${this.describeError(err)}`);
    });
  }

  private handleSocketMessage(text: string): void {
    const envelope: RpcEnvelope | null = this.parseEnvelope(text);
    if (envelope === null) {
      return;
    }

    if (envelope.method === undefined && envelope.id !== undefined) {
      const pendingRequest: PendingRpcRequest | undefined = this.pendingRequests.get(envelope.id.toString());
      if (pendingRequest === undefined) {
        return;
      }
      this.pendingRequests.delete(envelope.id.toString());
      if (envelope.error !== undefined) {
        pendingRequest.reject(envelope.error.message);
        return;
      }
      pendingRequest.resolve(envelope.result ?? new EmptyPayload());
      return;
    }

    if (envelope.method === undefined) {
      return;
    }

    if (envelope.id !== undefined) {
      void this.handleServerRequest(envelope.method, envelope.id, envelope.params);
      return;
    }

    this.handleNotification(envelope.method, envelope.params);
  }

  private async handleServerRequest(method: string, requestId: string | number, paramsObject?: Object): Promise<void> {
    if (method === 'item/commandExecution/requestApproval') {
      const approval: CodexApprovalRequest = this.buildCommandApproval(requestId, paramsObject as CommandApprovalParams);
      this.pendingApproval = approval;
      this.notifyListeners();
      return;
    }

    if (method === 'item/fileChange/requestApproval') {
      const approval: CodexApprovalRequest = this.buildFileChangeApproval(requestId, paramsObject as FileChangeApprovalParams);
      this.pendingApproval = approval;
      this.notifyListeners();
      return;
    }

    if (method === 'item/permissions/requestApproval') {
      const approval: CodexApprovalRequest = this.buildPermissionsApproval(requestId, paramsObject as PermissionsApprovalParams);
      this.pendingApproval = approval;
      this.notifyListeners();
      return;
    }

    await this.sendServerRequestError(
      new RpcErrorEnvelope(requestId, new RpcErrorPayload(-32001, `Harmony 前端暂不支持 ${method}`))
    );
  }

  private handleNotification(method: string, paramsObject?: Object): void {
    if (method === 'account/updated') {
      this.handleAccountUpdated(paramsObject as AccountUpdatedParams);
      return;
    }

    if (method === 'account/login/completed') {
      this.handleAccountLoginCompleted(paramsObject as AccountLoginCompletedParams);
      return;
    }

    if (method === 'item/started') {
      this.handleItemStarted(paramsObject as ItemNotificationParams);
      return;
    }

    if (method === 'item/completed') {
      this.handleItemCompleted(paramsObject as ItemNotificationParams);
      return;
    }

    if (method === 'rawResponseItem/completed') {
      this.handleRawResponseItemCompleted(paramsObject as RawResponseItemCompletedParams);
      return;
    }

    if (method === 'item/agentMessage/delta') {
      this.handleAgentMessageDelta(paramsObject as AgentMessageDeltaParams);
      return;
    }

    if (method === 'turn/diff/updated') {
      this.handleTurnDiffUpdated(paramsObject as TurnDiffUpdatedParams);
      return;
    }

    if (method === 'turn/plan/updated') {
      this.handleTurnPlanUpdated(paramsObject as TurnPlanUpdatedParams);
      return;
    }

    if (method === 'turn/completed') {
      this.handleTurnCompleted(paramsObject as TurnCompletedParams);
      return;
    }

    if (method === 'mcpServer/startupStatus/updated') {
      this.handleMcpServerStatusUpdated(paramsObject as McpServerStatusUpdatedParams);
      return;
    }

    if (method === 'mcpServer/oauthLogin/completed') {
      this.handleMcpOauthLoginCompleted(paramsObject as McpOauthLoginCompletedParams);
      return;
    }

    if (method === 'serverRequest/resolved') {
      this.pendingApproval = null;
      this.notifyListeners();
    }
  }

  private async refreshAccountState(): Promise<void> {
    const payload: Object = await this.sendRpcRequest(
      new RpcRequestEnvelope(this.nextRequestId(), 'account/read', new GetAccountRequestParams())
    );
    this.applyAccountState(payload as GetAccountResponsePayload);
  }

  private handleAccountUpdated(params?: AccountUpdatedParams): void {
    if (params === undefined) {
      return;
    }

    this.authMode = this.normalizeAuthMode(params.authMode);
    this.planTypeText = params.planType ?? '';
    this.authStatusText = this.authStatusFromMode(this.authMode);
    this.notifyListeners();
  }

  private handleAccountLoginCompleted(params?: AccountLoginCompletedParams): void {
    if (params === undefined) {
      return;
    }

    if (!params.success) {
      this.authStatusText = params.error ?? 'ç™»å½•å¤±è´¥';
      this.notifyListeners();
    }
  }

  private handleMcpServerStatusUpdated(params?: McpServerStatusUpdatedParams): void {
    if (params === undefined || params.name.trim().length === 0) {
      return;
    }
    this.mcpStartupStateByName.set(params.name, params.status);
    if (params.error !== null && params.error.trim().length > 0) {
      this.mcpStartupErrorByName.set(params.name, params.error);
      this.mcpErrorText = params.error;
    } else {
      this.mcpStartupErrorByName.delete(params.name);
    }
    this.mcpStatusText = `${params.name} · ${params.status}`;
    this.mcpServersCache = this.mcpServersCache.map((server: McpServerRecord) => {
      if (server.name !== params.name) {
        return server;
      }
      return new McpServerRecord(
        server.id,
        server.name,
        server.enabled,
        server.transportType,
        server.command,
        server.argsText,
        server.url,
        server.envText,
        server.toolCount,
        server.resourceCount,
        this.normalizeMcpHealthStatus(params.status, params.error),
        server.authStatus,
        params.error ?? '',
        params.error !== null && params.error.trim().length > 0 ? 'error' : server.syncStatus,
        this.currentTimestamp()
      );
    });
    this.notifyListeners();
  }

  private handleMcpOauthLoginCompleted(params?: McpOauthLoginCompletedParams): void {
    if (params === undefined) {
      return;
    }
    if (params.success) {
      this.mcpStatusText = `${params.name} OAuth 登录已完成`;
      this.mcpErrorText = '';
    } else {
      this.mcpStatusText = `${params.name} OAuth 登录失败`;
      this.mcpErrorText = params.error ?? 'OAuth 登录失败';
    }
    this.notifyListeners();
  }

  private applyAccountState(payload: GetAccountResponsePayload): void {
    this.requiresOpenAIAuth = payload.requiresOpenaiAuth !== false;
    if (!this.requiresOpenAIAuth) {
      this.authMode = 'unknown';
      this.authStatusText = 'å½“å‰æ¨¡åž‹æä¾›æ–¹ä¸è¦æ±‚ OpenAI è®¤è¯';
      this.planTypeText = '';
      this.notifyListeners();
      return;
    }

    const account: AccountPayload | undefined = payload.account;
    if (account === undefined) {
      this.authMode = 'none';
      this.authStatusText = 'æœªç™»å½•';
      this.planTypeText = '';
      this.notifyListeners();
      return;
    }

    this.authMode = this.normalizeAuthMode(account.type);
    if (this.authMode === 'chatgpt' || this.authMode === 'chatgptAuthTokens') {
      this.authStatusText = account.email ?? 'å·²ç™»å½• ChatGPT';
    } else if (this.authMode === 'apiKey') {
      this.authStatusText = 'å·²ä½¿ç”¨ API Key ç™»å½•';
    } else {
      this.authStatusText = 'å·²ç™»å½•';
    }
    this.planTypeText = account.planType ?? this.planTypeText;
    this.notifyListeners();
  }

  private normalizeAuthMode(rawMode?: string): CodexAuthMode {
    if (rawMode === 'apiKey') {
      return 'apiKey';
    }
    if (rawMode === 'chatgpt') {
      return 'chatgpt';
    }
    if (rawMode === 'chatgptAuthTokens') {
      return 'chatgptAuthTokens';
    }
    if (rawMode === undefined || rawMode.length === 0) {
      return 'none';
    }
    return 'unknown';
  }

  private authStatusFromMode(authMode: CodexAuthMode): string {
    if (authMode === 'apiKey') {
      return 'å·²ä½¿ç”¨ API Key ç™»å½•';
    }
    if (authMode === 'chatgpt') {
      return 'å·²ç™»å½• ChatGPT';
    }
    if (authMode === 'chatgptAuthTokens') {
      return 'å·²æŽ¥å…¥å¤–éƒ¨ ChatGPT Token';
    }
    if (authMode === 'none') {
      return 'æœªç™»å½•';
    }
    return 'è®¤è¯çŠ¶æ€�æœªçŸ¥';
  }

  private handleItemStarted(params: ItemNotificationParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null) {
      return;
    }

    if (params.item.type === 'agentMessage') {
      this.upsertMessage(thread, params.item.id, 'Codex', 'assistant', '', this.currentTimestamp());
      this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
      return;
    }

    if (params.item.type === 'commandExecution') {
      const command: string = params.item.command ?? '命令';
      this.upsertMessage(
        thread,
        `tool-${params.item.id}`,
        '系统',
        'system',
        `正在运行命令：${command}`,
        this.currentTimestamp()
      );
      this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
    }
  }

  private handleItemCompleted(params: ItemNotificationParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null) {
      return;
    }

    if (params.item.type === 'agentMessage') {
      const finalText: string = this.mergeAssistantMessageContent(thread, params.item.id, params.item.text ?? '');
      this.upsertMessage(
        thread,
        params.item.id,
        'Codex',
        'assistant',
        finalText,
        this.currentTimestamp()
      );
      this.logInfo(
        `item completed agentMessage thread=${params.threadId} turn=${params.turnId} item=${params.item.id} ` +
        `itemTextLen=${(params.item.text ?? '').length} mergedLen=${finalText.length} ` +
        `preview=${this.messagePreview(finalText)}`
      );
      this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
      return;
    }

    if (params.item.type === 'reasoning' && params.item.summary !== undefined && params.item.summary.length > 0) {
      thread.summaryTitle = '模型推理摘要';
      thread.summaryPoints = [...params.item.summary];
      this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
      return;
    }

    if (params.item.type === 'commandExecution') {
      const command: string = params.item.command ?? '命令';
      const output: string = params.item.aggregatedOutput ?? '';
      const content: string = output.trim().length > 0
        ? `命令已完成：${command}\n${this.truncate(output.trim(), 280)}`
        : `命令已完成：${command}`;
      this.upsertMessage(thread, `tool-${params.item.id}`, '系统', 'system', content, this.currentTimestamp());
      this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
      return;
    }

    if (params.item.type === 'fileChange') {
      this.upsertMessage(
        thread,
        `file-${params.item.id}`,
        '系统',
        'system',
        '已收到文件改动结果，右侧 diff 已刷新。',
        this.currentTimestamp()
      );
      this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
    }
  }

  private handleAgentMessageDelta(params: AgentMessageDeltaParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null) {
      return;
    }

    const existingIndex: number = this.findMessageIndex(thread, params.itemId);
    if (existingIndex >= 0) {
      const existing: CodexChatMessage = thread.messages[existingIndex];
      thread.messages[existingIndex] = new CodexChatMessage(
        existing.messageId,
        existing.sequence,
        existing.author,
        existing.role,
        existing.content + params.delta,
        existing.timestamp
      );
    } else {
      this.upsertMessage(thread, params.itemId, 'Codex', 'assistant', params.delta, this.currentTimestamp());
    }

    const currentText: string = this.findMessageIndex(thread, params.itemId) >= 0
      ? thread.messages[this.findMessageIndex(thread, params.itemId)].content
      : params.delta;
    this.logInfo(
      `agent delta thread=${params.threadId} turn=${params.turnId} item=${params.itemId} ` +
      `deltaLen=${params.delta.length} totalLen=${currentText.length} ` +
      `preview=${this.messagePreview(currentText)}`
    );
    this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
  }

  private handleRawResponseItemCompleted(params: RawResponseItemCompletedParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null) {
      return;
    }

    const item: RawResponseItemPayload = params.item;
    if (item.type !== 'message' || item.role !== 'assistant') {
      return;
    }

    const finalText: string = this.extractRawAssistantText(item);
    if (finalText.length === 0) {
      return;
    }

    if (item.id !== undefined && item.id.length > 0) {
      const merged: string = this.mergeAssistantMessageContent(thread, item.id, finalText);
      this.upsertMessage(thread, item.id, 'Codex', 'assistant', merged, this.currentTimestamp());
    } else {
      this.updateLatestAssistantMessageContent(thread, finalText);
    }

    const lastAssistantText: string = this.latestAssistantMessageContent(thread);
    this.logInfo(
      `raw response completed thread=${params.threadId} turn=${params.turnId} item=${item.id ?? 'unknown'} ` +
      `rawLen=${finalText.length} mergedLen=${lastAssistantText.length} ` +
      `preview=${this.messagePreview(lastAssistantText)}`
    );
    this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
  }

  private handleTurnDiffUpdated(params: TurnDiffUpdatedParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null) {
      return;
    }

    const parsed: ParsedDiff = this.parseUnifiedDiff(params.diff);
    thread.diffLines = parsed.lines;
    thread.diffStat = parsed.diffStat;
    thread.changedFiles = parsed.changedFiles;
    thread.diffUpdateCount += 1;
    thread.updatedAt = this.currentTimestamp();
    this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
  }

  private handleTurnPlanUpdated(params: TurnPlanUpdatedParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null) {
      return;
    }

    const points: string[] = [];
    params.plan.forEach((step: PlanStepPayload) => {
      points.push(`${this.planStatusLabel(step.status)} ${step.step}`);
    });

    thread.summaryTitle = params.explanation ?? '执行计划';
    thread.summaryPoints = points.length > 0 ? points : ['尚未返回结构化计划。'];
    this.emitTurnUpdate(thread, thread.activeTurn, this.snapshotForThread(thread, 'inProgress'));
  }

  private handleTurnCompleted(params: TurnCompletedParams): void {
    const thread: CodexThreadRecord | null = this.threadFromRemoteId(params.threadId);
    if (thread === null || thread.activeTurn === null) {
      return;
    }

    const status: CodexTurnStatus = this.mapTurnStatus(params.turn.status);
    thread.lastTurnStatus = status;
    thread.updatedAt = this.currentTimestamp();
    if (status === 'failed') {
      const message: string = params.turn.error?.message ?? '未知错误';
      this.upsertMessage(
        thread,
        `turn-error-${Date.now()}`,
        '系统',
        'system',
        `本轮执行失败：${message}`,
        this.currentTimestamp()
      );
    }

    const turnId: string = thread.activeTurn.turnId.length > 0 ? thread.activeTurn.turnId : params.turn.id;
    const finalAssistantText: string = this.latestAssistantMessageContent(thread);
    this.logInfo(
      `turn completed thread=${params.threadId} turn=${turnId} status=${status} ` +
      `lastAssistantLen=${finalAssistantText.length} preview=${this.messagePreview(finalAssistantText)}`
    );
    const snapshot: CodexTurnResult = this.snapshotForThread(thread, status, turnId);
    const activeTurn: PendingTurnState = thread.activeTurn;
    thread.activeTurn = null;
    this.emitTurnUpdate(thread, activeTurn, snapshot);
    activeTurn.resolveCompletion(snapshot);
  }

  private async ensureRemoteThread(request: CodexTurnRequest): Promise<CodexThreadRecord> {
    const existing: CodexThreadRecord | undefined = this.threads.get(request.threadKey);
    if (existing !== undefined && existing.remoteThreadId.length > 0) {
      existing.title = request.title;
      return existing;
    }

    const thread: CodexThreadRecord = existing ?? new CodexThreadRecord(request.threadKey, request.title);
    const params: ThreadStartRequestParams = new ThreadStartRequestParams();
    if (request.workspaceRoot.trim().length > 0) {
      params.cwd = request.workspaceRoot.trim();
      thread.cwd = request.workspaceRoot.trim();
    }
    if (request.model !== 'default') {
      params.model = request.model;
    }

    const payload: Object = await this.sendRpcRequest(
      new RpcRequestEnvelope(this.nextRequestId(), 'thread/start', params)
    );
    const result: ThreadStartResultPayload = payload as ThreadStartResultPayload;
    if (result.thread === undefined || result.thread.id.length === 0) {
      throw new Error('thread/start 未返回 thread.id');
    }

    thread.remoteThreadId = result.thread.id;
    this.threads.set(request.threadKey, thread);
    this.threadKeysByRemoteId.set(result.thread.id, request.threadKey);
    return thread;
  }

  private beginLocalTurn(thread: CodexThreadRecord, prompt: string): CodexTurnResult {
    this.upsertMessage(thread, `user-${Date.now()}`, '你', 'user', prompt, this.currentTimestamp());
    thread.turnCount += 1;
    thread.lastTurnStatus = 'inProgress';
    thread.updatedAt = this.currentTimestamp();
    thread.summaryTitle = '正在等待 Codex 响应';
    thread.summaryPoints = ['已发送请求，等待 app-server 返回 streaming 结果。'];
    return this.snapshotForThread(thread, 'inProgress');
  }

  private failTurn(thread: CodexThreadRecord, pendingTurn: PendingTurnState, message: string): CodexTurnResult {
    this.upsertMessage(
      thread,
      `local-error-${Date.now()}`,
      '系统',
      'system',
      `调用 app-server 失败：${message}`,
      this.currentTimestamp()
    );
    thread.lastTurnStatus = 'failed';
    thread.updatedAt = this.currentTimestamp();
    thread.summaryTitle = '调用失败';
    thread.summaryPoints = [message];
    const failed: CodexTurnResult = this.snapshotForThread(thread, 'failed');
    thread.activeTurn = null;
    this.emitTurnUpdate(thread, pendingTurn, failed);
    pendingTurn.resolveCompletion(failed);
    return failed;
  }

  private snapshotForThread(thread: CodexThreadRecord, status: CodexTurnStatus, turnId: string = ''): CodexTurnResult {
    return new CodexTurnResult(
      thread.remoteThreadId,
      turnId,
      status,
      thread.messages.map((message: CodexChatMessage) => this.cloneMessage(message)),
      thread.diffLines.map((line: CodexDiffLine) => this.cloneDiffLine(line)),
      thread.summaryTitle,
      [...thread.summaryPoints],
      thread.changedFiles,
      thread.diffStat
    );
  }

  private emitTurnUpdate(
    thread: CodexThreadRecord,
    pendingTurn: PendingTurnState | null,
    result: CodexTurnResult
  ): void {
    if (pendingTurn !== null && pendingTurn.listener !== undefined) {
      pendingTurn.listener(result);
    }
    if (thread.activeTurn !== null && thread.activeTurn !== pendingTurn && thread.activeTurn.listener !== undefined) {
      thread.activeTurn.listener(result);
    }
  }

  private upsertMessage(
    thread: CodexThreadRecord,
    messageId: string,
    author: string,
    role: CodexMessageRole,
    content: string,
    timestamp: string
  ): void {
    const index: number = this.findMessageIndex(thread, messageId);
    if (index >= 0) {
      const current: CodexChatMessage = thread.messages[index];
      thread.messages[index] = new CodexChatMessage(
        current.messageId,
        current.sequence,
        author,
        role,
        content,
        timestamp
      );
      return;
    }

    thread.messages.push(
      new CodexChatMessage(messageId, thread.messages.length + 1, author, role, content, timestamp)
    );
  }

  private mergeAssistantMessageContent(
    thread: CodexThreadRecord,
    messageId: string,
    completedText: string
  ): string {
    const existingIndex: number = this.findMessageIndex(thread, messageId);
    const existingText: string = existingIndex >= 0 ? thread.messages[existingIndex].content : '';
    if (completedText.length === 0) {
      return existingText;
    }
    if (existingText.length === 0) {
      return completedText;
    }
    if (completedText.length >= existingText.length) {
      return completedText;
    }
    return existingText;
  }

  private extractRawAssistantText(item: RawResponseItemPayload): string {
    if (item.content === undefined || item.content.length === 0) {
      return '';
    }

    const parts: string[] = [];
    item.content.forEach((contentItem: RawResponseContentPayload) => {
      if (contentItem.type === 'output_text' && contentItem.text !== undefined) {
        parts.push(contentItem.text);
      }
    });
    return parts.join('');
  }

  private updateLatestAssistantMessageContent(thread: CodexThreadRecord, completedText: string): void {
    for (let index: number = thread.messages.length - 1; index >= 0; index -= 1) {
      const current: CodexChatMessage = thread.messages[index];
      if (current.role !== 'assistant') {
        continue;
      }
      const nextText: string = completedText.length >= current.content.length ? completedText : current.content;
      thread.messages[index] = new CodexChatMessage(
        current.messageId,
        current.sequence,
        current.author,
        current.role,
        nextText,
        current.timestamp
      );
      return;
    }
  }

  private latestAssistantMessageContent(thread: CodexThreadRecord): string {
    for (let index: number = thread.messages.length - 1; index >= 0; index -= 1) {
      const current: CodexChatMessage = thread.messages[index];
      if (current.role === 'assistant') {
        return current.content;
      }
    }
    return '';
  }

  private findMessageIndex(thread: CodexThreadRecord, messageId: string): number {
    for (let index: number = 0; index < thread.messages.length; index += 1) {
      if (thread.messages[index].messageId === messageId) {
        return index;
      }
    }
    return -1;
  }

  private buildCommandApproval(requestId: string | number, params: CommandApprovalParams): CodexApprovalRequest {
    const command: string = params.command ?? '未命名命令';
    const reason: string = params.reason ?? 'Codex 请求执行命令';
    const detail: string = params.cwd !== undefined && params.cwd.length > 0
      ? `${reason}\n命令：${command}\n目录：${params.cwd}`
      : `${reason}\n命令：${command}`;
    return new CodexApprovalRequest(requestId, 'command', '需要执行命令', detail, params.threadId, params.turnId, params.itemId);
  }

  private buildFileChangeApproval(requestId: string | number, params: FileChangeApprovalParams): CodexApprovalRequest {
    const reason: string = params.reason ?? 'Codex 请求写入文件';
    const detail: string = params.grantRoot !== undefined && params.grantRoot.length > 0
      ? `${reason}\n授权根目录：${params.grantRoot}`
      : reason;
    return new CodexApprovalRequest(requestId, 'fileChange', '需要写入文件', detail, params.threadId, params.turnId, params.itemId);
  }

  private buildPermissionsApproval(requestId: string | number, params: PermissionsApprovalParams): CodexApprovalRequest {
    const details: string[] = [params.reason ?? 'Codex 请求额外权限'];
    if (params.permissions.fileSystem?.write !== undefined && params.permissions.fileSystem.write.length > 0) {
      details.push(`写权限：${params.permissions.fileSystem.write.join(', ')}`);
    }
    if (params.permissions.fileSystem?.read !== undefined && params.permissions.fileSystem.read.length > 0) {
      details.push(`读权限：${params.permissions.fileSystem.read.join(', ')}`);
    }
    if (params.permissions.network?.enabled === true) {
      details.push('网络权限：已请求开启');
    }

    const approval: CodexApprovalRequest = new CodexApprovalRequest(
      requestId,
      'permissions',
      '需要额外权限',
      details.join('\n'),
      params.threadId,
      params.turnId,
      params.itemId
    );
    const granted: PermissionsProfilePayload = new PermissionsProfilePayload();
    granted.network = PermissionNetworkPayload.cloneFrom(params.permissions.network);
    granted.fileSystem = PermissionFileSystemPayload.cloneFrom(params.permissions.fileSystem);
    approval.grantedPermissions = granted;
    return approval;
  }

  private parseUnifiedDiff(diff: string): ParsedDiff {
    const parsed: ParsedDiff = new ParsedDiff();
    const rawLines: string[] = diff.split('\n');
    const changedFiles: string[] = [];
    let addCount: number = 0;
    let deleteCount: number = 0;
    let oldLineNumber: number = 0;
    let newLineNumber: number = 0;
    let lineSequence: number = 1;

    rawLines.forEach((line: string) => {
      if (line.startsWith('diff --git ')) {
        const match: RegExpMatchArray | null = line.match(/ b\/(.+)$/);
        if (match !== null && match.length > 1 && changedFiles.indexOf(match[1]) < 0) {
          changedFiles.push(match[1]);
        }
        return;
      }

      if (line.startsWith('+++ b/')) {
        const filePath: string = line.substring(6);
        if (changedFiles.indexOf(filePath) < 0) {
          changedFiles.push(filePath);
        }
        return;
      }

      if (line.startsWith('@@')) {
        const match: RegExpMatchArray | null = line.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
        if (match !== null && match.length > 2) {
          oldLineNumber = Number(match[1]);
          newLineNumber = Number(match[2]);
        }
        return;
      }

      if (line.startsWith('+++') || line.startsWith('---') || line.startsWith('index ')) {
        return;
      }

      if (line.startsWith('+')) {
        parsed.lines.push(new CodexDiffLine(`diff-${lineSequence}`, lineSequence, newLineNumber.toString(), '+', line.substring(1), 'add'));
        lineSequence += 1;
        newLineNumber += 1;
        addCount += 1;
        return;
      }

      if (line.startsWith('-')) {
        parsed.lines.push(new CodexDiffLine(`diff-${lineSequence}`, lineSequence, oldLineNumber.toString(), '-', line.substring(1), 'delete'));
        lineSequence += 1;
        oldLineNumber += 1;
        deleteCount += 1;
        return;
      }

      if (line.startsWith(' ')) {
        parsed.lines.push(new CodexDiffLine(`diff-${lineSequence}`, lineSequence, newLineNumber.toString(), ' ', line.substring(1), 'context'));
        lineSequence += 1;
        oldLineNumber += 1;
        newLineNumber += 1;
      }
    });

    parsed.lines = parsed.lines.slice(0, 160);
    parsed.diffStat = `+${addCount} -${deleteCount}`;
    parsed.changedFiles = changedFiles.length > 0 ? changedFiles.join(', ') : '尚未识别变更文件';
    return parsed;
  }

  private async sendRpcRequest(request: RpcRequestEnvelope): Promise<Object> {
    if (this.socket === null) {
      throw new Error('WebSocket 尚未建立');
    }

    return await new Promise<Object>(async (resolve, reject) => {
      this.pendingRequests.set(request.id.toString(), new PendingRpcRequest(resolve, reject));
      const socket: webSocket.WebSocket = this.socket!;
      try {
        await socket.send(JSON.stringify(request));
      } catch (err) {
        this.pendingRequests.delete(request.id.toString());
        reject(this.describeError(err));
      }
    });
  }

  private async sendNotification(notification: RpcNotificationEnvelope): Promise<void> {
    if (this.socket === null) {
      throw new Error('WebSocket 尚未建立');
    }
    const socket: webSocket.WebSocket = this.socket;
    await socket.send(JSON.stringify(notification));
  }

  private async sendServerRequestResult(response: RpcResultEnvelope): Promise<void> {
    if (this.socket === null) {
      return;
    }
    const socket: webSocket.WebSocket = this.socket;
    await socket.send(JSON.stringify(response));
  }

  private async sendServerRequestError(response: RpcErrorEnvelope): Promise<void> {
    if (this.socket === null) {
      return;
    }
    const socket: webSocket.WebSocket = this.socket;
    await socket.send(JSON.stringify(response));
  }

  private rejectAllPendingRequests(message: string): void {
    this.pendingRequests.forEach((pendingRequest: PendingRpcRequest, key: string) => {
      pendingRequest.reject(message);
      this.pendingRequests.delete(key);
    });
  }

  private updateConnectionState(connectionState: CodexConnectionState, connectionText: string): void {
    this.connectionState = connectionState;
    this.connectionText = connectionText;
    if (connectionState !== 'connected') {
      this.pendingApproval = null;
    }
    this.notifyListeners();
  }

  private notifyListeners(): void {
    const snapshot: CodexBackendSnapshot = this.snapshot();
    this.listeners.forEach((listener: BackendListener) => {
      listener(snapshot);
    });
  }

  private threadFromRemoteId(remoteThreadId: string): CodexThreadRecord | null {
    const localKey: string | undefined = this.threadKeysByRemoteId.get(remoteThreadId);
    if (localKey === undefined) {
      return null;
    }
    return this.threads.get(localKey) ?? null;
  }

  private cloneApproval(approval: CodexApprovalRequest | null): CodexApprovalRequest | null {
    if (approval === null) {
      return null;
    }

    const cloned: CodexApprovalRequest = new CodexApprovalRequest(
      approval.requestId,
      approval.kind,
      approval.title,
      approval.detail,
      approval.threadId,
      approval.turnId,
      approval.itemId
    );
    const granted: PermissionsProfilePayload = new PermissionsProfilePayload();
    granted.network = PermissionNetworkPayload.cloneFrom(approval.grantedPermissions?.network);
    granted.fileSystem = PermissionFileSystemPayload.cloneFrom(approval.grantedPermissions?.fileSystem);
    cloned.grantedPermissions = granted;
    return cloned;
  }

  private cloneMessage(message: CodexChatMessage): CodexChatMessage {
    return new CodexChatMessage(
      message.messageId,
      message.sequence,
      message.author,
      message.role,
      message.content,
      message.timestamp
    );
  }

  private cloneDiffLine(line: CodexDiffLine): CodexDiffLine {
    return new CodexDiffLine(
      line.lineId,
      line.sequence,
      line.lineNumber,
      line.sign,
      line.content,
      line.kind
    );
  }

  private cloneMcpServer(server: McpServerRecord): McpServerRecord {
    return new McpServerRecord(
      server.id,
      server.name,
      server.enabled,
      server.transportType,
      server.command,
      server.argsText,
      server.url,
      server.envText,
      server.toolCount,
      server.resourceCount,
      server.healthStatus,
      server.authStatus,
      server.lastError,
      server.syncStatus,
      server.updatedAt
    );
  }

  private async readMcpConfig(): Promise<void> {
    const payload: Object = await this.sendRpcRequest(
      new RpcRequestEnvelope(this.nextRequestId(), 'config/read', new McpConfigReadParams())
    );
    const rawResponse: Record<string, Object> = payload as Record<string, Object>;
    const configObject: Record<string, Object> | undefined = rawResponse['config'] as Record<string, Object> | undefined;
    this.mcpConfigByName.clear();
    if (configObject === undefined) {
      return;
    }
    const mcpServers: Record<string, Object> | undefined = configObject['mcp_servers'] as Record<string, Object> | undefined;
    if (mcpServers === undefined) {
      return;
    }
    const names: string[] = Object.keys(mcpServers);
    for (let index: number = 0; index < names.length; index += 1) {
      const name: string = names[index];
      const value: Object | undefined = mcpServers[name] as Object | undefined;
      if (value !== undefined) {
        this.mcpConfigByName.set(name, value);
      }
    }
  }

  private buildMcpServerRecord(status: McpServerStatusPayload): McpServerRecord {
    const config: Record<string, Object> = (this.mcpConfigByName.get(status.name) as Record<string, Object> | undefined) ?? {};
    const command: string = this.readStringField(config, 'command');
    const url: string = this.readStringField(config, 'url');
    const argsText: string = this.stringifyJsonField(config['args']);
    const envText: string = this.stringifyJsonField(config['env']);
    const enabled: boolean = this.readBooleanField(config, 'enabled', true);
    const transportType: string = url.trim().length > 0 ? 'http' : (command.trim().length > 0 ? 'stdio' : 'unknown');
    const tools: Record<string, Object> = status.tools as Record<string, Object>;
    const toolCount: number = Object.keys(tools).length;
    const resourceCount: number = status.resources.length + status.resourceTemplates.length;
    const startupState: string = this.mcpStartupStateByName.get(status.name) ?? 'ready';
    const startupError: string = this.mcpStartupErrorByName.get(status.name) ?? '';
    return new McpServerRecord(
      status.name,
      status.name,
      enabled,
      transportType,
      command,
      argsText,
      url,
      envText,
      toolCount,
      resourceCount,
      this.normalizeMcpHealthStatus(startupState, startupError),
      this.normalizeMcpAuthStatus(status.authStatus),
      startupError,
      startupError.length > 0 ? 'error' : 'synced',
      this.currentTimestamp()
    );
  }

  private normalizeMcpAuthStatus(rawStatus: string): McpAuthStatus {
    if (rawStatus === 'oAuth' || rawStatus === 'bearerToken') {
      return 'authenticated';
    }
    if (rawStatus === 'notLoggedIn') {
      return 'required';
    }
    return 'notRequired';
  }

  private normalizeMcpHealthStatus(rawStatus: string, error: string | null): McpHealthStatus {
    if (error !== null && error.trim().length > 0) {
      return 'error';
    }
    if (rawStatus === 'ready') {
      return 'ok';
    }
    if (rawStatus === 'starting') {
      return 'degraded';
    }
    if (rawStatus === 'failed' || rawStatus === 'cancelled') {
      return 'error';
    }
    return 'unknown';
  }

  private readStringField(source: Record<string, Object>, fieldName: string): string {
    const value: Object | undefined = source[fieldName];
    return typeof value === 'string' ? value : '';
  }

  private readBooleanField(source: Record<string, Object>, fieldName: string, defaultValue: boolean): boolean {
    const value: Object | undefined = source[fieldName];
    return typeof value === 'boolean' ? value : defaultValue;
  }

  private stringifyJsonField(value: Object | undefined): string {
    if (value === undefined) {
      return '';
    }
    try {
      return JSON.stringify(value);
    } catch (_err) {
      return '';
    }
  }

  private parseJsonText(rawText: string, fallbackValue: Object): Object {
    const trimmed: string = rawText.trim();
    if (trimmed.length === 0) {
      return fallbackValue;
    }
    try {
      return JSON.parse(trimmed) as Object;
    } catch (_err) {
      return fallbackValue;
    }
  }

  private copyConfigObject(source: Record<string, Object>): Record<string, Object> {
    const target: Record<string, Object> = {};
    const keys: string[] = Object.keys(source);
    for (let index: number = 0; index < keys.length; index += 1) {
      const key: string = keys[index];
      target[key] = source[key];
    }
    return target;
  }

  private currentTimestamp(): string {
    const now: Date = new Date();
    const hours: string = now.getHours().toString().padStart(2, '0');
    const minutes: string = now.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  private parseEnvelope(text: string): RpcEnvelope | null {
    try {
      return JSON.parse(text) as RpcEnvelope;
    } catch (_err) {
      return null;
    }
  }

  private mapTurnStatus(status: string): CodexTurnStatus {
    if (status === 'completed') {
      return 'completed';
    }
    if (status === 'failed') {
      return 'failed';
    }
    if (status === 'interrupted') {
      return 'interrupted';
    }
    return 'inProgress';
  }

  private planStatusLabel(status: string): string {
    if (status === 'completed') {
      return '[完成]';
    }
    if (status === 'inProgress') {
      return '[进行中]';
    }
    return '[待处理]';
  }

  private nextRequestId(): string {
    const requestId: string = `req-${this.requestSequence}`;
    this.requestSequence += 1;
    return requestId;
  }

  private truncate(value: string, maxLength: number): string {
    if (value.length <= maxLength) {
      return value;
    }
    return `${value.substring(0, maxLength)}...`;
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }
}

export const codexBackend: CodexBackend = new CodexBackend();
