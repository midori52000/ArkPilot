import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  accountLoginNative,
  accountReadNative,
  approvalApproveNative,
  approvalDeclineNative,
  approvalPollNative,
  initializeNative,
  mcpConfigBatchWriteNative,
  mcpConfigReadNative,
  mcpOauthStartNative,
  mcpReloadNative,
  mcpStatusListNative,
  threadStartNative,
  turnPollNative,
  turnStartNative
} from './CodexNative';
import {
  McpAuthStatus,
  McpHealthStatus,
  McpServerRecord,
  SessionSummary,
  UsageSummary,
  WorkspaceAccessKind,
  WorkspaceDescriptor,
  WorkspacePermissionState
} from './ConsoleModels';

export type CodexMessageRole = 'user' | 'assistant' | 'system';
export type CodexTurnStatus = 'completed' | 'failed' | 'inProgress' | 'interrupted';
export type CodexDiffKind = 'add' | 'delete' | 'context';
export type CodexConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';
export type CodexApprovalKind = 'command' | 'fileChange' | 'permissions';
export type CodexAuthMode = 'none' | 'apiKey' | 'chatgpt' | 'chatgptAuthTokens' | 'unknown';
export type CodexTurnUpdateHandler = (result: CodexTurnResult) => void;
type BackendListener = (snapshot: CodexBackendSnapshot) => void;

const DEFAULT_SERVER_URL: string = 'native://entry';
const BACKEND_LOG_DOMAIN: number = 0x0ff1;
const BACKEND_LOG_TAG: string = 'CodexBackend';
const TURN_POLL_INTERVAL_MS: number = 800;
const APPROVAL_POLL_INTERVAL_MS: number = 1000;

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

class ThreadStartResultPayload {
  thread: ThreadPayload = new ThreadPayload();
  error?: TurnErrorPayload;
}

class TurnStartResultPayload {
  turn: TurnPayload = new TurnPayload();
}

class AccountPayload {
  type?: string;
  email?: string;
  planType?: string;
}

class GetAccountResponsePayload {
  account?: AccountPayload;
  requiresOpenaiAuth: boolean = true;
}

class McpServerStatusPayload {
  name: string = '';
  tools: Record<string, Object> = {};
  resources: Object[] = [];
  resourceTemplates: Object[] = [];
  authStatus: string = 'unsupported';
}

class McpStatusListResponsePayload {
  data: McpServerStatusPayload[] = [];
  nextCursor: string | null = null;
}

class InitializeClientInfoPayload {
  name: string = 'codex_harmony_agent';
  title: string = 'ArkPilot Harmony Agent';
  version: string = '0.1.0';
}

class InitializeCapabilitiesPayload {
  experimentalApi: boolean = true;
}

class InitializeRequestPayload {
  clientInfo: InitializeClientInfoPayload = new InitializeClientInfoPayload();
  capabilities: InitializeCapabilitiesPayload = new InitializeCapabilitiesPayload();
}

class AccountLoginRequestPayload {
  type: string = 'apiKey';
  apiKey: string = '';
}

class ApprovalActionRequestPayload {
  requestId: string | number = '';
  threadId: string = '';
  turnId: string = '';
  itemId: string = '';
  kind: CodexApprovalKind = 'command';
}

class TurnInputItemPayload {
  type: string = 'text';
  text: string = '';
}

class TurnStartRequestPayload {
  threadId: string = '';
  input: TurnInputItemPayload[] = [];
  cwd?: string;
  model?: string;
  effort?: string;
}

class McpStatusListRequestPayload {
  limit: number = 100;
}

class McpConfigBatchEditPayload {
  keyPath: string = '';
  value: Object = new Object() as Object;
  mergeStrategy: string = 'replace';
}

class McpConfigBatchWriteRequestPayload {
  edits: McpConfigBatchEditPayload[] = [];
  reloadUserConfig: boolean = true;
}

class McpOauthStartRequestPayload {
  name: string = '';
}

class McpConfigReadRequestPayload {
  includeLayers: boolean = false;
}

class ThreadStartRequestPayload {
  cwd?: string;
  model?: string;
}

class TurnPollResponsePayload {
}

class McpConfigReadResponsePayload {
  config: Record<string, Object> = {};
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

  constructor(messageId: string, sequence: number, author: string, role: CodexMessageRole, content: string, timestamp: string) {
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

  constructor(lineId: string, sequence: number, lineNumber: string, sign: string, content: string, kind: CodexDiffKind) {
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
  workspaceId: string;
  workspaceRoot: string;
  workspacePermissionState: WorkspacePermissionState;
  workspaceAccessKind: WorkspaceAccessKind;
  writableRoots: string[];
  model: string;
  reasoningEffort: string;
  prompt: string;

  constructor(
    threadKey: string,
    title: string,
    workspaceId: string,
    workspaceRoot: string,
    workspacePermissionState: WorkspacePermissionState,
    workspaceAccessKind: WorkspaceAccessKind,
    writableRoots: string[],
    model: string,
    reasoningEffort: string,
    prompt: string
  ) {
    this.threadKey = threadKey;
    this.title = title;
    this.workspaceId = workspaceId;
    this.workspaceRoot = workspaceRoot;
    this.workspacePermissionState = workspacePermissionState;
    this.workspaceAccessKind = workspaceAccessKind;
    this.writableRoots = writableRoots;
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

  constructor(threadId: string, turnId: string, status: CodexTurnStatus, messages: CodexChatMessage[], diffLines: CodexDiffLine[], summaryTitle: string, summaryPoints: string[], changedFiles: string, diffStat: string) {
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
  grantedPermissions?: Object;

  constructor(requestId: string | number, kind: CodexApprovalKind, title: string, detail: string, threadId: string, turnId: string, itemId: string) {
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

  constructor(serverUrl: string, connectionState: CodexConnectionState, connectionText: string, pendingApproval: CodexApprovalRequest | null, authMode: CodexAuthMode, requiresOpenAIAuth: boolean, authStatusText: string, planTypeText: string, mcpStatusText: string, mcpServerCount: number, mcpErrorText: string) {
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
  workspaceId: string = '';
  workspaceName: string = '';
  cwd: string = '';
  workspacePermissionState: WorkspacePermissionState = 'unavailable';
  workspaceAccessKind: WorkspaceAccessKind = 'unknown';
  writableRoots: string[] = [];
  messages: CodexChatMessage[] = [];
  diffLines: CodexDiffLine[] = [];
  summaryTitle: string = '等待 ArkPilot 响应';
  summaryPoints: string[] = ['发送请求后会在这里显示计划、摘要和关键步骤。'];
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
    this.updatedAt = currentTimestamp();
  }
}

function currentTimestamp(): string {
  const now: Date = new Date();
  const hours: string = now.getHours().toString().padStart(2, '0');
  const minutes: string = now.getMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}

function safeJsonParse(rawText: string): Object | null {
  try {
    return JSON.parse(rawText) as Object;
  } catch (_err) {
    return null;
  }
}

function parseJsonText(rawText: string, fallbackValue: Object): Object {
  const parsed: Object | null = safeJsonParse(rawText);
  return parsed ?? fallbackValue;
}

export class CodexBackend {
  private initialized: boolean = false;
  private connectionState: CodexConnectionState = 'disconnected';
  private connectionText: string = '未连接';
  private readonly listeners: Map<number, BackendListener> = new Map();
  private readonly threads: Map<string, CodexThreadRecord> = new Map();
  private readonly threadKeysByRemoteId: Map<string, string> = new Map();
  private readonly workspaceCatalog: Map<string, WorkspaceDescriptor> = new Map();
  private serverUrl: string = DEFAULT_SERVER_URL;
  private listenerSequence: number = 1;
  private pendingApproval: CodexApprovalRequest | null = null;
  private authMode: CodexAuthMode = 'none';
  private requiresOpenAIAuth: boolean = true;
  private authStatusText: string = '未登录';
  private planTypeText: string = '';
  private mcpServersCache: McpServerRecord[] = [];
  private readonly mcpConfigByName: Map<string, Object> = new Map();
  private mcpStatusText: string = '尚未加载 MCP 状态';
  private mcpErrorText: string = '';
  private approvalTimerId: number = -1;

  private logInfo(message: string): void {
    hilog.info(BACKEND_LOG_DOMAIN, BACKEND_LOG_TAG, '%{public}s', message);
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
      const lastMessageTimestamp: string = thread.messages.length > 0 ? thread.messages[thread.messages.length - 1].timestamp : thread.updatedAt;
      const workspace: WorkspaceDescriptor = this.workspaceDescriptorForThread(thread);
      sessions.push(new SessionSummary(
        thread.localKey,
        thread.title,
        workspace.id,
        workspace.name,
        workspace.rootPath,
        workspace.permissionState,
        workspace.accessKind,
        thread.messages.length,
        lastMessageTimestamp,
        thread.summaryTitle,
        thread.lastTurnStatus,
        thread.changedFiles
      ));
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
    return new UsageSummary(this.threads.size, activeTurnCount, turnCount, messageCount, diffLineCount, diffUpdateCount, lastTurnStatus);
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

  configureServerUrl(serverUrl: string): void {
    const nextServerUrl: string = serverUrl.trim();
    this.serverUrl = nextServerUrl.length > 0 ? nextServerUrl : DEFAULT_SERVER_URL;
    this.notifyListeners();
  }

  async connect(): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.updateConnectionState('connecting', '正在初始化原生桥接');
    const initRequest: InitializeRequestPayload = new InitializeRequestPayload();
    const initResult: Object = parseJsonText(initializeNative(JSON.stringify(initRequest)), new Object() as Object);
    this.initialized = true;
    await this.refreshAccountState();
    const platformOs: string = typeof (initResult as Record<string, Object>)['platformOs'] === 'string'
      ? ((initResult as Record<string, Object>)['platformOs'] as string)
      : 'ohos';
    this.updateConnectionState('connected', `已连接 · ${platformOs}`);
    this.ensureApprovalPolling();
  }

  async disconnect(): Promise<void> {
    this.initialized = false;
    this.stopApprovalPolling();
    this.pendingApproval = null;
    this.updateConnectionState('disconnected', '已断开连接');
  }

  async loginWithApiKey(apiKey: string): Promise<void> {
    const trimmedApiKey: string = apiKey.trim();
    if (trimmedApiKey.length === 0) {
      throw new Error('请输入有效的 OpenAI API Key。');
    }
    await this.ensureConnected();
    const loginRequest: AccountLoginRequestPayload = new AccountLoginRequestPayload();
    loginRequest.apiKey = trimmedApiKey;
    accountLoginNative(JSON.stringify(loginRequest));
    await this.refreshAccountState();
  }

  async approvePendingRequest(): Promise<void> {
    if (this.pendingApproval === null) {
      return;
    }
    const request: CodexApprovalRequest = this.pendingApproval;
    this.pendingApproval = null;
    const approveRequest: ApprovalActionRequestPayload = new ApprovalActionRequestPayload();
    approveRequest.requestId = request.requestId;
    approveRequest.threadId = request.threadId;
    approveRequest.turnId = request.turnId;
    approveRequest.itemId = request.itemId;
    approveRequest.kind = request.kind;
    approvalApproveNative(JSON.stringify(approveRequest));
    this.notifyListeners();
  }

  async declinePendingRequest(): Promise<void> {
    if (this.pendingApproval === null) {
      return;
    }
    const request: CodexApprovalRequest = this.pendingApproval;
    this.pendingApproval = null;
    const declineRequest: ApprovalActionRequestPayload = new ApprovalActionRequestPayload();
    declineRequest.requestId = request.requestId;
    declineRequest.threadId = request.threadId;
    declineRequest.turnId = request.turnId;
    declineRequest.itemId = request.itemId;
    declineRequest.kind = request.kind;
    approvalDeclineNative(JSON.stringify(declineRequest));
    this.notifyListeners();
  }

  async startTurn(request: CodexTurnRequest, onUpdate?: CodexTurnUpdateHandler): Promise<CodexTurnResult> {
    await this.ensureConnected();
    if (this.requiresOpenAIAuth && this.authMode === 'none') {
      throw new Error('当前后端尚未登录 OpenAI。请先填写 API Key 并登录。');
    }
    const thread: CodexThreadRecord = await this.ensureRemoteThread(request);
    const pendingTurn: PendingTurnState = new PendingTurnState(request.threadKey, onUpdate);
    thread.activeTurn = pendingTurn;
    const workspace: WorkspaceDescriptor = this.bindWorkspaceToThread(thread, request);

    const startedSnapshot: CodexTurnResult = this.beginLocalTurn(thread, request.prompt);
    this.emitTurnUpdate(thread, pendingTurn, startedSnapshot);

    const turnRequest: TurnStartRequestPayload = new TurnStartRequestPayload();
    turnRequest.threadId = thread.remoteThreadId;
    const inputItem: TurnInputItemPayload = new TurnInputItemPayload();
    inputItem.text = request.prompt;
    turnRequest.input = [inputItem];
    turnRequest.cwd = workspace.rootPath.trim().length > 0 ? workspace.rootPath.trim() : undefined;
    turnRequest.model = request.model !== 'default' ? request.model : undefined;
    turnRequest.effort = request.reasoningEffort !== 'default' ? request.reasoningEffort : undefined;
    const turnResult: Object = parseJsonText(turnStartNative(JSON.stringify(turnRequest)), new Object() as Object);

    const turnPayload: Record<string, Object> = ((turnResult as Record<string, Object>)['turn'] as Record<string, Object> | undefined) ?? {};
    pendingTurn.turnId = typeof turnPayload['id'] === 'string' ? (turnPayload['id'] as string) : '';
    const rawStatus: string = typeof turnPayload['status'] === 'string' ? (turnPayload['status'] as string) : 'unknown';
    const errorPayload: Record<string, Object> = (turnPayload['error'] as Record<string, Object> | undefined) ?? {};
    const errorMessage: string = typeof errorPayload['message'] === 'string' ? (errorPayload['message'] as string) : '';
    this.logInfo(`turnStart thread=${thread.remoteThreadId} turn=${pendingTurn.turnId} rawStatus=${rawStatus} error=${errorMessage}`);
    if (rawStatus === 'failed' || pendingTurn.turnId.trim().length === 0) {
      thread.activeTurn = null;
      thread.lastTurnStatus = 'failed';
      thread.updatedAt = currentTimestamp();
      thread.summaryTitle = '本轮失败';
      thread.summaryPoints = [errorMessage.trim().length > 0 ? errorMessage : 'turn/start 未返回有效的 turnId。'];
      const failedSnapshot: CodexTurnResult = this.snapshotForThread(thread, 'failed');
      this.emitTurnUpdate(thread, pendingTurn, failedSnapshot);
      pendingTurn.resolveCompletion(failedSnapshot);
      return failedSnapshot;
    }

    const result: CodexTurnResult = await this.pollTurnUntilCompleted(thread, pendingTurn);
    return result;
  }

  async refreshMcpServers(): Promise<McpServerRecord[]> {
    await this.ensureConnected();
    this.readMcpConfig();
    const statusListRequest: McpStatusListRequestPayload = new McpStatusListRequestPayload();
    const response: McpStatusListResponsePayload = parseJsonText(mcpStatusListNative(JSON.stringify(statusListRequest)), new McpStatusListResponsePayload()) as McpStatusListResponsePayload;
    this.mcpServersCache = response.data.map((item: McpServerStatusPayload) => this.buildMcpServerRecord(item));
    this.mcpStatusText = this.mcpServersCache.length > 0 ? `已加载 ${this.mcpServersCache.length} 个 MCP server` : '当前没有已配置的 MCP server';
    this.mcpErrorText = '';
    this.notifyListeners();
    return this.mcpServers();
  }

  async reloadMcpServers(): Promise<void> {
    await this.ensureConnected();
    mcpReloadNative();
    this.mcpStatusText = 'MCP 配置已重载';
    this.mcpErrorText = '';
    await this.refreshMcpServers();
  }

  async batchWriteMcpConfig(edits: McpConfigBatchEditPayload[]): Promise<void> {
    await this.ensureConnected();
    const batchWriteRequest: McpConfigBatchWriteRequestPayload = new McpConfigBatchWriteRequestPayload();
    batchWriteRequest.edits = edits;
    mcpConfigBatchWriteNative(JSON.stringify(batchWriteRequest));
    this.mcpStatusText = 'MCP 配置已保存';
    this.mcpErrorText = '';
    this.notifyListeners();
  }

  async saveMcpServerConfig(serverName: string, enabled: boolean, transportType: string, command: string, argsText: string, url: string, envText: string): Promise<void> {
    await this.ensureConnected();
    this.readMcpConfig();
    const existingConfig: Record<string, Object> = this.copyConfigObject((this.mcpConfigByName.get(serverName) as Record<string, Object> | undefined) ?? {});
    const nextConfig: Record<string, Object> = this.copyConfigObject(existingConfig);
    nextConfig['enabled'] = enabled;
    nextConfig['args'] = parseJsonText(argsText, new Array<Object>() as Object);
    nextConfig['env'] = parseJsonText(envText, new Object() as Object);
    if (transportType === 'http') {
      nextConfig['url'] = url.trim();
      nextConfig['command'] = '';
    } else {
      nextConfig['command'] = command.trim();
      nextConfig['url'] = '';
    }
    const edit: McpConfigBatchEditPayload = new McpConfigBatchEditPayload();
    edit.keyPath = `mcp_servers.${serverName}`;
    edit.value = nextConfig;
    edit.mergeStrategy = 'replace';
    await this.batchWriteMcpConfig([edit]);
    await this.reloadMcpServers();
  }

  async startMcpOAuthLogin(serverName: string): Promise<void> {
    await this.ensureConnected();
    const oauthRequest: McpOauthStartRequestPayload = new McpOauthStartRequestPayload();
    oauthRequest.name = serverName;
    mcpOauthStartNative(JSON.stringify(oauthRequest));
    this.mcpStatusText = `已为 ${serverName} 发起 OAuth 登录`;
    this.mcpErrorText = '';
    this.notifyListeners();
  }

  private async ensureConnected(): Promise<void> {
    if (!this.initialized) {
      await this.connect();
    }
  }

  private async refreshAccountState(): Promise<void> {
    const payload: GetAccountResponsePayload = parseJsonText(accountReadNative(), new GetAccountResponsePayload()) as GetAccountResponsePayload;
    this.applyAccountState(payload);
  }

  private ensureApprovalPolling(): void {
    if (this.approvalTimerId >= 0) {
      return;
    }
    this.approvalTimerId = setInterval(() => {
      this.pollPendingApproval();
    }, APPROVAL_POLL_INTERVAL_MS);
  }

  private stopApprovalPolling(): void {
    if (this.approvalTimerId >= 0) {
      clearInterval(this.approvalTimerId);
      this.approvalTimerId = -1;
    }
  }

  private pollPendingApproval(): void {
    if (!this.initialized) {
      return;
    }
    const parsed: Object | null = safeJsonParse(approvalPollNative());
    if (parsed === null) {
      return;
    }
    if (parsed === null || parsed === undefined) {
      return;
    }
    const approval = this.buildApprovalFromNative(parsed as Record<string, Object>);
    this.pendingApproval = approval;
    this.notifyListeners();
  }

  private async ensureRemoteThread(request: CodexTurnRequest): Promise<CodexThreadRecord> {
    const existing: CodexThreadRecord | undefined = this.threads.get(request.threadKey);
    if (existing !== undefined && existing.remoteThreadId.length > 0) {
      existing.title = request.title;
      this.bindWorkspaceToThread(existing, request);
      return existing;
    }
    const thread: CodexThreadRecord = existing ?? new CodexThreadRecord(request.threadKey, request.title);
    const workspace: WorkspaceDescriptor = this.bindWorkspaceToThread(thread, request);
    const threadStartRequest: ThreadStartRequestPayload = new ThreadStartRequestPayload();
    threadStartRequest.cwd = workspace.rootPath.trim().length > 0 ? workspace.rootPath.trim() : undefined;
    threadStartRequest.model = request.model !== 'default' ? request.model : undefined;
    const payload: ThreadStartResultPayload = parseJsonText(threadStartNative(JSON.stringify(threadStartRequest)), new ThreadStartResultPayload()) as ThreadStartResultPayload;
    if (payload.thread === undefined || payload.thread.id.length === 0) {
      const message: string = payload.error?.message?.trim() ?? '';
      if (message.length > 0) {
        throw new Error(`threadStart failed: ${message}`);
      }
    }
    if (payload.thread === undefined || payload.thread.id.length === 0) {
      payload.thread = new ThreadPayload();
      payload.thread.id = `native-thread-${request.threadKey}`;
    }
    thread.remoteThreadId = payload.thread.id;
    this.threads.set(request.threadKey, thread);
    this.threadKeysByRemoteId.set(payload.thread.id, request.threadKey);
    return thread;
  }

  private bindWorkspaceToThread(thread: CodexThreadRecord, request: CodexTurnRequest): WorkspaceDescriptor {
    const workspace: WorkspaceDescriptor = this.upsertWorkspaceDescriptor(request);
    thread.workspaceId = workspace.id;
    thread.workspaceName = workspace.name;
    thread.cwd = workspace.rootPath;
    thread.workspacePermissionState = workspace.permissionState;
    thread.workspaceAccessKind = workspace.accessKind;
    thread.writableRoots = [...workspace.writableRoots];
    return workspace;
  }

  private upsertWorkspaceDescriptor(request: CodexTurnRequest): WorkspaceDescriptor {
    const trimmedRoot: string = request.workspaceRoot.trim();
    const workspaceId: string = request.workspaceId.trim().length > 0 ? request.workspaceId.trim() : `session:${request.threadKey}`;
    const existing: WorkspaceDescriptor | undefined = this.workspaceCatalog.get(workspaceId);
    const nextRoot: string = trimmedRoot.length > 0 ? trimmedRoot : (existing?.rootPath ?? '');
    const nextWritableRoots: string[] = request.writableRoots.length > 0
      ? [...request.writableRoots]
      : (nextRoot.length > 0 ? [nextRoot] : (existing?.writableRoots ?? []));
    const nextName: string = request.title.trim().length > 0 ? request.title.trim() : (existing?.name ?? workspaceId);
    const workspace: WorkspaceDescriptor = new WorkspaceDescriptor(
      workspaceId,
      nextName,
      nextRoot,
      request.workspaceAccessKind,
      request.workspacePermissionState,
      existing?.sourceUri ?? '',
      nextWritableRoots,
      existing?.grantedAt ?? Date.now(),
      Date.now()
    );
    this.workspaceCatalog.set(workspaceId, workspace);
    return workspace;
  }

  private workspaceDescriptorForThread(thread: CodexThreadRecord): WorkspaceDescriptor {
    const existing: WorkspaceDescriptor | undefined = thread.workspaceId.length > 0 ? this.workspaceCatalog.get(thread.workspaceId) : undefined;
    if (existing !== undefined) {
      return existing;
    }
    const inferredRoot: string = thread.cwd.trim();
    return new WorkspaceDescriptor(
      thread.workspaceId.length > 0 ? thread.workspaceId : `session:${thread.localKey}`,
      thread.workspaceName.length > 0 ? thread.workspaceName : thread.title,
      inferredRoot,
      thread.workspaceAccessKind,
      thread.workspacePermissionState,
      '',
      thread.writableRoots.length > 0 ? [...thread.writableRoots] : (inferredRoot.length > 0 ? [inferredRoot] : []),
      Date.now(),
      Date.now()
    );
  }

  private beginLocalTurn(thread: CodexThreadRecord, prompt: string): CodexTurnResult {
    this.upsertMessage(thread, `user-${Date.now()}`, '你', 'user', prompt, currentTimestamp());
    thread.turnCount += 1;
    thread.lastTurnStatus = 'inProgress';
    thread.updatedAt = currentTimestamp();
    thread.summaryTitle = '正在等待 ArkPilot 响应';
    thread.summaryPoints = ['已通过原生桥接发送请求，等待轮询结果。'];
    return this.snapshotForThread(thread, 'inProgress');
  }

  private async pollTurnUntilCompleted(thread: CodexThreadRecord, pendingTurn: PendingTurnState): Promise<CodexTurnResult> {
    while (true) {
      const pollObject: Record<string, Object> = parseJsonText(turnPollNative(thread.remoteThreadId, pendingTurn.turnId), new TurnPollResponsePayload() as Object) as Record<string, Object>;
      this.logInfo(`turnPoll thread=${thread.remoteThreadId} turn=${pendingTurn.turnId} payload=${JSON.stringify(pollObject)}`);
      const nextSnapshot: CodexTurnResult = this.applyTurnPollResult(thread, pendingTurn.turnId, pollObject);
      this.emitTurnUpdate(thread, pendingTurn, nextSnapshot);
      if (nextSnapshot.status !== 'inProgress') {
        thread.activeTurn = null;
        pendingTurn.resolveCompletion(nextSnapshot);
        return nextSnapshot;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, TURN_POLL_INTERVAL_MS));
    }
  }

  private applyTurnPollResult(thread: CodexThreadRecord, turnId: string, payload: Record<string, Object>): CodexTurnResult {
    const statusRaw: string = typeof payload['status'] === 'string' ? (payload['status'] as string) : 'completed';
    const status: CodexTurnStatus = this.mapTurnStatus(statusRaw);
    const messages: Object[] = Array.isArray(payload['messages']) ? (payload['messages'] as Object[]) : [];
    if (messages.length > 0) {
      const nextMessages: CodexChatMessage[] = messages.map((item: Object, index: number) => {
        const message = item as Record<string, Object>;
        const roleRaw: string = typeof message['role'] === 'string' ? (message['role'] as string) : 'assistant';
        const role: CodexMessageRole = roleRaw === 'user' || roleRaw === 'system' ? roleRaw : 'assistant';
        return new CodexChatMessage(
          typeof message['messageId'] === 'string' ? (message['messageId'] as string) : `msg-${index + 1}`,
          index + 1,
          typeof message['author'] === 'string' ? (message['author'] as string) : (role === 'assistant' ? 'ArkPilot' : '系统'),
          role,
          typeof message['content'] === 'string' ? (message['content'] as string) : '',
          typeof message['timestamp'] === 'string' ? (message['timestamp'] as string) : currentTimestamp()
        );
      });
      thread.messages = this.mergeThreadMessages(thread.messages, nextMessages);
    }
    const diffText: string = typeof payload['diff'] === 'string' ? (payload['diff'] as string) : '';
    if (diffText.trim().length > 0) {
      const parsed: ParsedDiff = this.parseUnifiedDiff(diffText);
      thread.diffLines = parsed.lines;
      thread.diffStat = parsed.diffStat;
      thread.changedFiles = parsed.changedFiles;
    }
    const summaryRaw: Object[] = Array.isArray(payload['summary']) ? (payload['summary'] as Object[]) : [];
    const summaryPoints: string[] = summaryRaw.map((item: Object) => typeof item === 'string' ? (item as string) : JSON.stringify(item));
    thread.summaryTitle = typeof payload['summaryTitle'] === 'string' ? (payload['summaryTitle'] as string) : (status === 'completed' ? '本轮已完成' : '执行中');
    thread.summaryPoints = summaryPoints.length > 0 ? summaryPoints : [status === 'completed' ? '本轮执行已结束。' : '等待更多轮询结果。'];
    thread.lastTurnStatus = status;
    thread.updatedAt = currentTimestamp();
    return this.snapshotForThread(thread, status, turnId);
  }

  private mergeThreadMessages(existing: CodexChatMessage[], incoming: CodexChatMessage[]): CodexChatMessage[] {
    if (existing.length === 0) {
      return incoming.map((message: CodexChatMessage) => this.cloneMessage(message));
    }
    const merged: CodexChatMessage[] = existing.map((message: CodexChatMessage) => this.cloneMessage(message));
    for (const message of incoming) {
      const index: number = merged.findIndex((item: CodexChatMessage) => item.messageId === message.messageId);
      if (index >= 0) {
        merged[index] = this.cloneMessage(message);
      } else {
        merged.push(this.cloneMessage(message));
      }
    }
    for (let index: number = 0; index < merged.length; index += 1) {
      const current: CodexChatMessage = merged[index];
      merged[index] = new CodexChatMessage(
        current.messageId,
        index + 1,
        current.author,
        current.role,
        current.content,
        current.timestamp
      );
    }
    return merged;
  }

  private buildApprovalFromNative(payload: Record<string, Object>): CodexApprovalRequest | null {
    const kindRaw: string = typeof payload['kind'] === 'string' ? (payload['kind'] as string) : '';
    if (kindRaw.length === 0) {
      return null;
    }
    const kind: CodexApprovalKind = kindRaw === 'fileChange' || kindRaw === 'permissions' ? kindRaw : 'command';
    const approval = new CodexApprovalRequest(
      typeof payload['requestId'] === 'string' || typeof payload['requestId'] === 'number' ? payload['requestId'] as string | number : `approval-${Date.now()}`,
      kind,
      typeof payload['title'] === 'string' ? (payload['title'] as string) : '需要审批',
      typeof payload['detail'] === 'string' ? (payload['detail'] as string) : '',
      typeof payload['threadId'] === 'string' ? (payload['threadId'] as string) : '',
      typeof payload['turnId'] === 'string' ? (payload['turnId'] as string) : '',
      typeof payload['itemId'] === 'string' ? (payload['itemId'] as string) : ''
    );
    approval.grantedPermissions = payload['grantedPermissions'];
    return approval;
  }

  private applyAccountState(payload: GetAccountResponsePayload): void {
    this.requiresOpenAIAuth = payload.requiresOpenaiAuth !== false;
    if (!this.requiresOpenAIAuth) {
      this.authMode = 'unknown';
      this.authStatusText = '当前模型提供方不要求 OpenAI 认证';
      this.planTypeText = '';
      this.notifyListeners();
      return;
    }
    const account: AccountPayload | undefined = payload.account;
    if (account === undefined) {
      this.authMode = 'none';
      this.authStatusText = '未登录';
      this.planTypeText = '';
      this.notifyListeners();
      return;
    }
    this.authMode = this.normalizeAuthMode(account.type);
    if (this.authMode === 'chatgpt' || this.authMode === 'chatgptAuthTokens') {
      this.authStatusText = account.email ?? '已登录 ChatGPT';
    } else if (this.authMode === 'apiKey') {
      this.authStatusText = '已使用 API Key 登录';
    } else {
      this.authStatusText = '已登录';
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

  private snapshotForThread(thread: CodexThreadRecord, status: CodexTurnStatus, turnId: string = ''): CodexTurnResult {
    return new CodexTurnResult(thread.remoteThreadId, turnId, status, thread.messages.map((message: CodexChatMessage) => this.cloneMessage(message)), thread.diffLines.map((line: CodexDiffLine) => this.cloneDiffLine(line)), thread.summaryTitle, [...thread.summaryPoints], thread.changedFiles, thread.diffStat);
  }

  private emitTurnUpdate(thread: CodexThreadRecord, pendingTurn: PendingTurnState | null, result: CodexTurnResult): void {
    if (pendingTurn !== null && pendingTurn.listener !== undefined) {
      pendingTurn.listener(result);
    }
    if (thread.activeTurn !== null && thread.activeTurn !== pendingTurn && thread.activeTurn.listener !== undefined) {
      thread.activeTurn.listener(result);
    }
  }

  private upsertMessage(thread: CodexThreadRecord, messageId: string, author: string, role: CodexMessageRole, content: string, timestamp: string): void {
    const index: number = this.findMessageIndex(thread, messageId);
    if (index >= 0) {
      const current: CodexChatMessage = thread.messages[index];
      thread.messages[index] = new CodexChatMessage(current.messageId, current.sequence, author, role, content, timestamp);
      return;
    }
    thread.messages.push(new CodexChatMessage(messageId, thread.messages.length + 1, author, role, content, timestamp));
  }

  private findMessageIndex(thread: CodexThreadRecord, messageId: string): number {
    for (let index: number = 0; index < thread.messages.length; index += 1) {
      if (thread.messages[index].messageId === messageId) {
        return index;
      }
    }
    return -1;
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

  private cloneApproval(approval: CodexApprovalRequest | null): CodexApprovalRequest | null {
    if (approval === null) {
      return null;
    }
    const cloned: CodexApprovalRequest = new CodexApprovalRequest(approval.requestId, approval.kind, approval.title, approval.detail, approval.threadId, approval.turnId, approval.itemId);
    cloned.grantedPermissions = approval.grantedPermissions;
    return cloned;
  }

  private cloneMessage(message: CodexChatMessage): CodexChatMessage {
    return new CodexChatMessage(message.messageId, message.sequence, message.author, message.role, message.content, message.timestamp);
  }

  private cloneDiffLine(line: CodexDiffLine): CodexDiffLine {
    return new CodexDiffLine(line.lineId, line.sequence, line.lineNumber, line.sign, line.content, line.kind);
  }

  private cloneMcpServer(server: McpServerRecord): McpServerRecord {
    return new McpServerRecord(server.id, server.name, server.enabled, server.transportType, server.command, server.argsText, server.url, server.envText, server.toolCount, server.resourceCount, server.healthStatus, server.authStatus, server.lastError, server.syncStatus, server.updatedAt);
  }

  private readMcpConfig(): void {
    const configReadRequest: McpConfigReadRequestPayload = new McpConfigReadRequestPayload();
    const rawResponse: Record<string, Object> = parseJsonText(mcpConfigReadNative(JSON.stringify(configReadRequest)), new McpConfigReadResponsePayload() as Object) as Record<string, Object>;
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
    return new McpServerRecord(status.name, status.name, enabled, transportType, command, argsText, url, envText, toolCount, resourceCount, this.normalizeMcpHealthStatus('ready', null), this.normalizeMcpAuthStatus(status.authStatus), '', 'synced', currentTimestamp());
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

  private copyConfigObject(source: Record<string, Object>): Record<string, Object> {
    const target: Record<string, Object> = {};
    const keys: string[] = Object.keys(source);
    for (let index: number = 0; index < keys.length; index += 1) {
      const key: string = keys[index];
      target[key] = source[key];
    }
    return target;
  }
}

export const codexBackend: CodexBackend = new CodexBackend();
