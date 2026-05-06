import {
  codexBackend,
  CodexApprovalRequest,
  CodexBackendSnapshot,
  CodexConnectionState,
  CodexDiffLine,
  CodexTurnRequest,
  CodexTurnResult
} from '../backend/CodexBackend';
import {
  CodexProviderConfig,
  WorkspaceAccessStatus,
  checkWorkspaceAccess,
  getEmbeddedCodexHostStatus,
  getEmbeddedCodexProviderCatalog,
  getEmbeddedCodexProviderConfig,
  saveEmbeddedCodexProviderConfig
} from '../backend/CodexNative';
import { providerCatalogService } from '../backend/ProviderCatalogService';
import { SessionSummary, SidebarView, WorkspaceAccessKind, WorkspacePermissionState, TurnTokenUsage, TokenUsageAggregate, TokenUsageBreakdown, WorkspaceItem, WorkspaceBindingDraft, WorkspaceDirectorySelection, SelectorOption, SidebarItem } from '../backend/ConsoleModels';
import { StoredWorkspaceItem, workspaceBindingStore } from '../backend/WorkspaceBindingStore';
import router from '@ohos.router';
import pasteboard from '@ohos.pasteboard';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { picker } from '@kit.CoreFileKit';
import uri from '@ohos.uri';

const INDEX_DOMAIN = 0x0000;
const INDEX_TAG = 'IndexProviderDebug';
const WAITING_FOR_DIFF_TEXT: string = '\u7b49\u5f85 turn/diff/updated \u901a\u77e5\u3002';
const NO_DIFF_TEXT: string = '\u672c\u8f6e\u5c1a\u672a\u4ea7\u751f diff\u3002';
const NO_FILE_CHANGES_TEXT: string = '\u5c1a\u672a\u4ea7\u751f\u6587\u4ef6\u6539\u52a8';
const UNKNOWN_DIFF_FILE_TEXT: string = '\u672a\u8bc6\u522b\u6587\u4ef6';

class ChatMessage {
  id: string;
  author: string;
  role: string;
  content: string;
  timestamp: string;
  itemType?: string;
  status?: string;
  metadata?: Record<string, Object>;

  constructor(id: string, author: string, role: string, content: string, timestamp: string, itemType?: string, status?: string, metadata?: Record<string, Object>) {
    this.id = id;
    this.author = author;
    this.role = role;
    this.content = content;
    this.timestamp = timestamp;
    this.itemType = itemType;
    this.status = status;
    this.metadata = metadata;
  }
}

class CodeDiffLine {
  id: string;
  lineNumber: string;
  sign: string;
  content: string;
  kind: string;
  filePath: string;

  constructor(id: string, lineNumber: string, sign: string, content: string, kind: string, filePath?: string) {
    this.id = id;
    this.lineNumber = lineNumber;
    this.sign = sign;
    this.content = content;
    this.kind = kind;
    this.filePath = filePath ?? '';
  }
}

class CodeDiffFile {
  path: string;
  label: string;
  diffStat: string;
  lines: CodeDiffLine[];

  constructor(path: string, label: string, diffStat: string, lines: CodeDiffLine[]) {
    this.path = path;
    this.label = label;
    this.diffStat = diffStat;
    this.lines = lines;
  }
}

@Entry
@Component
struct Index {
  private readonly quickActions: string[] = [
    '检查当前工作目录的变更',
    '总结最近一次改动',
    '解释右侧 diff'
  ];
  private readonly effortOptions: SelectorOption[] = [
    new SelectorOption('默认', 'default'),
    new SelectorOption('minimal', 'minimal'),
    new SelectorOption('low', 'low'),
    new SelectorOption('medium', 'medium'),
    new SelectorOption('high', 'high'),
    new SelectorOption('xhigh', 'xhigh')
  ];
  private readonly sidebarItems: SidebarItem[] = [
    new SidebarItem('chat', 'Chat', '继续与内置 ArkPilot 协作'),
    new SidebarItem('sessions', 'Sessions', '查看、切换并删除历史会话')
  ];
  private backendSubscriptionId: number = -1;
  private reconnectTimerId: number = -1;
  private reconnectAttemptCount: number = 0;
  private readonly workspaceRoots: Map<number, string> = new Map();
  private readonly workspaceIds: Map<number, string> = new Map();
  private readonly workspaceUris: Map<number, string> = new Map();
  private readonly messageScroller: Scroller = new Scroller();

  @State private workspaces: WorkspaceItem[] = [];
  @State private activeSidebarView: SidebarView = 'chat';
  @State private activeWorkspaceId: number = 1;
  @State private activeWorkspaceBindingId: string = 'session:1';
  @State private currentWorkspaceTitle: string = '新会话 1';
  @State private currentWorkspaceDescription: string = '等待通过 app-server 创建真实会话';
  @State private activeWorkspacePermissionState: WorkspacePermissionState = 'unavailable';
  @State private activeWorkspaceAccessKind: WorkspaceAccessKind = 'unknown';
  @State private workspaceStatusText: string = 'å°šæœªæ£€æµ‹å·¥ä½œåŒºæƒé™';
  @State private selectedEffortIndex: number = 0;
  @State private showEffortOptions: boolean = false;
  @State private serverUrl: string = 'ws://127.0.0.1:7456';
  @State private workspaceRoot: string = '';
  @State private workspaceDraftText: string = '';
  @State private workspaceSelectionText: string = '使用默认工作区';
  @State private providerBaseUrl: string = '';
  @State private providerApiKey: string = '';
  @State private manualModel: string = '';
  @State private providerStatusText: string = 'Provider config not loaded yet.';
  @State private providerName: string = '未选择';
  @State private isSavingProvider: boolean = false;
  @State private apiKey: string = '';
  @State private isAuthenticating: boolean = false;
  @State private authStatusText: string = '未登录';
  @State private connectionState: CodexConnectionState = 'disconnected';
  @State private connectionText: string = '未连接';
  @State private summaryTitle: string = '等待连接原生桥接后端';
  @State private summaryPoints: string[] = [
    '应用启动时会自动拉起内置 Rust ArkPilot host。',
    '这里通过 libentry.so 同步调用原生桥接层，而不是本地 mock。',
    '发送消息后会刷新对话、计划和 diff。'
  ];
  @State private changedFiles: string = '尚未产生文件改动';
  @State private diffStat: string = '+0 -0';
  @State private diffFiles: CodeDiffFile[] = [];
  @State private selectedDiffFilePath: string = '';
  @State private isRunning: boolean = false;
  @State private showLeftDrawer: boolean = true;
  @State private showRightDrawer: boolean = true;
  @State private leftPanelWidth: number = 280;
  @State private rightPanelWidth: number = 360;
  private readonly leftDrawerMinWidth: number = 200;
  private readonly rightDrawerMinWidth: number = 240;
  private dragStartLeftW: number = 0;
  private dragStartRightW: number = 0;
  @State private recentWorkspaces: WorkspaceItem[] = [];
  @State private directoryFilter: string = '';
  @State private directoryFilterText: string = '使用默认工作区';
  @State private draft: string = '检查当前工作目录，并说明需要我批准的操作。';
  private savedDraft: string = '';
  @State private pendingApproval: CodexApprovalRequest | null = null;
  @State private messages: ChatMessage[] = [
    new ChatMessage(
      'welcome-1',
      'ArkPilot',
      'assistant',
      '前端会自动连接应用内置 app-server。必要时你仍然可以手动重连或修改工作目录。',
      '刚刚'
    )
  ];
  @State private codeLines: CodeDiffLine[] = [
    new CodeDiffLine('placeholder-1', '1', ' ', '等待 turn/diff/updated 通知。', 'context')
  ];
  @State private tokenUsage: TurnTokenUsage | null = null;
  @State private tokenAggregate: TokenUsageAggregate | null = null;
  @State private tokenCardExpanded: boolean = true;
  @State private tokenTab: number = 0;

  aboutToAppear(): void {
    this.backendSubscriptionId = codexBackend.subscribe((snapshot: CodexBackendSnapshot) => {
      this.applyBackendSnapshot(snapshot);
    });
    this.applyBackendSnapshot(codexBackend.snapshot());
    this.applyEmbeddedHostStatus();
    this.loadProviderConfig();
    this.restoreWorkspaceBindings();

    // Check if SessionsPage passed a selected session ID
    const selectedSessionId: string = (AppStorage.get('sessionsPageSelectedSessionId') as string) ?? '';
    if (selectedSessionId.trim().length > 0) {
      AppStorage.setOrCreate('sessionsPageSelectedSessionId', '');
      void this.loadSessionFromSessionsPage(selectedSessionId);
    } else {
      void this.restoreSessionsFromBackend();
    }

    this.scheduleEmbeddedHostReconnect(0);
    this.scheduleMessageScrollToBottom();
  }

  aboutToDisappear(): void {
    if (this.backendSubscriptionId >= 0) {
      codexBackend.unsubscribe(this.backendSubscriptionId);
    }
    this.clearReconnectTimer();
  }

  private applyBackendSnapshot(snapshot: CodexBackendSnapshot): void {
    this.serverUrl = snapshot.serverUrl;
    this.connectionState = snapshot.connectionState;
    this.connectionText = snapshot.connectionText;
    this.pendingApproval = snapshot.pendingApproval;
    if (snapshot.tokenUsage !== null && snapshot.tokenUsage !== undefined) {
      this.tokenUsage = snapshot.tokenUsage;
    }
  }

  private applyEmbeddedHostStatus(): void {
    const hostStatus = getEmbeddedCodexHostStatus();
    if (hostStatus.serverUrl.trim().length > 0) {
      this.serverUrl = hostStatus.serverUrl;
    }

    if (hostStatus.running) {
      this.summaryTitle = '应用内后端已启动';
      this.summaryPoints = [
        hostStatus.message,
        '页面会自动尝试连接本地 原生桥接 服务。',
        '如果需要调试，也可以手动断开后重新连接。'
      ];
      return;
    }

    if (hostStatus.message.trim().length > 0) {
      this.summaryTitle = '应用内后端未就绪';
      this.summaryPoints = [
        hostStatus.message,
        '可以稍后点击连接重试。',
        '如果持续失败，需要检查 native/Rust 构建产物是否被正确打包。'
      ];
    }
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimerId >= 0) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = -1;
    }
  }

  private scheduleEmbeddedHostReconnect(delayMs: number): void {
    this.clearReconnectTimer();
    this.reconnectTimerId = setTimeout(() => {
      this.reconnectTimerId = -1;
      void this.connectEmbeddedHost();
    }, delayMs);
  }

  private activeWorkspace(): WorkspaceItem | undefined {
    if (this.workspaces.length === 0) {
      return undefined;
    }
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      if (this.workspaces[index].id === this.activeWorkspaceId) {
        return this.workspaces[index];
      }
    }
    return this.workspaces[0];
  }

  private syncCurrentWorkspaceState(): void {
    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace === undefined) {
      this.currentWorkspaceTitle = '';
      this.currentWorkspaceDescription = '';
      return;
    }
    this.currentWorkspaceTitle = workspace.title;
    this.currentWorkspaceDescription = workspace.description;
  }

  private syncRecentWorkspaces(): void {
    const filter = this.directoryFilter.trim();
    if (filter.length === 0) {
      this.recentWorkspaces = [...this.workspaces].reverse();
      return;
    }
    const filtered = this.workspaces.filter((item: WorkspaceItem) => {
      const root = this.workspaceRoots.get(item.id) ?? '';
      return root.trim().length === 0 || root.trim() === filter;
    });
    this.recentWorkspaces = [...filtered].reverse();
  }

  private ensureWorkspaceBinding(item: WorkspaceItem): string {
    const existing: string | undefined = this.workspaceIds.get(item.id);
    if (existing !== undefined && existing.trim().length > 0) {
      item.workspaceId = existing;
      return existing;
    }
    const workspaceId: string = item.workspaceId.trim().length > 0 ? item.workspaceId : `session:${item.id.toString()}`;
    item.workspaceId = workspaceId;
    this.workspaceIds.set(item.id, workspaceId);
    return workspaceId;
  }

  private refreshWorkspaceBindingState(): void {
    if (this.workspaces.length === 0) {
      this.activeWorkspaceBindingId = '';
      this.activeWorkspacePermissionState = 'unavailable';
      this.activeWorkspaceAccessKind = 'unknown';
      this.workspaceStatusText = '';
      return;
    }
    const active: WorkspaceItem = this.activeWorkspace()!;
    this.activeWorkspaceBindingId = this.ensureWorkspaceBinding(active);
    const currentWorkspaceRoot: string = this.workspaceDraftText.trim().length > 0 ? this.workspaceDraftText.trim() : this.workspaceRoot.trim();
    if (currentWorkspaceRoot.length > 0) {
      const status: WorkspaceAccessStatus = checkWorkspaceAccess(currentWorkspaceRoot);
      this.activeWorkspacePermissionState = this.mapWorkspacePermissionState(status.permissionState);
      this.activeWorkspaceAccessKind = this.mapWorkspaceAccessKind(status.accessKind);
      this.workspaceStatusText = status.message.trim().length > 0 ? status.message : 'å·¥ä½œåŒºå·²é…ç½®';
      return;
    }
    this.activeWorkspacePermissionState = 'unavailable';
    this.activeWorkspaceAccessKind = 'unknown';
    this.workspaceStatusText = 'å½“å‰æœªé…ç½®å·¥ä½œåŒº';
  }

  private initializeDefaultWorkspace(): void {
    const defaultWorkspaceRoot: string = AppStorage.get('defaultWorkspaceRoot') as string ?? '';
    if (this.workspaceRoot.trim().length === 0 && defaultWorkspaceRoot.trim().length > 0) {
      this.workspaceRoot = defaultWorkspaceRoot;
      this.workspaceRoots.set(this.activeWorkspaceId, defaultWorkspaceRoot);
    }
    if (this.workspaceDraftText.trim().length === 0) {
      this.workspaceDraftText = this.workspaceRoot;
    }
    this.refreshWorkspaceBindingState();
  }

  private nextWorkspaceId(): number {
    let nextId: number = this.activeWorkspaceId > 0 ? this.activeWorkspaceId + 1 : 1;
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      if (this.workspaces[index].id >= nextId) {
        nextId = this.workspaces[index].id + 1;
      }
    }
    this.workspaceIds.forEach((_workspaceId: string, key: number) => {
      if (key >= nextId) {
        nextId = key + 1;
      }
    });
    return nextId;
  }

  private ensurePlaceholderWorkspace(preferredId?: number): WorkspaceItem {
    if (this.workspaces.length > 0) {
      return this.workspaces[0];
    }
    const workspaceId: number = preferredId !== undefined && preferredId > 0 ? preferredId : this.nextWorkspaceId();
    const workspace: WorkspaceItem = new WorkspaceItem(
      workspaceId,
      `新会话 ${workspaceId}`,
      '等待通过 app-server 创建真实会话',
      `session:${workspaceId.toString()}`
    );
    this.workspaces = [workspace];
    this.syncRecentWorkspaces();
    this.workspaceIds.set(workspace.id, workspace.workspaceId);
    this.currentWorkspaceTitle = workspace.title;
    this.currentWorkspaceDescription = workspace.description;
    return workspace;
  }

  private isRemoteThreadId(workspaceId: string): boolean {
    const trimmedWorkspaceId: string = workspaceId.trim();
    return trimmedWorkspaceId.length > 0 && !trimmedWorkspaceId.startsWith('session:');
  }

  private workspaceDescriptionFromSummary(summary: SessionSummary): string {
    const changedFiles: string = summary.changedFiles.trim();
    if (changedFiles.length > 0 && changedFiles !== '尚未产生文件改动') {
      return changedFiles;
    }
    const summaryTitle: string = summary.summaryTitle.trim();
    if (summaryTitle.length > 0) {
      return summaryTitle;
    }
    return '已从 app-server 恢复的历史会话';
  }

  private resetConversationSurface(title: string, points?: string[]): void {
    this.messages = [
      new ChatMessage(
        'welcome-1',
        'ArkPilot',
        'assistant',
        '前端会自动连接应用内置 app-server。必要时你仍然可以手动重连或修改工作目录。',
        '刚刚'
      )
    ];
    this.codeLines = [
      new CodeDiffLine('placeholder-1', '1', ' ', '等待 turn/diff/updated 通知。', 'context')
    ];
    this.diffFiles = [];
    this.selectedDiffFilePath = '';
    this.summaryTitle = title;
    this.summaryPoints = points ?? ['当前会话尚未产生历史消息。'];
    this.changedFiles = '尚未产生文件改动';
    this.diffStat = '+0 -0';
  }

  private async restoreSessionsFromBackend(preferredThreadId?: string): Promise<void> {
    const sessions: SessionSummary[] = await codexBackend.loadPersistedSessions();
    this.applySessionSummariesToWorkspaces(sessions, preferredThreadId);
    await this.loadSelectedWorkspaceHistory();
  }

  private syncSessionSummariesFromCache(preferredThreadId?: string): void {
    const sessions: SessionSummary[] = codexBackend.sessionSummaries();
    this.applySessionSummariesToWorkspaces(sessions, preferredThreadId);
  }

  private applySessionSummariesToWorkspaces(summaries: SessionSummary[], preferredThreadId?: string): void {
    if (summaries.length === 0) {
      this.workspaces = [];
      this.activeWorkspaceId = 0;
      this.workspaceRoot = '';
      this.workspaceDraftText = '';
      this.currentWorkspaceTitle = '';
      this.currentWorkspaceDescription = '';
      this.syncRecentWorkspaces();
      this.syncWorkspaceSelectionText();
      this.refreshWorkspaceBindingState();
      this.persistWorkspaceBindings();
      return;
    }

    const currentWorkspaceByThreadId: Map<string, WorkspaceItem> = new Map();
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const workspace: WorkspaceItem = this.workspaces[index];
      if (this.isRemoteThreadId(workspace.workspaceId)) {
        currentWorkspaceByThreadId.set(workspace.workspaceId, workspace);
      }
    }

    const bindingSnapshot = workspaceBindingStore.load();
    const bindingByThreadId: Map<string, StoredWorkspaceItem> = new Map();
    for (let index: number = 0; index < bindingSnapshot.items.length; index += 1) {
      const item: StoredWorkspaceItem = bindingSnapshot.items[index];
      if (this.isRemoteThreadId(item.workspaceId)) {
        bindingByThreadId.set(item.workspaceId, item);
      }
    }

    const activeWorkspace: WorkspaceItem | undefined = this.activeWorkspace();
    const activePlaceholderId: number = activeWorkspace !== undefined && !this.isRemoteThreadId(activeWorkspace.workspaceId) ? activeWorkspace.id : 0;
    const nextWorkspaces: WorkspaceItem[] = [];
    const nextWorkspaceIds: Map<number, string> = new Map();
    const nextWorkspaceRoots: Map<number, string> = new Map();
    const nextWorkspaceUris: Map<number, string> = new Map();
    const usedIds: Set<number> = new Set();
    let nextIdSeed: number = this.nextWorkspaceId();
    let nextActiveWorkspaceId: number = 0;

    for (let index: number = 0; index < summaries.length; index += 1) {
      const summary: SessionSummary = summaries[index];
      let workspaceId: number | undefined = currentWorkspaceByThreadId.get(summary.sessionId)?.id;
      if (workspaceId === undefined) {
        workspaceId = bindingByThreadId.get(summary.sessionId)?.id;
      }
      if (workspaceId === undefined && preferredThreadId !== undefined && summary.sessionId === preferredThreadId && activePlaceholderId > 0) {
        workspaceId = activePlaceholderId;
      }
      while (workspaceId === undefined || usedIds.has(workspaceId)) {
        workspaceId = nextIdSeed;
        nextIdSeed += 1;
      }
      usedIds.add(workspaceId);

      const workspace: WorkspaceItem = new WorkspaceItem(
        workspaceId,
        summary.title,
        this.workspaceDescriptionFromSummary(summary),
        summary.sessionId
      );
      nextWorkspaces.push(workspace);
      nextWorkspaceIds.set(workspace.id, summary.sessionId);

      const existingRoot: string = this.workspaceRoots.get(workspace.id) ?? bindingByThreadId.get(summary.sessionId)?.workspaceRoot ?? '';
      const nextRoot: string = existingRoot.trim().length > 0 ? existingRoot : summary.workspaceRoot.trim();
      nextWorkspaceRoots.set(workspace.id, nextRoot);
      nextWorkspaceUris.set(workspace.id, this.workspaceUris.get(workspace.id) ?? bindingByThreadId.get(summary.sessionId)?.workspaceUri ?? '');

      if (summary.sessionId === preferredThreadId || (nextActiveWorkspaceId === 0 && summary.sessionId === this.activeWorkspaceBindingId)) {
        nextActiveWorkspaceId = workspace.id;
      }
    }

    if (nextActiveWorkspaceId === 0) {
      const matched: WorkspaceItem | undefined = nextWorkspaces.find((item: WorkspaceItem) => item.id === this.activeWorkspaceId);
      nextActiveWorkspaceId = matched?.id ?? nextWorkspaces[0].id;
    }

    this.workspaces = [...nextWorkspaces];
    this.syncRecentWorkspaces();
    this.workspaceIds.clear();
    this.workspaceRoots.clear();
    this.workspaceUris.clear();
    nextWorkspaceIds.forEach((value: string, key: number) => this.workspaceIds.set(key, value));
    nextWorkspaceRoots.forEach((value: string, key: number) => this.workspaceRoots.set(key, value));
    nextWorkspaceUris.forEach((value: string, key: number) => this.workspaceUris.set(key, value));
    this.activeWorkspaceId = nextActiveWorkspaceId;
    this.workspaceRoot = this.workspaceRoots.get(this.activeWorkspaceId) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
  }

  private async loadSessionFromSessionsPage(sessionId: string): Promise<void> {
    await this.restoreSessionsFromBackend(sessionId);
    const workspace: WorkspaceItem | undefined = this.findWorkspaceBySessionId(sessionId);
    if (workspace !== undefined) {
      this.directoryFilter = this.workspaceRoot;
      this.directoryFilterText = this.workspaceRoot.length > 0 ? this.workspaceRoot : '使用默认工作区';
      this.syncRecentWorkspaces();
      this.draft = `继续处理"${workspace.title}"，重点关注当前工作目录。`;
    }
  }

  private findWorkspaceBySessionId(sessionId: string): WorkspaceItem | undefined {
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const workspace: WorkspaceItem = this.workspaces[index];
      if (this.ensureWorkspaceBinding(workspace) === sessionId) {
        return workspace;
      }
    }
    return undefined;
  }

  private async loadSelectedWorkspaceHistory(): Promise<void> {
    if (this.workspaces.length === 0) {
      this.resetConversationSurface('当前目录下暂无会话', ['请先创建一个新会话。']);
      return;
    }
    const workspace: WorkspaceItem = this.activeWorkspace()!;
    if (!this.isRemoteThreadId(workspace.workspaceId)) {
      this.resetConversationSurface('等待创建新会话', ['当前会话尚未在 app-server 中创建，发送第一条消息后会自动建立线程。']);
      return;
    }
    try {
      const result: CodexTurnResult = await codexBackend.loadThreadHistory(workspace.workspaceId);
      this.applyBackendResult(result);
    } catch (err) {
      this.summaryTitle = '恢复会话失败';
      this.summaryPoints = [this.describeError(err)];
    }
  }

  private syncWorkspaceWithRemoteThreadId(remoteThreadId: string): void {
    const trimmedThreadId: string = remoteThreadId.trim();
    if (trimmedThreadId.length === 0 || this.workspaces.length === 0) {
      return;
    }
    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace === undefined) {
      return;
    }
    workspace.workspaceId = trimmedThreadId;
    this.workspaceIds.set(workspace.id, trimmedThreadId);
    this.activeWorkspaceBindingId = trimmedThreadId;
    this.persistWorkspaceBindings();
  }

  private restoreWorkspaceBindings(): void {
    const snapshot = workspaceBindingStore.load();
    const restoredItems: WorkspaceBindingDraft[] = [];
    this.workspaceIds.clear();
    this.workspaceRoots.clear();
    this.workspaceUris.clear();
    this.workspaces = [];
    for (let index: number = 0; index < snapshot.items.length; index += 1) {
      const item = snapshot.items[index];
      if (item.id <= 0) {
        continue;
      }
      restoredItems.push(new WorkspaceBindingDraft(
        item.id,
        item.title.trim().length > 0 ? item.title : `ä¼šè¯ ${item.id}`,
        item.description,
        item.workspaceId.trim().length > 0 ? item.workspaceId : `session:${item.id.toString()}`,
        item.workspaceRoot,
        item.workspaceUri
      ));
    }

    if (restoredItems.length === 0) {
      this.activeWorkspaceId = snapshot.activeWorkspaceId > 0 ? snapshot.activeWorkspaceId : 1;
      this.ensurePlaceholderWorkspace(this.activeWorkspaceId);
      this.initializeDefaultWorkspace();
      this.syncWorkspaceSelectionText();
      this.syncCurrentWorkspaceState();
      this.persistWorkspaceBindings();
      return;
    }

    const restoredWorkspaces: WorkspaceItem[] = [];
    for (let index: number = 0; index < restoredItems.length; index += 1) {
      const restored: WorkspaceBindingDraft = restoredItems[index];
      const workspace: WorkspaceItem = new WorkspaceItem(restored.id, restored.title, restored.description, restored.workspaceId);
      restoredWorkspaces.push(workspace);
      this.workspaceIds.set(restored.id, restored.workspaceId);
      this.workspaceRoots.set(restored.id, restored.workspaceRoot);
      this.workspaceUris.set(restored.id, restored.workspaceUri);
    }
    this.workspaces = restoredWorkspaces;
    this.syncRecentWorkspaces();

    const preferredActiveId: number = snapshot.activeWorkspaceId > 0 ? snapshot.activeWorkspaceId : restoredItems[0].id;
    const matched: WorkspaceItem | undefined = this.workspaces.find((item: WorkspaceItem) => item.id === preferredActiveId);
    this.activeWorkspaceId = matched?.id ?? this.workspaces[0].id;
    this.workspaceRoot = this.workspaceRoots.get(this.activeWorkspaceId) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
  }

  private persistWorkspaceBindings(): void {
    const items: StoredWorkspaceItem[] = [];
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const workspace: WorkspaceItem = this.workspaces[index];
      const item: StoredWorkspaceItem = new StoredWorkspaceItem();
      item.id = workspace.id;
      item.title = workspace.title;
      item.description = workspace.description;
      item.workspaceId = this.ensureWorkspaceBinding(workspace);
      item.workspaceRoot = this.workspaceRoots.get(workspace.id) ?? '';
      item.workspaceUri = this.workspaceUris.get(workspace.id) ?? '';
      items.push(item);
    }
    workspaceBindingStore.saveBindings(this.activeWorkspaceId, items);
  }

  private applyWorkspaceRootBinding(): void {
    const trimmedWorkspaceRoot: string = this.workspaceDraftText.trim();
    this.workspaceRoot = trimmedWorkspaceRoot;
    this.workspaceRoots.set(this.activeWorkspaceId, trimmedWorkspaceRoot);
    this.workspaceUris.set(this.activeWorkspaceId, '');
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.persistWorkspaceBindings();
  }

  private applyWorkspaceDirectorySelection(workspaceRoot: string, workspaceUri: string): void {
    const trimmedWorkspaceRoot: string = workspaceRoot.trim();
    this.directoryFilter = trimmedWorkspaceRoot;
    this.directoryFilterText = trimmedWorkspaceRoot.length > 0 ? trimmedWorkspaceRoot : '使用默认工作区';
    this.syncRecentWorkspaces();
  }

  private syncWorkspaceSelectionText(): void {
    const workspaceUri: string = this.workspaceUris.get(this.activeWorkspaceId) ?? '';
    if (workspaceUri.trim().length > 0) {
      this.workspaceSelectionText = `已选择目录: ${workspaceUri}`;
      return;
    }
    if (this.workspaceRoot.trim().length > 0) {
      this.workspaceSelectionText = `当前工作目录: ${this.workspaceRoot}`;
      return;
    }
    this.workspaceSelectionText = '使用默认工作区';
  }

  private async pickDirectorySelection(): Promise<WorkspaceDirectorySelection | null> {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      throw new Error('当前页面上下文不可用，无法打开目录选择器。');
    }
    const documentPicker = new picker.DocumentViewPicker(hostContext);
    const selectedUris: Array<string> = await documentPicker.select({
      selectMode: picker.DocumentSelectMode.FOLDER
    });
    if (selectedUris.length === 0) {
      return null;
    }
    const selectedUri: string = selectedUris[0];
    const parsedUri = new uri.URI(selectedUri);
    const candidatePath: string = decodeURIComponent(parsedUri.path ?? '');
    if (candidatePath.trim().length === 0) {
      throw new Error(`目录已选择，但暂时无法解析路径: ${selectedUri}`);
    }
    return new WorkspaceDirectorySelection(candidatePath, selectedUri);
  }

  private async pickWorkspaceDirectory(): Promise<void> {
    try {
      const selection: WorkspaceDirectorySelection | null = await this.pickDirectorySelection();
      if (selection === null) {
        this.workspaceStatusText = '未选择目录，继续使用当前工作区。';
        return;
      }
      this.applyWorkspaceDirectorySelection(selection.rootPath, selection.sourceUri);
    } catch (err) {
      this.workspaceStatusText = `选择目录失败: ${this.describeError(err)}`;
    }
  }

  private mapWorkspacePermissionState(value: string): WorkspacePermissionState {
    if (value === 'writable' || value === 'readonly' || value === 'revoked') {
      return value;
    }
    return 'unavailable';
  }

  private mapWorkspaceAccessKind(value: string): WorkspaceAccessKind {
    if (value === 'sandbox' || value === 'user_granted' || value === 'readonly') {
      return value;
    }
    return 'unknown';
  }

  private currentModelLabel(): string {
    const model: string = this.manualModel.trim();
    if (model.length === 0) {
      return 'default';
    }
    return model;
  }

  private currentModelValue(): string {
    const model: string = this.manualModel.trim();
    if (model.length === 0) {
      return 'default';
    }
    return model;
  }

  private currentEffortLabel(): string {
    return this.effortOptions[this.selectedEffortIndex].label;
  }

  private currentEffortValue(): string {
    return this.effortOptions[this.selectedEffortIndex].value;
  }

  private sendMessage(): void {
    const prompt: string = this.draft.trim();
    if (prompt.length === 0 || this.isRunning) {
      return;
    }
    this.savedDraft = this.draft;
    this.draft = '';
    void this.runTurn(prompt);
  }

  private stopTurn(): void {
    codexBackend.interruptTurn();
  }

  private async runTurn(prompt: string): Promise<void> {
    if (this.workspaces.length === 0) {
      return;
    }
    this.isRunning = true;
    if (this.workspaceDraftText.trim() !== this.workspaceRoot.trim()) {
      this.applyWorkspaceRootBinding();
    }
    this.workspaceRoots.set(this.activeWorkspaceId, this.workspaceRoot);
    this.refreshWorkspaceBindingState();
    codexBackend.configureServerUrl(this.serverUrl);

    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace === undefined) {
      this.isRunning = false;
      return;
    }
    const trimmedWorkspaceRoot: string = this.workspaceRoot.trim();
    const threadKey: string = workspace.workspaceId.trim().length > 0 ? workspace.workspaceId : this.activeWorkspaceBindingId;
    this.applyEmbeddedHostStatus();
    try {
      const result: CodexTurnResult = await codexBackend.startTurn(
        new CodexTurnRequest(
          threadKey,
          workspace.title,
          this.activeWorkspaceBindingId,
          trimmedWorkspaceRoot,
          this.activeWorkspacePermissionState,
          this.activeWorkspaceAccessKind,
          trimmedWorkspaceRoot.length > 0 ? [trimmedWorkspaceRoot] : [],
          this.currentModelValue(),
          this.currentEffortValue(),
          prompt
        ),
        (update: CodexTurnResult) => {
          this.applyBackendResult(update);
        }
      );
      this.applyBackendResult(result);
      if (result.status === 'interrupted') {
        this.draft = this.savedDraft;
      }
      this.savedDraft = '';
    } catch (err) {
      this.summaryTitle = '调用失败';
      this.summaryPoints = [this.describeError(err)];
      this.draft = this.savedDraft;
      this.savedDraft = '';
    } finally {
      this.isRunning = false;
    }
  }

  private applyBackendResult(result: CodexTurnResult): void {
    this.syncWorkspaceWithRemoteThreadId(result.threadId);
    this.messages = result.messages.map((item) => {
      return new ChatMessage(item.messageId, item.author, item.role, item.content, item.timestamp, item.itemType, item.status, item.metadata);
    });
    this.codeLines = result.diffLines.length > 0
      ? result.diffLines.map((line: CodexDiffLine) => {
          return new CodeDiffLine(line.lineId, line.lineNumber, line.sign, line.content, line.kind, line.filePath);
        })
      : [new CodeDiffLine('placeholder-2', '1', ' ', '本轮尚未产生 diff。', 'context')];
    if (result.diffLines.length > 0) {
      this.applyDiffFiles(this.buildDiffFiles(this.codeLines));
    } else {
      this.diffFiles = [];
      this.selectedDiffFilePath = '';
    }
    this.summaryTitle = result.summaryTitle;
    this.summaryPoints = result.summaryPoints.length > 0 ? result.summaryPoints : ['没有可展示的摘要信息。'];
    this.changedFiles = result.changedFiles;
    this.diffStat = result.diffStat;
    if (result.tokenUsage !== null && result.tokenUsage !== undefined) {
      this.tokenUsage = result.tokenUsage;
    }
    this.tokenAggregate = codexBackend.fetchTokenUsageAggregate();
    this.scheduleMessageScrollToBottom();
  }

  private scheduleMessageScrollToBottom(): void {
    setTimeout(() => {
      this.scrollMessagesToBottom();
    }, 0);
    setTimeout(() => {
      this.scrollMessagesToBottom();
    }, 32);
  }

  private scrollMessagesToBottom(): void {
    try {
      this.messageScroller.scrollEdge(Edge.Bottom);
    } catch (_err) {
    }
  }

  private messageRenderKey(item: ChatMessage): string {
    return `${item.id}:${item.content.length}:${item.timestamp}`;
  }

  private async connectOrDisconnect(): Promise<void> {
    codexBackend.configureServerUrl(this.serverUrl);
    if (this.connectionState === 'connected' || this.connectionState === 'connecting') {
      await codexBackend.disconnect();
      return;
    }

    try {
      await codexBackend.connect();
      this.loadProviderConfig();
      await this.restoreSessionsFromBackend();
      this.reconnectAttemptCount = 0;
      this.clearReconnectTimer();
      this.summaryTitle = '连接成功';
      this.summaryPoints = [
        'initialize / initialized 握手已经完成。',
        '现在可以直接发送 turn/start 请求。',
        '如需针对项目操作，请填写真实工作目录。'
      ];
    } catch (err) {
      this.summaryTitle = '连接失败';
      this.summaryPoints = [this.describeError(err)];
    }
  }

  private async connectEmbeddedHost(): Promise<void> {
    if (this.connectionState === 'connected' || this.connectionState === 'connecting') {
      return;
    }

    try {
      codexBackend.configureServerUrl(this.serverUrl);
      await codexBackend.connect();
      this.loadProviderConfig();
      await this.restoreSessionsFromBackend();
      this.summaryTitle = '应用内后端连接成功';
      this.summaryPoints = [
        'initialize / initialized 握手已经完成。',
        '当前页面连接的是应用内自启动的 Rust app-server。',
        '现在可以直接发送 turn/start 请求。'
      ];
    } catch (err) {
      this.reconnectAttemptCount += 1;
      const hostStatus = getEmbeddedCodexHostStatus();
      const retryDelayMs: number = Math.min(1500 * this.reconnectAttemptCount, 6000);
      this.summaryTitle = '应用内后端连接失败';
      this.summaryPoints = [
        hostStatus.message.length > 0 ? hostStatus.message : 'embedded host status unavailable',
        this.describeError(err),
        `系统将在 ${retryDelayMs} ms 后自动重试连接。`,
        '可以点击连接按钮重试，或者检查 native 日志。'
      ];
      this.scheduleEmbeddedHostReconnect(retryDelayMs);
    }
  }

  private async loginWithApiKey(): Promise<void> {
    if (this.isAuthenticating) {
      return;
    }

    const apiKey: string = this.apiKey.trim();
    if (apiKey.length === 0) {
      this.summaryTitle = '登录失败';
      this.summaryPoints = ['请先输入 OpenAI API Key。'];
      return;
    }

    this.isAuthenticating = true;
    try {
      await codexBackend.loginWithApiKey(apiKey);
      this.summaryTitle = 'OpenAI 认证已就绪';
      this.summaryPoints = [
        '已经通过 account/login/start 完成 API Key 登录。',
        '现在可以重新发送你的问题。',
        this.authStatusText
      ];
    } catch (err) {
      this.summaryTitle = '登录失败';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isAuthenticating = false;
    }
  }

  private loadProviderConfig(): void {
    const config: CodexProviderConfig = getEmbeddedCodexProviderConfig();
    const catalog = getEmbeddedCodexProviderCatalog();
    this.providerBaseUrl = config.baseUrl;
    this.providerApiKey = config.apiKey;
    this.manualModel = config.model;
    this.providerStatusText = this.describeProviderConfig(config);
    // 从 catalog 中获取当前激活的 provider 名称
    let activeName: string = '未选择';
    for (let i = 0; i < catalog.providers.length; i++) {
      if (catalog.providers[i].isActive) {
        activeName = catalog.providers[i].name;
        break;
      }
    }
    if (activeName === '未选择' && catalog.providers.length > 0) {
      activeName = catalog.providers[0].name;
    }
    this.providerName = activeName;
    hilog.info(
      INDEX_DOMAIN,
      INDEX_TAG,
      'loadProviderConfig baseUrl=%{public}s model=%{public}s apiKeyLen=%{public}d catalogProviders=%{public}d',
      config.baseUrl,
      config.model,
      config.apiKey.length,
      catalog.providers.length
    );
  }

  private async saveProviderConfig(): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }

    this.isSavingProvider = true;
    try {
      hilog.info(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig input baseUrl=%{public}s model=%{public}s apiKeyLen=%{public}d',
        this.providerBaseUrl.trim(),
        this.manualModel.trim(),
        this.providerApiKey.trim().length
      );
      const config: CodexProviderConfig = saveEmbeddedCodexProviderConfig(
        this.providerBaseUrl.trim(),
        this.providerApiKey.trim(),
        this.manualModel.trim()
      );
      hilog.info(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig native returned baseUrl=%{public}s model=%{public}s apiKeyLen=%{public}d',
        config.baseUrl,
        config.model,
        config.apiKey.length
      );
      this.providerBaseUrl = config.baseUrl;
      this.providerApiKey = config.apiKey;
      this.manualModel = config.model;
      const importedCatalog = providerCatalogService.importCurrentProvider();
      hilog.info(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig imported catalog activeProviderId=%{public}s providers=%{public}d',
        importedCatalog.activeProviderId,
        importedCatalog.providers.length
      );
      this.providerStatusText = this.describeProviderConfig(config);
      this.summaryTitle = 'Provider config saved';
      this.summaryPoints = [
        'base_url, api_key, and default model were written to CODEX_HOME and synced to the active provider catalog.',
        'Restart the app to apply provider changes to the embedded app-server runtime.',
        this.providerStatusText
      ];
    } catch (err) {
      hilog.error(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig failed: %{public}s',
        this.describeError(err)
      );
      hilog.error(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig error details: %{public}s',
        JSON.stringify(err)
      );
      if (err instanceof Error && err.stack !== undefined) {
        hilog.error(
          INDEX_DOMAIN,
          INDEX_TAG,
          'saveProviderConfig stack: %{public}s',
          err.stack
        );
      }
      this.summaryTitle = 'Provider config failed';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isSavingProvider = false;
    }
  }

  private async approvePending(): Promise<void> {
    await codexBackend.approvePendingRequest();
  }

  private async declinePending(): Promise<void> {
    await codexBackend.declinePendingRequest();
  }

  private async selectWorkspace(item: WorkspaceItem): Promise<void> {
    this.activeWorkspaceId = item.id;
    this.workspaceRoot = this.workspaceRoots.get(item.id) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.directoryFilter = this.workspaceRoot;
    this.directoryFilterText = this.workspaceRoot.length > 0 ? this.workspaceRoot : '使用默认工作区';
    this.syncRecentWorkspaces();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.draft = `继续处理”${item.title}”，重点关注当前工作目录。`;
    this.activeSidebarView = 'chat';
    this.persistWorkspaceBindings();
    await this.loadSelectedWorkspaceHistory();
  }

  private connectionButtonLabel(): string {
    if (this.connectionState === 'connected') {
      return '断开';
    }
    if (this.connectionState === 'connecting') {
      return '连接中';
    }
    return '连接';
  }

  private authButtonLabel(): string {
    return 'Log in';
  }

  private providerButtonLabel(): string {
    if (this.isSavingProvider) {
      return 'Saving...';
    }
    return 'Save provider';
  }

  private describeProviderConfig(config: CodexProviderConfig): string {
    const baseUrl: string = config.baseUrl.trim().length > 0 ? config.baseUrl.trim() : 'https://api.openai.com/v1';
    const model: string = config.model.trim().length > 0 ? config.model.trim() : 'default';
    const auth: string = config.apiKey.trim().length > 0 ? 'API key set' : 'No API key';
    return `base_url: ${baseUrl} | model: ${model} | ${auth}`;
  }

  private connectionChipBackground(): string {
    if (this.connectionState === 'connected') {
      return '#DCFCE7';
    }
    if (this.connectionState === 'connecting') {
      return '#FEF3C7';
    }
    if (this.connectionState === 'error') {
      return '#FEE2E2';
    }
    return '#E2E8F0';
  }

  private connectionChipColor(): string {
    if (this.connectionState === 'connected') {
      return '#166534';
    }
    if (this.connectionState === 'connecting') {
      return '#92400E';
    }
    if (this.connectionState === 'error') {
      return '#B91C1C';
    }
    return '#475569';
  }

  private messageBackground(role: string): string {
    switch (role) {
      case 'assistant':
      case 'agent':
        return '#FFFFFF';
      case 'system':
        return '#F8FAFC';
      case 'reasoning':
        return '#FFFBEB';
      case 'command':
        return '#F0FDF4';
      case 'tool':
        return '#EFF6FF';
      case 'file':
        return '#FDF4FF';
      case 'search':
        return '#ECFDF5';
      case 'plan':
        return '#FFF7ED';
      case 'image':
        return '#FDF2F8';
      case 'hook':
        return '#FEF3C7';
      case 'review':
        return '#FEF08A';
      case 'user':
      default:
        return '#F6F3FF';
    }
  }

  private messageBorder(role: string): string {
    switch (role) {
      case 'assistant':
      case 'agent':
        return '#DBEAFE';
      case 'system':
        return '#CBD5E1';
      case 'reasoning':
        return '#FEF3C7';
      case 'command':
        return '#BBF7D0';
      case 'tool':
        return '#BFDBFE';
      case 'file':
        return '#E9D5FF';
      case 'search':
        return '#A7F3D0';
      case 'plan':
        return '#FED7AA';
      case 'image':
        return '#FBCFE8';
      case 'hook':
        return '#FCD34D';
      case 'review':
        return '#FACC15';
      case 'user':
      default:
        return '#DDD6FE';
    }
  }

  private authorColor(role: string): string {
    switch (role) {
      case 'assistant':
      case 'agent':
        return '#1D4ED8';
      case 'system':
        return '#475569';
      case 'reasoning':
        return '#D97706';
      case 'command':
        return '#059669';
      case 'tool':
        return '#2563EB';
      case 'file':
        return '#9333EA';
      case 'search':
        return '#10B981';
      case 'plan':
        return '#EA580C';
      case 'image':
        return '#DB2777';
      case 'hook':
        return '#B45309';
      case 'review':
        return '#A16207';
      case 'user':
      default:
        return '#7C3AED';
    }
  }

  private diffBackground(kind: string): string {
    if (kind === 'add') {
      return '#ECFDF3';
    }
    if (kind === 'delete') {
      return '#FEF2F2';
    }
    return '#F8FAFC';
  }

  private diffColor(kind: string): string {
    if (kind === 'add') {
      return '#15803D';
    }
    if (kind === 'delete') {
      return '#DC2626';
    }
    return '#475569';
  }

  private isWorkspaceActive(item: WorkspaceItem): boolean {
    return this.activeWorkspaceId === item.id;
  }

  private isSidebarActive(view: SidebarView): boolean {
    return this.activeSidebarView === view;
  }

  private toggleLeftDrawer(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.showLeftDrawer = !this.showLeftDrawer;
    });
  }

  private toggleRightDrawer(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.showRightDrawer = !this.showRightDrawer;
    });
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }

  private placeholderDiffLine(id: string, content: string): CodeDiffLine {
    return new CodeDiffLine(id, '1', ' ', content, 'context');
  }

  private diffFileKey(filePath: string): string {
    const trimmedFilePath: string = filePath.trim();
    return trimmedFilePath.length > 0 ? trimmedFilePath : UNKNOWN_DIFF_FILE_TEXT;
  }

  private diffFileDisplayName(filePath: string): string {
    const normalizedPath: string = this.diffFileKey(filePath).replace(/\\/g, '/');
    const slashIndex: number = normalizedPath.lastIndexOf('/');
    return slashIndex >= 0 ? normalizedPath.substring(slashIndex + 1) : normalizedPath;
  }

  private buildDiffFiles(lines: CodeDiffLine[]): CodeDiffFile[] {
    const orderedPaths: string[] = [];
    const groupedLines: Map<string, CodeDiffLine[]> = new Map();
    const addCounts: Map<string, number> = new Map();
    const deleteCounts: Map<string, number> = new Map();

    for (let index: number = 0; index < lines.length; index += 1) {
      const line: CodeDiffLine = lines[index];
      const filePath: string = this.diffFileKey(line.filePath);
      if (!groupedLines.has(filePath)) {
        groupedLines.set(filePath, []);
        addCounts.set(filePath, 0);
        deleteCounts.set(filePath, 0);
        orderedPaths.push(filePath);
      }
      (groupedLines.get(filePath) as CodeDiffLine[]).push(line);
      if (line.kind === 'add') {
        addCounts.set(filePath, (addCounts.get(filePath) ?? 0) + 1);
      } else if (line.kind === 'delete') {
        deleteCounts.set(filePath, (deleteCounts.get(filePath) ?? 0) + 1);
      }
    }

    const files: CodeDiffFile[] = [];
    for (let index: number = 0; index < orderedPaths.length; index += 1) {
      const filePath: string = orderedPaths[index];
      files.push(
        new CodeDiffFile(
          filePath,
          this.diffFileDisplayName(filePath),
          `+${addCounts.get(filePath) ?? 0} -${deleteCounts.get(filePath) ?? 0}`,
          groupedLines.get(filePath) ?? []
        )
      );
    }
    return files;
  }

  private diffFileByPath(path: string, files?: CodeDiffFile[]): CodeDiffFile | null {
    const sourceFiles: CodeDiffFile[] = files ?? this.diffFiles;
    for (let index: number = 0; index < sourceFiles.length; index += 1) {
      if (sourceFiles[index].path === path) {
        return sourceFiles[index];
      }
    }
    return null;
  }

  private applyDiffFiles(files: CodeDiffFile[]): void {
    this.diffFiles = files;
    if (files.length === 0) {
      this.selectedDiffFilePath = '';
      this.codeLines = [this.placeholderDiffLine('placeholder-2', NO_DIFF_TEXT)];
      return;
    }

    let selectedFile: CodeDiffFile | null = this.diffFileByPath(this.selectedDiffFilePath, files);
    if (selectedFile === null) {
      selectedFile = files[0];
    }
    this.selectedDiffFilePath = selectedFile.path;
    this.codeLines = selectedFile.lines.length > 0
      ? selectedFile.lines
      : [this.placeholderDiffLine('placeholder-empty-file', NO_DIFF_TEXT)];
  }

  private selectDiffFile(path: string): void {
    const selectedFile: CodeDiffFile | null = this.diffFileByPath(path);
    if (selectedFile === null) {
      return;
    }
    this.selectedDiffFilePath = selectedFile.path;
    this.codeLines = selectedFile.lines.length > 0
      ? selectedFile.lines
      : [this.placeholderDiffLine('placeholder-empty-file', NO_DIFF_TEXT)];
  }

  private selectedDiffFile(): CodeDiffFile | null {
    return this.diffFileByPath(this.selectedDiffFilePath);
  }

  private currentDiffFilePath(): string {
    const selectedFile: CodeDiffFile | null = this.selectedDiffFile();
    return selectedFile !== null ? selectedFile.path : NO_FILE_CHANGES_TEXT;
  }

  private currentDiffFileStat(): string {
    const selectedFile: CodeDiffFile | null = this.selectedDiffFile();
    return selectedFile !== null ? selectedFile.diffStat : this.diffStat;
  }

  private isDiffFileSelected(file: CodeDiffFile): boolean {
    return this.selectedDiffFilePath === file.path;
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(background)
      .borderRadius(10)
  }

  @Builder
  private panelTitle(title: string, subtitle: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')

      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#94A3B8')
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private selectorButton(label: string, value: string, active: boolean, onPress: () => void) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#64748B')

      Text(value)
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#0F172A')
        .margin({ left: 6 })

      Text('▾')
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#94A3B8')
        .margin({ left: 6 })
    }
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(active ? '#EEF4FF' : '#FFFFFF')
    .border({ width: 1, color: active ? '#BFDBFE' : '#D7DEE8' })
    .borderRadius(12)
    .onClick(() => {
      onPress();
    })
  }

  @Builder
  private optionChip(option: SelectorOption, selected: boolean, onPress: () => void) {
    Text(option.label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor(selected ? '#1D4ED8' : '#475569')
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .backgroundColor(selected ? '#DBEAFE' : '#FFFFFF')
      .border({ width: 1, color: selected ? '#93C5FD' : '#E2E8F0' })
      .borderRadius(10)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        onPress();
      })
  }

  @Builder
  private workspaceRow(item: WorkspaceItem) {
    Column() {
      Text(item.title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontWeight(this.isWorkspaceActive(item) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor('#0F172A')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(item.description)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#64748B')
        .margin({ top: 4 })
        .lineHeight(16)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(10)
    .backgroundColor(this.isWorkspaceActive(item) ? '#EEF4FF' : '#FFFFFF')
    .border({
      width: 1,
      color: this.isWorkspaceActive(item) ? '#BFDBFE' : '#E5E7EB'
    })
    .borderRadius(14)
    .onClick(() => {
      void this.selectWorkspace(item);
    })
  }

  @Builder
  private sidebarRow(item: SidebarItem) {
    Column() {
      Row() {
        Text(item.label)
          .copyOption(CopyOptions.None)
          .fontSize(12)
          .fontWeight(this.isSidebarActive(item.view) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor('#0F172A')

        Blank()
          .layoutWeight(1)
      }
      .width('100%')

      Text(item.description)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#64748B')
        .margin({ top: 4 })
        .lineHeight(16)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(10)
    .backgroundColor(this.isSidebarActive(item.view) ? '#EEF4FF' : '#FFFFFF')
    .border({ width: 1, color: this.isSidebarActive(item.view) ? '#BFDBFE' : '#E5E7EB' })
    .borderRadius(14)
    .margin({ bottom: 6 })
    .onClick(() => {
      if (item.view === 'sessions') {
        router.pushUrl({ url: 'pages/SessionsPage' });
      } else {
        this.activeSidebarView = item.view;
      }
    })
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#94A3B8')
        .width(78)

      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#334155')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ top: 8 })
  }


  @Builder
  private summaryBullet(text: string) {
    Row() {
      Text('•')
        .copyOption(CopyOptions.None)
        .fontSize(12)
        .fontColor('#475569')
        .margin({ right: 6 })

      Text(text)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor('#334155')
        .layoutWeight(1)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private messageCard(item: ChatMessage) {
    Column() {
      Row() {
        Text(this.messageIcon(item.itemType))
          .fontSize(12)
          .margin({ right: 4 })

        Text(item.author)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.authorColor(item.role))

        Text(item.timestamp)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ left: 8 })

        if (item.status && item.status !== 'completed') {
          Text(this.statusLabel(item.status))
            .fontSize(9)
            .fontColor(this.statusColor(item.status))
            .backgroundColor(this.statusBgColor(item.status))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .margin({ left: 8 })
        }
      }
      .width('100%')

      Text(item.content)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .lineHeight(19)
        .fontColor(this.messageContentColor(item.itemType))
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor(this.messageBackground(item.itemType ?? item.role))
    .border({
      width: 1,
      color: this.messageBorder(item.itemType ?? item.role)
    })
    .borderRadius(16)
  }

  private messageIcon(itemType?: string): string {
    switch (itemType) {
      case 'reasoning':
        return '🧠';
      case 'command':
        return '⚡';
      case 'tool':
        return '🔧';
      case 'file':
        return '📄';
      case 'search':
        return '🔍';
      case 'plan':
        return '📋';
      case 'image':
        return '🖼️';
      case 'hook':
        return '🪝';
      case 'review':
        return '👁️';
      case 'system':
        return '⚙️';
      default:
        return '';
    }
  }

  private statusLabel(status: string): string {
    switch (status) {
      case 'inProgress':
        return '进行中';
      case 'failed':
        return '失败';
      case 'declined':
        return '已拒绝';
      default:
        return status;
    }
  }

  private statusColor(status: string): string {
    switch (status) {
      case 'inProgress':
        return '#0369A1';
      case 'failed':
        return '#DC2626';
      case 'declined':
        return '#D97706';
      default:
        return '#64748B';
    }
  }

  private statusBgColor(status: string): string {
    switch (status) {
      case 'inProgress':
        return '#E0F2FE';
      case 'failed':
        return '#FEE2E2';
      case 'declined':
        return '#FEF3C7';
      default:
        return '#F1F5F9';
    }
  }

  private messageContentColor(itemType?: string): string {
    switch (itemType) {
      case 'reasoning':
        return '#6B7280';
      case 'command':
      case 'tool':
        return '#1E40AF';
      default:
        return '#334155';
    }
  }

  @Builder
  private diffRow(line: CodeDiffLine) {
    Row() {
      Text(line.lineNumber)
        .copyOption(CopyOptions.LocalDevice)
        .width(28)
        .fontSize(10)
        .fontColor('#94A3B8')
        .fontFamily('monospace')

      Text(line.sign)
        .copyOption(CopyOptions.LocalDevice)
        .width(12)
        .fontSize(11)
        .fontColor(this.diffColor(line.kind))
        .fontFamily('monospace')

      Text(line.content)
        .copyOption(CopyOptions.LocalDevice)
        .layoutWeight(1)
        .fontSize(10)
        .fontColor(this.diffColor(line.kind))
        .fontFamily('monospace')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .backgroundColor(this.diffBackground(line.kind))
    .borderRadius(10)
  }

  @Builder
  private diffFileRow(file: CodeDiffFile) {
    Row() {
      Column() {
        Text(file.label)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(this.isDiffFileSelected(file) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor('#0F172A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(file.path)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(9)
          .fontColor('#64748B')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(file.diffStat)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor(this.isDiffFileSelected(file) ? '#1D4ED8' : '#15803D')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.isDiffFileSelected(file) ? '#EEF4FF' : '#FFFFFF')
    .border({ width: 1, color: this.isDiffFileSelected(file) ? '#BFDBFE' : '#E2E8F0' })
    .borderRadius(12)
    .onClick(() => {
      this.selectDiffFile(file.path);
    })
  }

  @Builder
  private actionChip(label: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor('#475569')
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(10)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.draft = label;
      })
  }

  @Builder
  private approvalCard(approval: CodexApprovalRequest) {
    Column() {
      Row() {
        this.panelTitle(approval.title, 'app-server 正在等待前端响应')

        Blank()
          .layoutWeight(1)

        this.chip('需要确认', '#FEF3C7', '#92400E')
      }
      .width('100%')

      Text(approval.detail)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor('#334155')
        .lineHeight(19)
        .margin({ top: 10 })

      Row() {
        Button('允许')
          .height(34)
          .fontSize(12)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => {
            void this.approvePending();
          })

        Button('拒绝')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(16)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            void this.declinePending();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 12 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor('#FFF7ED')
    .border({ width: 1, color: '#FED7AA' })
    .borderRadius(18)
    .margin({ top: 10 })
  }

  @Builder
  private leftPanel() {
    Column() {
    Scroll() {
    Column() {
      Row() {
        Column() {
          Text('ArkPilot')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text('项目侧边栏控制台')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Column() {
        this.panelTitle('导航', '通过项目侧边栏切换控制台子面板')

        List({ space: 0 }) {
          ForEach(this.sidebarItems, (item: SidebarItem) => {
            ListItem() {
              this.sidebarRow(item)
            }
          }, (item: SidebarItem) => item.view)
        }
        .width('100%')
        .width('100%')
        .scrollBar(BarState.Off)
        .margin({ top: 10 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .margin({ top: 12 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)

      Column() {
        this.panelTitle('会话概况', '')

        Column() {
          this.panelTitle('筛选目录', '选择目录以筛选下方会话列表')

          Text(this.directoryFilterText)
            .width('100%')
            .margin({ top: 10 })
            .fontSize(12)
            .fontColor('#111827')
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .copyOption(CopyOptions.LocalDevice)

          Row() {
            Button('选择目录')
              .layoutWeight(1)
              .height(34)
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .fontColor('#111827')
              .borderRadius(16)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                void this.pickWorkspaceDirectory();
              })

            Button('复制路径')
              .layoutWeight(1)
              .height(34)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .fontColor('#111827')
              .borderRadius(16)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                const targetPath: string = this.directoryFilter.length > 0 ? this.directoryFilter : this.workspaceRoot;
                if (targetPath.length === 0) {
                  return;
                }
                const clipData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, targetPath);
                const clip: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
                clip.setData(clipData).then(() => {
                  promptAction.showToast({ message: '路径已复制到剪贴板', duration: 2000 });
                }).catch((err: Error) => {
                  hilog.error(INDEX_DOMAIN, INDEX_TAG, 'Failed to copy path: %{public}s', JSON.stringify(err));
                });
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 10 })
        .backgroundColor('#F8FAFC')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(16)

        Row() {
          Button('新建会话')
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .backgroundColor('#111827')
            .fontColor('#FFFFFF')
            .borderRadius(16)
            .onClick(() => {
              AppStorage.setOrCreate('sessionsPageOpenCreateDialog', true);
              router.pushUrl({ url: 'pages/SessionsPage' });
            })

          Button('会话管理')
            .layoutWeight(1)
            .height(34)
            .margin({ left: 8 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .fontColor('#334155')
            .borderRadius(16)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => {
              router.pushUrl({ url: 'pages/SessionsPage' });
            })
        }
        .width('100%')
        .margin({ top: 12 })

        if (this.recentWorkspaces.length === 0) {
          Text('当前目录下暂无会话')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 12 })
        } else {
          Text('当前目录下的所有会话')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 12, bottom: 8 })

          List({ space: 6 }) {
            ForEach(this.recentWorkspaces, (item: WorkspaceItem) => {
              ListItem() {
                this.workspaceRow(item)
              }
            }, (item: WorkspaceItem) => `${item.id.toString()}:${item.title}`)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .margin({ top: 10 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)

    }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .layoutWeight(1)
    .width('100%')

    Button() {
      Row() {
        Text('⚙')
          .fontSize(14)
          .fontColor('#64748B')

        Text('Settings')
          .fontSize(12)
          .fontColor('#64748B')
          .margin({ left: 6 })
      }
    }
    .height(38)
    .width('100%')
    .margin({ top: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .border({ width: 1, color: '#E2E8F0' })
    .onClick(() => {
      router.pushUrl({ url: 'pages/SettingsPage' });
    })
    }
    .height('100%')
    .width(this.leftPanelWidth)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  @Builder
  private chatCenterView() {
    Column() {
      Row() {
        this.leftDrawerToggle()

        Blank()
          .width(6)

        Column() {
          Text(this.currentWorkspaceTitle)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')

          Text(this.currentWorkspaceDescription)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
          .layoutWeight(1)

        Row() {
          this.chip(this.currentModelLabel(), '#EEF4FF', '#1D4ED8')
          Blank()
            .width(6)
          this.chip(this.currentEffortLabel(), '#F8FAFC', '#64748B')
          Blank()
            .width(6)
          this.rightDrawerToggle()
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column() {
        Text(this.summaryTitle)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')

        Column() {
          ForEach(this.summaryPoints, (item: string) => {
            this.summaryBullet(item)
          }, (item: string) => item)
        }
        .width('100%')
        .margin({ top: 10 })

        Row() {
          Text(this.changedFiles)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.diffStat)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#16A34A')
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .margin({ top: 10 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E5E7EB' })
      .borderRadius(18)

      if (this.pendingApproval !== null) {
        this.approvalCard(this.pendingApproval!)
      }

      Scroll(this.messageScroller) {
        Column() {
          ForEach(this.messages, (item: ChatMessage) => {
            this.messageCard(item)
          }, (item: ChatMessage) => this.messageRenderKey(item))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 10 })
      .scrollBar(BarState.Off)

      Column() {
        Row() {
          this.selectorButton('推理', this.currentEffortLabel(), this.showEffortOptions, () => {
            this.showEffortOptions = !this.showEffortOptions;
          })
        }
        .width('100%')

        if (this.showEffortOptions) {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(this.effortOptions, (item: SelectorOption, index: number) => {
              this.optionChip(item, this.selectedEffortIndex === index, () => {
                this.selectedEffortIndex = index;
                this.showEffortOptions = false;
              })
            })
          }
          .width('100%')
          .margin({ top: 8 })
        }

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.quickActions, (item: string) => {
            this.actionChip(item)
          }, (item: string) => item)
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          TextInput({ text: this.draft, placeholder: '输入要发送给真实 ArkPilot 的指令...' })
            .layoutWeight(1)
            .height(40)
            .fontSize(12)
            .fontColor('#0F172A')
            .placeholderColor('#94A3B8')
            .backgroundColor('#FFFFFF')
            .borderRadius(19)
            .padding({ left: 12, right: 12 })
            .enterKeyType(EnterKeyType.Send)
            .onChange((value: string) => {
              this.draft = value;
            })
            .onSubmit(() => {
              this.sendMessage();
            })
            .onKeyEvent((event: KeyEvent) => {
              if (event.type === KeyType.Down && event.keyCode === 27 && this.isRunning) {
                this.stopTurn();
              }
            })

          Button() {
            Text(this.isRunning ? '■' : '发送')
              .fontSize(this.isRunning ? 14 : 12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .copyOption(CopyOptions.None)
          }
            .width(64)
            .height(36)
            .margin({ left: 8 })
            .backgroundColor('#111827')
            .borderRadius(18)
            .opacity(1)
            .onClick(() => {
              if (this.isRunning) {
                this.stopTurn();
              } else {
                this.sendMessage();
              }
            })
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          Text(this.connectionText)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')

          Text(this.workspaceRoot.trim().length > 0 ? this.workspaceRoot : '默认 cwd')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ left: 10 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .padding(12)
      .margin({ top: 10 })
      .backgroundColor('#F8FAFC')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private centerPanel() {
    Column() {
      if (this.recentWorkspaces.length === 0) {
        Row() {
          this.leftDrawerToggle()
          Blank()
            .layoutWeight(1)
          this.rightDrawerToggle()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column() {
          Text('当前目录下暂无会话')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontColor('#94A3B8')
          Text(this.directoryFilterText)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#CBD5E1')
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.chatCenterView()
      }
    }
    .height('100%')
    .layoutWeight(1)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  @Builder
  private chatContextPanel() {
    Column() {
      Row() {
        this.panelTitle('统一 diff', 'turn/diff/updated 会实时刷新这里')

        Blank()
          .layoutWeight(1)

        Text(this.diffFiles.length > 0 ? this.currentDiffFileStat() : this.diffStat)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#15803D')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#ECFDF3')
          .borderRadius(10)
      }
      .width('100%')

      Text(this.changedFiles)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .margin({ top: 8 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.diffFiles.length > 0) {
        Text('\u53d8\u66f4\u6587\u4ef6')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ top: 10 })

        List({ space: 6 }) {
          ForEach(this.diffFiles, (file: CodeDiffFile) => {
            ListItem() {
              this.diffFileRow(file)
            }
          }, (file: CodeDiffFile) => file.path)
        }
        .width('100%')
        .height(Math.min(150, this.diffFiles.length * 54))
        .margin({ top: 8 })
        .scrollBar(BarState.Off)

        Row() {
          Text('\u5f53\u524d')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')

          Text(this.currentDiffFilePath())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#334155')
            .layoutWeight(1)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.currentDiffFileStat())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#1D4ED8')
        }
        .width('100%')
        .margin({ top: 10 })
      }

      List({ space: 6 }) {
        ForEach(this.codeLines, (item: CodeDiffLine) => {
          ListItem() {
            this.diffRow(item)
          }
        }, (item: CodeDiffLine) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 10 })
      .scrollBar(BarState.Off)
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private rightPanel() {
    Column() {
      // 主内容区
      Column() {
        this.chatContextPanel()
      }
      .layoutWeight(1)
      .width('100%')

      // Token 用量卡片（底部）
      this.tokenUsageCard()
    }
    .height('100%')
    .width(this.rightPanelWidth)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  @Builder
  private splitterBar(isLeft: boolean) {
    Column() {
      Column()
        .width(2)
        .height('60%')
        .backgroundColor('#CBD5E1')
        .borderRadius(1)
    }
    .width(8)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F1F5F9')
    .borderRadius(4)
    .hitTestBehavior(HitTestMode.Block)
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionStart(() => {
          this.dragStartLeftW = this.leftPanelWidth;
          this.dragStartRightW = this.rightPanelWidth;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (isLeft) {
            const newLeft = this.dragStartLeftW + event.offsetX;
            if (newLeft >= this.leftDrawerMinWidth) {
              this.leftPanelWidth = newLeft;
            }
          } else {
            const newRight = this.dragStartRightW - event.offsetX;
            if (newRight >= this.rightDrawerMinWidth) {
              this.rightPanelWidth = newRight;
            }
          }
        })
    )
  }

  @Builder
  private leftDrawerToggle() {
    Button() {
      Stack() {
        Column()
          .width(16)
          .height(12)
          .borderRadius(3)
          .border({ width: 1.5, color: '#64748B' })
          .backgroundColor(this.showLeftDrawer ? '#EEF4FF' : '#FFFFFF')

        Column()
          .width(1.5)
          .height(8)
          .backgroundColor('#64748B')
          .position({ x: 4, y: 2 })
      }
      .width(16)
      .height(12)
    }
    .type(ButtonType.Normal)
    .width(32)
    .height(28)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E2E8F0' })
    .onClick(() => {
      this.toggleLeftDrawer();
    })
  }

  @Builder
  private rightDrawerToggle() {
    Button() {
      Stack() {
        Column()
          .width(16)
          .height(12)
          .borderRadius(3)
          .border({ width: 1.5, color: '#64748B' })
          .backgroundColor(this.showRightDrawer ? '#EEF4FF' : '#FFFFFF')

        Column()
          .width(1.5)
          .height(8)
          .backgroundColor('#64748B')
          .position({ x: 10.5, y: 2 })
      }
      .width(16)
      .height(12)
    }
    .type(ButtonType.Normal)
    .width(32)
    .height(28)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E2E8F0' })
    .onClick(() => {
      this.toggleRightDrawer();
    })
  }

  private formatTokenCount(count: number): string {
    if (count <= 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) return (count / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return (count / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
  }

  private get contextUsedTokens(): number {
    return this.tokenUsage?.total?.totalTokens ?? 0;
  }

  private get contextWindowTotal(): number {
    return this.tokenUsage?.modelContextWindow ?? 0;
  }

  private get contextUsedPercent(): number {
    if (this.contextWindowTotal <= 0) return 0;
    return (this.contextUsedTokens / this.contextWindowTotal) * 100;
  }

  private contextPercentColor(): ResourceColor {
    const pct = this.contextUsedPercent;
    if (pct > 90) return '#EF4444';
    if (pct > 70) return '#F59E0B';
    return '#3B82F6';
  }

  private tokenMiniText(): string {
    const total = this.tokenUsage?.total?.totalTokens ?? 0;
    const pct = this.contextWindowTotal > 0
      ? ` · ${this.contextUsedPercent.toFixed(0)}%`
      : '';
    return `总 ${this.formatTokenCount(total)}${pct}`;
  }

  @Builder tokenUsageCard() {
    Column() {
      // 箭头指示器
      Row() {
        Text(this.tokenCardExpanded ? '▼' : '▲')
          .fontSize(10)
          .fontColor('#94A3B8')
      }
      .width(40)
      .height(16)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.tokenCardExpanded ? '#FFFFFF' : '#F1F5F9')
      .borderRadius({ topLeft: 8, topRight: 8 })
      .border({ width: 1, color: '#E2E8F0' })
      .margin({ bottom: -1 })
      .onClick(() => {
        animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
          this.tokenCardExpanded = !this.tokenCardExpanded;
        });
      })

      // 卡片内容
      Column() {
        if (!this.tokenCardExpanded) {
          // 收起状态：只显示摘要
          Row() {
            Text(this.tokenMiniText())
              .fontSize(11)
              .fontColor('#64748B')
              .maxLines(1)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 8 })
        } else {
          // 展开状态：完整内容
          // 标题行
          Row() {
            Text('Token 用量')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1E293B')
            Blank()
            Text(this.providerName)
              .fontSize(11)
              .fontColor('#94A3B8')
          }
          .width('100%')

          // 上下文占用
          if (this.contextWindowTotal > 0) {
            Column() {
              Row() {
                Text(`${this.contextUsedPercent.toFixed(1)}%`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.contextPercentColor())
                Blank()
                Text(`${this.formatTokenCount(this.contextUsedTokens)} / ${this.formatTokenCount(this.contextWindowTotal)}`)
                  .fontSize(11)
                  .fontColor('#94A3B8')
              }
              .width('100%')
              Stack({ alignContent: Alignment.Start }) {
                Row().width('100%').height(6).backgroundColor('#E2E8F0').borderRadius(3)
                Row()
                  .width(`${Math.min(this.contextUsedPercent, 100)}%`)
                  .height(6)
                  .backgroundColor(this.contextPercentColor())
                  .borderRadius(3)
              }
              .width('100%')
              .height(6)
              .margin({ top: 4 })
            }
            .margin({ top: 8 })
          }

          // 标签页
          Row() {
            Text('当前轮')
              .fontSize(12)
              .fontColor(this.tokenTab === 0 ? '#3B82F6' : '#94A3B8')
              .fontWeight(this.tokenTab === 0 ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.tokenTab === 0 ? '#EFF6FF' : 'transparent')
              .onClick(() => { this.tokenTab = 0; })
            Text('趋势')
              .fontSize(12)
              .fontColor(this.tokenTab === 1 ? '#3B82F6' : '#94A3B8')
              .fontWeight(this.tokenTab === 1 ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.tokenTab === 1 ? '#EFF6FF' : 'transparent')
              .onClick(() => { this.tokenTab = 1; })
          }
          .margin({ top: 10 })
          .width('100%')

          // 当前轮 tab
          if (this.tokenTab === 0) {
            Column() {
              if (this.tokenUsage === null) {
                Text('等待数据...')
                  .fontSize(11)
                  .fontColor('#94A3B8')
                  .margin({ top: 8 })
              } else {
                // 堆叠条
                if (this.tokenUsage!.last.totalTokens <= 0) {
                  Row().width('100%').height(8).backgroundColor('#F1F5F9').borderRadius(4)
                } else {
                  Row() {
                    if (this.tokenUsage!.last.inputTokens > 0) {
                      Row()
                        .width(`${(this.tokenUsage!.last.inputTokens / this.tokenUsage!.last.totalTokens) * 100}%`)
                        .height(8)
                        .backgroundColor('#3B82F6')
                    }
                    if (this.tokenUsage!.last.cachedInputTokens > 0) {
                      Row()
                        .width(`${(this.tokenUsage!.last.cachedInputTokens / this.tokenUsage!.last.totalTokens) * 100}%`)
                        .height(8)
                        .backgroundColor('#94A3B8')
                    }
                    if (this.tokenUsage!.last.outputTokens > 0) {
                      Row()
                        .width(`${(this.tokenUsage!.last.outputTokens / this.tokenUsage!.last.totalTokens) * 100}%`)
                        .height(8)
                        .backgroundColor('#10B981')
                    }
                    if (this.tokenUsage!.last.reasoningOutputTokens > 0) {
                      Row()
                        .width(`${(this.tokenUsage!.last.reasoningOutputTokens / this.tokenUsage!.last.totalTokens) * 100}%`)
                        .height(8)
                        .backgroundColor('#8B5CF6')
                    }
                  }
                  .width('100%')
                  .height(8)
                  .borderRadius(4)
                  .clip(true)
                }
                // 细分数字
                Column() {
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#3B82F6')
                    Text('输入').fontSize(11).fontColor('#64748B').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.inputTokens)).fontSize(11).fontColor('#1E293B').fontWeight(FontWeight.Medium)
                  }.width('100%').margin({ top: 4 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#94A3B8')
                    Text('缓存').fontSize(11).fontColor('#64748B').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.cachedInputTokens)).fontSize(11).fontColor('#1E293B').fontWeight(FontWeight.Medium)
                  }.width('100%').margin({ top: 4 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#10B981')
                    Text('输出').fontSize(11).fontColor('#64748B').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.outputTokens)).fontSize(11).fontColor('#1E293B').fontWeight(FontWeight.Medium)
                  }.width('100%').margin({ top: 4 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#8B5CF6')
                    Text('推理').fontSize(11).fontColor('#64748B').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.reasoningOutputTokens)).fontSize(11).fontColor('#1E293B').fontWeight(FontWeight.Medium)
                  }.width('100%').margin({ top: 4 })
                }
                .margin({ top: 8 })
              }
            }
            .margin({ top: 8 })
            .width('100%')
          }

          // 趋势 tab
          if (this.tokenTab === 1) {
            Column() {
              if (this.tokenAggregate === null) {
                Text('加载中...')
                  .fontSize(11)
                  .fontColor('#94A3B8')
                  .margin({ top: 8 })
              } else {
                Row() {
                  // 今日
                  Column() {
                    Text(this.formatTokenCount(this.tokenAggregate!.today))
                      .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#1E293B')
                    Text('今日').fontSize(10).fontColor('#94A3B8').margin({ top: 2 })
                    Column() {
                      Column()
                        .width(20)
                        .height(this.tokenAggregate!.thisMonth > 0 ? `${Math.max((this.tokenAggregate!.today / this.tokenAggregate!.thisMonth) * 48, 2)}px` : '2px')
                        .backgroundColor('#3B82F6').borderRadius(3)
                    }.height(48).width(20).alignItems(HorizontalAlign.End).justifyContent(FlexAlign.End).margin({ top: 4 })
                  }.alignItems(HorizontalAlign.Center).layoutWeight(1)
                  // 本周
                  Column() {
                    Text(this.formatTokenCount(this.tokenAggregate!.thisWeek))
                      .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#1E293B')
                    Text('本周').fontSize(10).fontColor('#94A3B8').margin({ top: 2 })
                    Column() {
                      Column()
                        .width(20)
                        .height(this.tokenAggregate!.thisMonth > 0 ? `${Math.max((this.tokenAggregate!.thisWeek / this.tokenAggregate!.thisMonth) * 48, 2)}px` : '2px')
                        .backgroundColor('#3B82F6').borderRadius(3)
                    }.height(48).width(20).alignItems(HorizontalAlign.End).justifyContent(FlexAlign.End).margin({ top: 4 })
                  }.alignItems(HorizontalAlign.Center).layoutWeight(1)
                  // 本月
                  Column() {
                    Text(this.formatTokenCount(this.tokenAggregate!.thisMonth))
                      .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#1E293B')
                    Text('本月').fontSize(10).fontColor('#94A3B8').margin({ top: 2 })
                    Column() {
                      Column()
                        .width(20)
                        .height('48px')
                        .backgroundColor('#3B82F6').borderRadius(3)
                    }.height(48).width(20).alignItems(HorizontalAlign.End).justifyContent(FlexAlign.End).margin({ top: 4 })
                  }.alignItems(HorizontalAlign.Center).layoutWeight(1)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
              }
            }
            .margin({ top: 8 })
            .width('100%')
          }
        }
      }
      .padding(this.tokenCardExpanded ? 12 : 0)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .border({ width: 1, color: '#E2E8F0' })
      .shadow(this.tokenCardExpanded ? { radius: 8, color: '#0D000000', offsetY: 2 } : undefined)
      .animation({ duration: 250, curve: Curve.EaseInOut })
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#EEF2F7')

      Row() {
        if (this.showLeftDrawer) {
          Column() {
            this.leftPanel()
          }
          .height('100%')
          .transition(TransitionEffect.move(TransitionEdge.START).animation({ duration: 300, curve: Curve.EaseOut }))

          this.splitterBar(true)
        }

        this.centerPanel()

        if (this.showRightDrawer) {
          this.splitterBar(false)

          Column() {
            this.rightPanel()
          }
          .height('100%')
          .transition(TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .height('100%')
      .padding(10)
    }
    .width('100%')
    .height('100%')
  }
}
