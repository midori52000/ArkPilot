import {
  codexBackend,
  CodexApprovalRequest,
  CodexBackendSnapshot,
  CodexConnectionState,
  CodexDiffLine,
  CodexRequestUserInput,
  CodexRequestUserInputOption,
  CodexRequestUserInputQuestion,
  CodexTurnRequest,
  CodexTurnResult
} from '../backend/CodexBackend';
import {
  CollaborationModeOption,
  CodexProviderConfig,
  WorkspaceAccessStatus,
  checkWorkspaceAccess,
  getEmbeddedCodexHostStatus,
  getEmbeddedCodexProviderCatalog,
  getEmbeddedCodexProviderConfig,
  saveEmbeddedCodexProviderConfig
} from '../backend/CodexNative';
import { providerCatalogService } from '../backend/ProviderCatalogService';
import { SessionSummary, WorkspaceAccessKind, WorkspacePermissionState, TurnTokenUsage, TokenUsageAggregate, TokenUsageBreakdown, WorkspaceItem, WorkspaceBindingDraft, WorkspaceDirectorySelection, SelectorOption, DailyTokenSnapshot, ProjectRecord } from '../backend/ConsoleModels';
import { StoredWorkspaceItem, workspaceBindingStore } from '../backend/WorkspaceBindingStore';
import { projectStore } from '../backend/ProjectStore';
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
  private backendSubscriptionId: number = -1;
  private reconnectTimerId: number = -1;
  private reconnectAttemptCount: number = 0;
  private readonly workspaceRoots: Map<number, string> = new Map();
  private readonly workspaceIds: Map<number, string> = new Map();
  private readonly workspaceUris: Map<number, string> = new Map();
  private readonly collaborationModeByWorkspaceId: Map<string, string> = new Map();
  private readonly requestUserInputDrafts: Map<string, string> = new Map();
  private readonly messageScroller: Scroller = new Scroller();

  @State private workspaces: WorkspaceItem[] = [];
  @State private activeWorkspaceId: number = 1;
  @State private activeWorkspaceBindingId: string = 'session:1';
  @State private currentWorkspaceTitle: string = '新会话 1';
  @State private currentWorkspaceDescription: string = '等待通过 app-server 创建真实会话';
  @State private activeWorkspacePermissionState: WorkspacePermissionState = 'unavailable';
  @State private activeWorkspaceAccessKind: WorkspaceAccessKind = 'unknown';
  @State private workspaceStatusText: string = 'å°šæœªæ£€æµ‹å·¥ä½œåŒºæƒé™';
  @State private selectedEffortIndex: number = 0;
  @State private showEffortOptions: boolean = false;
  @State private collaborationModes: CollaborationModeOption[] = [];
  @State private selectedCollaborationModeName: string = 'default';
  @State private collaborationModeVersion: number = 0;
  @State private showCollaborationModeOptions: boolean = false;
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
  private leftScrollOffset: number = 0;
  private leftScrollController: Scroller = new Scroller();
  private readonly leftDrawerMinWidth: number = 100;
  private readonly rightDrawerMinWidth: number = 120;
  private dragStartLeftW: number = 0;
  private dragStartRightW: number = 0;
  private leftHiding: boolean = false;
  private rightHiding: boolean = false;
  @State private recentWorkspaces: WorkspaceItem[] = [];
  @State private directoryFilter: string = '';
  @State private directoryFilterText: string = '使用默认工作区';
  @State private draft: string = '检查当前工作目录，并说明需要我批准的操作。';
  private savedDraft: string = '';
  @State private pendingApproval: CodexApprovalRequest | null = null;
  @State private pendingRequestUserInput: CodexRequestUserInput | null = null;
  @State private requestUserInputVersion: number = 0;
  @State private expandedIntermediateMessageIds: string[] = [];
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
  @State private tokenCardHeight: number = 280;
  @State private tokenCardDragStartY: number = 0;
  @State private tokenCardDragStartH: number = 0;
  @State private tokenTab: number = 0;
  @State private tokenTrendRange: number = 0;
  @State private compacting: boolean = false;
  @State private compactError: string = '';
  @State private projects: ProjectRecord[] = [];
  @State private showCreateProjectDialog: boolean = false;
  @State private newProjectName: string = '';
  @State private newProjectPath: string = '';
  @State private renamingProjectId: string = '';
  @State private renameProjectText: string = '';
  @State private showNewSessionDialog: boolean = false;
  @State private newSessionProjectId: string = '';
  @State private newSessionName: string = '';
  @State private renamingSessionId: string = '';
  @State private renameSessionText: string = '';
  @State private hoveredProjectId: string = '';
  @State private hoveredSessionId: string = '';
  @State private showProjectMenuId: string = '';
  @State private showSessionMenuId: string = '';
  @State private showRenameSessionDialog: boolean = false;
  @State private renameSessionDialogText: string = '';
  @State private renameSessionDialogId: string = '';
  @State private showDeleteSessionDialog: boolean = false;
  @State private deleteSessionDialogId: string = '';
  @State private deleteSessionDialogTitle: string = '';
  @State private showRenameProjectDialog: boolean = false;
  @State private renameProjectDialogText: string = '';
  @State private renameProjectDialogId: string = '';
  @State private showDeleteProjectDialog: boolean = false;
  @State private deleteProjectDialogId: string = '';
  @State private deleteProjectDialogName: string = '';


  aboutToAppear(): void {
    this.backendSubscriptionId = codexBackend.subscribe((snapshot: CodexBackendSnapshot) => {
      this.applyBackendSnapshot(snapshot);
    });
    this.applyBackendSnapshot(codexBackend.snapshot());
    this.applyEmbeddedHostStatus();
    this.loadProviderConfig();
    this.restoreWorkspaceBindings();
    this.loadProjects();

    void this.restoreSessionsFromBackend();

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
    hilog.info(0x0001, 'ArkPilot', `applyBackendSnapshot: conn=${snapshot.connectionState} modes=${snapshot.collaborationModes.length} selected=${this.selectedCollaborationModeName}`);
    this.serverUrl = snapshot.serverUrl;
    this.connectionState = snapshot.connectionState;
    this.connectionText = snapshot.connectionText;
    this.pendingApproval = snapshot.pendingApproval;
    const previousRequestId: string = this.pendingRequestUserInput !== null ? `${this.pendingRequestUserInput.requestId}` : '';
    const nextRequestId: string = snapshot.pendingRequestUserInput !== null ? `${snapshot.pendingRequestUserInput.requestId}` : '';
    this.pendingRequestUserInput = snapshot.pendingRequestUserInput;
    this.collaborationModes = snapshot.collaborationModes;
    if (previousRequestId !== nextRequestId) {
      this.requestUserInputDrafts.clear();
      this.requestUserInputVersion += 1;
    }
    this.syncSelectedCollaborationMode();
    if (snapshot.tokenUsage !== null && snapshot.tokenUsage !== undefined) {
      if (this.compacting && this.tokenUsage !== null && this.tokenUsage !== undefined) {
        const oldTotal = this.tokenUsage.total.totalTokens;
        const newTotal = snapshot.tokenUsage.total.totalTokens;
        if (oldTotal !== newTotal) {
          this.compacting = false;
          const saved = oldTotal - newTotal;
          if (saved > 0) {
            promptAction.showToast({ message: `压缩完成，释放 ${this.formatTokenCount(saved)} tokens`, duration: 3000 });
          } else {
            promptAction.showToast({ message: '压缩完成', duration: 2000 });
          }
        }
      }
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
      if (this.workspaces.length === 0) {
        this.activeWorkspaceId = 0;
        this.workspaceRoot = '';
        this.workspaceDraftText = '';
        this.currentWorkspaceTitle = '';
        this.currentWorkspaceDescription = '';
      }
      this.syncRecentWorkspaces();
      this.syncWorkspaceSelectionText();
      this.refreshWorkspaceBindingState();
      this.syncCurrentWorkspaceState();
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
    const newProjects: ProjectRecord[] = [];
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

      // Assign project by matching session root to project path
      const sessionRoot: string = nextRoot.trim();
      if (sessionRoot.length > 0) {
        let matchedProject: ProjectRecord | undefined = undefined;
        for (let pi: number = 0; pi < this.projects.length; pi += 1) {
          if (this.projects[pi].path.trim() === sessionRoot) {
            matchedProject = this.projects[pi];
            break;
          }
        }
        if (matchedProject !== undefined) {
          workspace.projectId = matchedProject.id;
        } else if (!projectStore.isDeletedPath(sessionRoot)) {
          const projId: string = `proj_${Date.now().toString()}_${index.toString()}`;
          const projName: string = sessionRoot.substring(sessionRoot.lastIndexOf('/') + 1);
          const newProj: ProjectRecord = new ProjectRecord(projId, projName.length > 0 ? projName : sessionRoot, sessionRoot, true);
          newProjects.push(newProj);
          workspace.projectId = projId;
        }
      }

      if (summary.sessionId === preferredThreadId || (nextActiveWorkspaceId === 0 && summary.sessionId === this.activeWorkspaceBindingId)) {
        nextActiveWorkspaceId = workspace.id;
      }
    }

    // Preserve manually created workspaces that have local session IDs
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const ws: WorkspaceItem = this.workspaces[index];
      if (!this.isRemoteThreadId(ws.workspaceId) && !usedIds.has(ws.id)) {
        usedIds.add(ws.id);
        nextWorkspaces.push(ws);
        nextWorkspaceIds.set(ws.id, ws.workspaceId);
        const preservedRoot: string = this.workspaceRoots.get(ws.id) ?? '';
        nextWorkspaceRoots.set(ws.id, preservedRoot);
        nextWorkspaceUris.set(ws.id, this.workspaceUris.get(ws.id) ?? '');
      }
    }

    if (nextActiveWorkspaceId === 0) {
      const matched: WorkspaceItem | undefined = nextWorkspaces.find((item: WorkspaceItem) => item.id === this.activeWorkspaceId);
      nextActiveWorkspaceId = matched?.id ?? nextWorkspaces[0].id;
    }

    this.workspaces = [...nextWorkspaces];
    if (newProjects.length > 0) {
      this.projects = [...this.projects, ...newProjects];
    }
    this.saveProjects();
    this.syncRecentWorkspaces();
    this.workspaceIds.clear();
    this.workspaceRoots.clear();
    this.workspaceUris.clear();
    nextWorkspaceIds.forEach((value: string, key: number) => this.workspaceIds.set(key, value));
    nextWorkspaceRoots.forEach((value: string, key: number) => this.workspaceRoots.set(key, value));
    nextWorkspaceUris.forEach((value: string, key: number) => this.workspaceUris.set(key, value));
    this.activeWorkspaceId = nextActiveWorkspaceId;
    this.syncSelectedCollaborationMode();
    this.workspaceRoot = this.workspaceRoots.get(this.activeWorkspaceId) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
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
        item.workspaceUri,
        item.projectId
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
      const workspace: WorkspaceItem = new WorkspaceItem(restored.id, restored.title, restored.description, restored.workspaceId, restored.projectId);
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
    this.syncSelectedCollaborationMode();
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
      item.projectId = workspace.projectId;
      items.push(item);
    }
    workspaceBindingStore.saveBindings(this.activeWorkspaceId, items);
  }

  // ── Project management ──────────────────────────────────────────

  private loadProjects(): void {
    this.projects = projectStore.load();
  }

  private saveProjects(): void {
    projectStore.save(this.projects);
  }

  private sessionsForProject(projectId: string): WorkspaceItem[] {
    const result: WorkspaceItem[] = [];
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      if (this.workspaces[i].projectId === projectId) {
        result.push(this.workspaces[i]);
      }
    }
    return result;
  }

  private async createProject(): Promise<void> {
    const name: string = this.newProjectName.trim();
    const path: string = this.newProjectPath.trim();
    if (name.length === 0 || path.length === 0) {
      promptAction.showToast({ message: '请输入项目名称并选择目录', duration: 2000 });
      return;
    }
    const id: string = `proj_${Date.now().toString()}`;
    const next: ProjectRecord[] = [...this.projects, new ProjectRecord(id, name, path, true)];
    this.projects = next;
    this.saveProjects();
    this.showCreateProjectDialog = false;
    this.newProjectName = '';
    this.newProjectPath = '';
    promptAction.showToast({ message: `项目"${name}"已创建`, duration: 2000 });
  }

  private startRenameProject(projectId: string): void {
    const proj: ProjectRecord | undefined = this.projects.find((p: ProjectRecord) => p.id === projectId);
    if (proj !== undefined) {
      this.renamingProjectId = projectId;
      this.renameProjectText = proj.name;
    }
  }

  private confirmRenameProject(): void {
    const name: string = this.renameProjectText.trim();
    if (name.length === 0 || this.renamingProjectId.length === 0) {
      return;
    }
    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      const p: ProjectRecord = this.projects[i];
      if (p.id === this.renamingProjectId) {
        next.push(new ProjectRecord(p.id, name, p.path, p.expanded));
      } else {
        next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded));
      }
    }
    this.projects = next;
    this.saveProjects();
    this.renamingProjectId = '';
    this.renameProjectText = '';
  }

  private cancelRenameProject(): void {
    this.renamingProjectId = '';
    this.renameProjectText = '';
  }

  private toggleProjectExpanded(projectId: string): void {
    const savedOffset: number = this.leftScrollController.currentOffset().yOffset;
    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      const p: ProjectRecord = this.projects[i];
      if (p.id === projectId) {
        next.push(new ProjectRecord(p.id, p.name, p.path, !p.expanded));
      } else {
        next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded));
      }
    }
    this.projects = next;
    this.saveProjects();
    setTimeout(() => {
      this.leftScrollController.scrollTo({ yOffset: savedOffset, xOffset: 0 });
    }, 50);
  }

  private openNewSessionDialog(projectId: string): void {
    this.newSessionProjectId = projectId;
    this.newSessionName = '';
    this.showNewSessionDialog = true;
  }

  private async confirmCreateSession(): Promise<void> {
    const name: string = this.newSessionName.trim();
    if (name.length === 0 || this.newSessionProjectId.length === 0) {
      promptAction.showToast({ message: '请输入会话名称', duration: 2000 });
      return;
    }
    const proj: ProjectRecord | undefined = this.projects.find((p: ProjectRecord) => p.id === this.newSessionProjectId);
    if (proj === undefined) {
      return;
    }
    const nextId: number = this.nextWorkspaceId();
    const workspace: WorkspaceItem = new WorkspaceItem(nextId, name, '', `session:${nextId.toString()}`, proj.id);
    this.workspaces.push(workspace);
    this.workspaceRoots.set(nextId, proj.path);
    this.workspaceIds.set(nextId, `session:${nextId.toString()}`);
    this.showNewSessionDialog = false;
    this.newSessionProjectId = '';
    this.newSessionName = '';
    this.syncRecentWorkspaces();
    this.persistWorkspaceBindings();
    await this.selectWorkspace(workspace);
  }

  private startRenameSession(sessionId: string): void {
    const ws: WorkspaceItem | undefined = this.workspaces.find((w: WorkspaceItem) => this.ensureWorkspaceBinding(w) === sessionId);
    if (ws !== undefined) {
      this.renamingSessionId = sessionId;
      this.renameSessionText = ws.title;
    }
  }

  private confirmRenameSession(): void {
    const name: string = this.renameSessionText.trim();
    if (name.length === 0 || this.renamingSessionId.length === 0) {
      return;
    }
    const next: WorkspaceItem[] = [];
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      const w: WorkspaceItem = this.workspaces[i];
      if (this.ensureWorkspaceBinding(w) === this.renamingSessionId) {
        next.push(new WorkspaceItem(w.id, name, w.description, w.workspaceId, w.projectId));
      } else {
        next.push(new WorkspaceItem(w.id, w.title, w.description, w.workspaceId, w.projectId));
      }
    }
    this.workspaces = next;
    this.syncRecentWorkspaces();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
    void codexBackend.renameSession(this.renamingSessionId, name);
    this.renamingSessionId = '';
    this.renameSessionText = '';
  }

  private cancelRenameSession(): void {
    this.renamingSessionId = '';
    this.renameSessionText = '';
  }

  private async deleteSession(sessionId: string): Promise<void> {
    let targetIndex: number = -1;
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      if (this.ensureWorkspaceBinding(this.workspaces[i]) === sessionId) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      return;
    }
    // Archive backend session data
    try {
      await codexBackend.archiveSession(sessionId);
    } catch (_err) {
      // ignore archive errors
    }
    this.workspaces.splice(targetIndex, 1);
    if (this.workspaces.length === 0) {
      this.activeWorkspaceId = 0;
    } else if (targetIndex <= this.workspaces.length) {
      const newIndex: number = targetIndex < this.workspaces.length ? targetIndex : this.workspaces.length - 1;
      await this.selectWorkspace(this.workspaces[newIndex]);
    }
    this.syncRecentWorkspaces();
    this.persistWorkspaceBindings();
  }

  private async deleteProject(projectId: string): Promise<void> {
    let targetIndex: number = -1;
    for (let i: number = 0; i < this.projects.length; i += 1) {
      if (this.projects[i].id === projectId) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      return;
    }
    projectStore.addDeletedPath(this.projects[targetIndex].path);

    // Archive all backend sessions belonging to this project
    for (let i: number = this.workspaces.length - 1; i >= 0; i -= 1) {
      if (this.workspaces[i].projectId === projectId) {
        const sessionId: string = this.ensureWorkspaceBinding(this.workspaces[i]);
        try {
          await codexBackend.archiveSession(sessionId);
        } catch (_err) {
          // ignore archive errors
        }
      }
    }

    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      if (this.projects[i].id !== projectId) {
        next.push(this.projects[i]);
      }
    }
    this.projects = next;
    this.saveProjects();
    for (let i: number = this.workspaces.length - 1; i >= 0; i -= 1) {
      if (this.workspaces[i].projectId === projectId) {
        this.workspaces.splice(i, 1);
      }
    }
    this.syncRecentWorkspaces();
    this.persistWorkspaceBindings();
  }

  private relativeTime(updatedAt: string): string {
    const parsed: number = Date.parse(updatedAt);
    if (isNaN(parsed)) {
      return '';
    }
    const diffMs: number = Date.now() - parsed;
    if (diffMs < 0) {
      return '刚刚';
    }
    const minutes: number = Math.floor(diffMs / 60000);
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes < 60) {
      return `${minutes.toString()} 分`;
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours.toString()} 时`;
    }
    const days: number = Math.floor(hours / 24);
    return `${days.toString()} 天`;
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

  private async pickWorkspaceDirectoryForProject(): Promise<void> {
    try {
      const selection: WorkspaceDirectorySelection | null = await this.pickDirectorySelection();
      if (selection !== null) {
        this.newProjectPath = selection.rootPath;
      }
    } catch (err) {
      promptAction.showToast({ message: `选择目录失败: ${this.describeError(err)}`, duration: 3000 });
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
    return this.currentModelValue();
  }

  private currentModelValue(): string {
    const mode: CollaborationModeOption | null = this.selectedCollaborationMode();
    const modeModel: string = mode?.model?.trim() ?? '';
    if (modeModel.length > 0) {
      return modeModel;
    }
    const model: string = this.manualModel.trim();
    if (model.length === 0) {
      return 'default';
    }
    return model;
  }

  private currentEffortLabel(): string {
    const currentValue: string = this.currentEffortValue();
    const matched: SelectorOption | undefined = this.effortOptions.find((item: SelectorOption) => item.value === currentValue);
    return matched?.label ?? currentValue;
  }

  private currentEffortValue(): string {
    const mode: CollaborationModeOption | null = this.selectedCollaborationMode();
    const modeEffort: string | null | undefined = mode?.reasoningEffort;
    // If the collaboration mode explicitly sets an effort (non-null string), use it.
    if (typeof modeEffort === 'string' && modeEffort.trim().length > 0) {
      return modeEffort.trim();
    }
    // Otherwise fall back to the user-selected effort from the UI picker.
    return this.effortOptions[this.selectedEffortIndex].value;
  }

  private collaborationModeKey(): string {
    return this.activeWorkspaceBindingId;
  }

  private syncSelectedCollaborationMode(): void {
    if (this.collaborationModes.length === 0) {
      hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: modes empty, resetting to default`);
      this.selectedCollaborationModeName = 'default';
      return;
    }
    const modeKey: string = this.collaborationModeKey();
    const mappedName: string | undefined = this.collaborationModeByWorkspaceId.get(modeKey);
    const currentName: string = mappedName ?? this.selectedCollaborationModeName;
    hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: key=${modeKey} mappedName=${mappedName} currentName=${currentName} modes=${this.collaborationModes.map((m: CollaborationModeOption) => m.name).join(',')}`);
    const matched: CollaborationModeOption | undefined = this.collaborationModes.find((item: CollaborationModeOption) => item.name === currentName);
    if (matched !== undefined) {
      hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: matched=${matched.name}`);
      this.selectedCollaborationModeName = matched.name;
      this.collaborationModeByWorkspaceId.set(modeKey, matched.name);
      this.collaborationModeVersion += 1;
      return;
    }
    const defaultMode: CollaborationModeOption | undefined = this.collaborationModes.find((item: CollaborationModeOption) => item.mode === 'default');
    const fallback: CollaborationModeOption = defaultMode ?? this.collaborationModes[0];
    hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: fallback=${fallback.name}`);
    this.selectedCollaborationModeName = fallback.name;
    this.collaborationModeByWorkspaceId.set(modeKey, fallback.name);
    this.collaborationModeVersion += 1;
  }

  private selectedCollaborationMode(): CollaborationModeOption | null {
    const matched: CollaborationModeOption | undefined = this.collaborationModes.find((item: CollaborationModeOption) => item.name === this.selectedCollaborationModeName);
    if (this.selectedCollaborationModeName !== 'default') {
      hilog.info(0x0001, 'ArkPilot', `selectedCollaborationMode: searching=${this.selectedCollaborationModeName} found=${matched !== undefined} modes=[${this.collaborationModes.map((m: CollaborationModeOption) => `"${m.name}"`).join(',')}]`);
    }
    return matched ?? null;
  }

  private currentCollaborationModeLabel(): string {
    this.collaborationModeVersion; // touch to register as dependency
    const mode: CollaborationModeOption | null = this.selectedCollaborationMode();
    const label: string = mode !== null ? mode.name : 'Default';
    hilog.info(0x0001, 'ArkPilot', `currentCollaborationModeLabel: selected=${this.selectedCollaborationModeName} modes=${this.collaborationModes.length} label=${label}`);
    return label;
  }

  private chooseCollaborationMode(mode: CollaborationModeOption): void {
    hilog.info(0x0001, 'ArkPilot', `chooseCollaborationMode: name=${mode.name} mode=${mode.mode} key=${this.collaborationModeKey()}`);
    this.selectedCollaborationModeName = mode.name;
    this.collaborationModeByWorkspaceId.set(this.collaborationModeKey(), mode.name);
    this.showCollaborationModeOptions = false;
    this.collaborationModeVersion += 1;
    hilog.info(0x0001, 'ArkPilot', `chooseCollaborationMode done: selectedCollaborationModeName=${this.selectedCollaborationModeName} version=${this.collaborationModeVersion}`);
  }

  private visibleMessages(): ChatMessage[] {
    if (this.pendingRequestUserInput === null) {
      return this.messages;
    }
    const request: CodexRequestUserInput = this.pendingRequestUserInput;
    const promptMessage = new ChatMessage(
      `request-user-input:${request.requestId}`,
      'ArkPilot',
      'plan',
      request.detail.trim().length > 0 ? request.detail : request.title,
      '刚刚',
      'plan'
    );
    return [...this.messages, promptMessage];
  }

  private requestUserInputAnswer(questionId: string): string {
    this.requestUserInputVersion;
    return this.requestUserInputDrafts.get(questionId) ?? '';
  }

  private setRequestUserInputAnswer(questionId: string, value: string): void {
    this.requestUserInputDrafts.set(questionId, value);
    this.requestUserInputVersion += 1;
  }

  private async submitRequestUserInput(): Promise<void> {
    const request: CodexRequestUserInput | null = this.pendingRequestUserInput;
    if (request === null) {
      return;
    }
    const answers: Record<string, string[]> = {};
    for (let index: number = 0; index < request.questions.length; index += 1) {
      const question = request.questions[index];
      const value: string = this.requestUserInputAnswer(question.id).trim();
      if (value.length === 0) {
        this.summaryTitle = '需要补充信息';
        this.summaryPoints = [`请先回答“${question.header}”再继续。`];
        return;
      }
      answers[question.id] = [value];
    }
    await codexBackend.submitPendingUserInput(answers);
    this.requestUserInputDrafts.clear();
    this.requestUserInputVersion += 1;
  }

  private async declineRequestUserInput(): Promise<void> {
    await codexBackend.declinePendingUserInput();
    this.requestUserInputDrafts.clear();
    this.requestUserInputVersion += 1;
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
          this.selectedCollaborationMode(),
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
      if (this.compacting && this.tokenUsage !== null && this.tokenUsage !== undefined) {
        const oldTotal = this.tokenUsage.total.totalTokens;
        const newTotal = result.tokenUsage.total.totalTokens;
        if (oldTotal !== newTotal) {
          this.compacting = false;
          const saved = oldTotal - newTotal;
          if (saved > 0) {
            promptAction.showToast({ message: `压缩完成，释放 ${this.formatTokenCount(saved)} tokens`, duration: 3000 });
          } else {
            promptAction.showToast({ message: '压缩完成', duration: 2000 });
          }
        }
      }
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
    this.syncSelectedCollaborationMode();
    this.workspaceRoot = this.workspaceRoots.get(item.id) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.directoryFilter = this.workspaceRoot;
    this.directoryFilterText = this.workspaceRoot.length > 0 ? this.workspaceRoot : '使用默认工作区';
    this.syncRecentWorkspaces();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.draft = `继续处理”${item.title}”，重点关注当前工作目录。`;
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
      return '#fffefbc7';
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
        return '#FAFAFA';
      case 'system':
        return '#F4F4F5';
      case 'reasoning':
        return '#FFFBEB';
      case 'command':
        return '#F0FDF4';
      case 'tool':
        return '#EFF6FF';
      case 'file':
        return '#FAF5FF';
      case 'search':
        return '#ECFDF5';
      case 'plan':
        return '#FFF7ED';
      case 'image':
        return '#FDF2F8';
      case 'hook':
        return '#FEF3C7';
      case 'review':
        return '#FEF9C3';
      case 'user':
        return '#E8F0FE';
      default:
        return '#F5F3FF';
    }
  }

  private authorColor(role: string): string {
    switch (role) {
      case 'assistant':
      case 'agent':
        return '#3B82F6';
      case 'system':
        return '#71717A';
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
        return '#2563EB';
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
      .borderRadius(6)
  }

  @Builder
  private panelTitle(title: string, subtitle: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#18181B')

      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#A1A1AA')
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
        .fontColor('#71717A')

      Text(value)
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#18181B')
        .margin({ left: 6 })

      Text('▾')
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .margin({ left: 6 })
    }
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(active ? '#F4F4F5' : '#FAFAFA')
    .border({ width: 0.5, color: active ? '#D4D4D8' : '#E4E4E7' })
    .borderRadius(8)
    .onClick(() => {
      onPress();
    })
  }

  @Builder
  private optionChip(option: SelectorOption, selected: boolean, onPress: () => void) {
    Text(option.label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor(selected ? '#18181B' : '#71717A')
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(selected ? '#E4E4E7' : '#FAFAFA')
      .borderRadius(6)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        onPress();
      })
  }

  @Builder
  private projectGroup(proj: ProjectRecord) {
      Column() {
        // Project header row
        Row() {
          Text(proj.expanded ? '▾' : '▸')
            .fontSize(11)
            .fontColor('#71717A')
            .width(16)

          Stack({ alignContent: Alignment.TopStart }) {
            Column()
              .width(14)
              .height(10)
              .border({ width: 1, color: '#A1A1AA' })
              .borderRadius({ bottomLeft: 2, bottomRight: 2, topLeft: 0, topRight: 2 })
            Column()
              .width(7)
              .height(3)
              .border({ width: 1, color: '#A1A1AA' })
              .borderRadius({ topLeft: 2, topRight: 2 })
              .backgroundColor('#FAFAFA')
              .position({ x: 0, y: -1 })
          }
          .width(14)
          .height(12)
          .margin({ right: 6 })

          Text(proj.name)
            .copyOption(CopyOptions.None)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // Context menu button (hover-visible)
          Text('···')
            .fontSize(16)
            .fontColor('#52525B')
            .padding({ left: 6, right: 6, top: 0, bottom: 0 })
            .height(20)
            .visibility(this.hoveredProjectId === proj.id ? Visibility.Visible : Visibility.Hidden)
            .bindContextMenu(!!this.showProjectMenuId, this.projectContextMenuBuilder(proj), { placement: Placement.TopRight })
            .onClick(() => {
              this.showProjectMenuId = this.showProjectMenuId === proj.id ? '' : proj.id;
            })

          // New session button (plus)
          Text('+')
            .fontSize(18)
            .fontColor('#71717A')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .onClick(() => {
              this.openNewSessionDialog(proj.id);
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(6)
        .backgroundColor(this.hoveredProjectId === proj.id ? '#F4F4F5' : 'transparent')
        .onHover((isHover: boolean) => {
          if (this.showProjectMenuId.length === 0) {
            this.hoveredProjectId = isHover ? proj.id : '';
          }
        })
        .onClick(() => {
          this.toggleProjectExpanded(proj.id);
        })
        .bindContextMenu(this.projectContextMenuBuilder(proj), ResponseType.RightClick)

        // Inline rename input
        if (this.renamingProjectId === proj.id) {
          Row() {
            TextInput({ text: this.renameProjectText })
              .layoutWeight(1)
              .height(28)
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .border({ width: 0.5, color: '#D4D4D8' })
              .borderRadius(6)
              .padding({ left: 8, right: 8 })
              .onChange((value: string) => {
                this.renameProjectText = value;
              })

            Text('✓')
              .fontSize(14)
              .fontColor('#16A34A')
              .padding({ left: 8 })
              .onClick(() => {
                this.confirmRenameProject();
              })

            Text('✕')
              .fontSize(14)
              .fontColor('#DC2626')
              .padding({ left: 4 })
              .onClick(() => {
                this.cancelRenameProject();
              })
          }
          .width('100%')
          .padding({ left: 24, right: 8, bottom: 6 })
        }

        // Sessions under this project
        if (proj.expanded) {
          Column() {
            if (this.sessionsForProject(proj.id).length === 0) {
              Text('暂无会话')
                .fontSize(10)
                .fontColor('#D4D4D8')
                .padding({ left: 24, top: 4, bottom: 4 })
            } else {
              ForEach(this.sessionsForProject(proj.id), (session: WorkspaceItem) => {
                this.sessionItem(session)
              }, (session: WorkspaceItem) => `${session.id.toString()}:${session.title}`)
            }
          }
          .width('100%')
          .padding({ left: 16 })
        }
      }
      .width('100%')
      .margin({ bottom: 4 })
  }

  @Builder
  private projectContextMenuBuilder(proj: ProjectRecord) {
    Menu() {
      MenuItem({ content: '重命名项目' })
        .onClick(() => {
          this.renameProjectDialogId = proj.id;
          this.renameProjectDialogText = proj.name;
          this.showRenameProjectDialog = true;
        })

      MenuItem({ content: '删除项目' })
        .onClick(() => {
          this.deleteProjectDialogId = proj.id;
          this.deleteProjectDialogName = proj.name;
          this.showDeleteProjectDialog = true;
        })

      MenuItem({ content: '复制路径' })
        .onClick(() => {
          let targetPath: string = '';
          for (let i: number = 0; i < this.projects.length; i += 1) {
            if (this.projects[i].id === proj.id) {
              targetPath = this.projects[i].path;
              break;
            }
          }
          if (targetPath.length > 0) {
            try {
              const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, targetPath);
              const systemPasteboard = pasteboard.getSystemPasteboard();
              void systemPasteboard.setData(pasteData);
              promptAction.showToast({ message: '路径已复制', duration: 2000 });
            } catch (_err) {
              promptAction.showToast({ message: '复制失败', duration: 2000 });
            }
          }
        })
    }
  }

  @Builder
  private sessionItem(item: WorkspaceItem) {
      Column() {
        if (this.renamingSessionId === this.ensureWorkspaceBinding(item)) {
          // Inline rename mode
          Row() {
            TextInput({ text: this.renameSessionText })
              .layoutWeight(1)
              .height(24)
              .fontSize(11)
              .backgroundColor('#FFFFFF')
              .border({ width: 0.5, color: '#D4D4D8' })
              .borderRadius(4)
              .padding({ left: 6, right: 6 })
              .onChange((value: string) => {
                this.renameSessionText = value;
              })

            Text('✓')
              .fontSize(12)
              .fontColor('#16A34A')
              .padding({ left: 6 })
              .onClick(() => {
                this.confirmRenameSession();
              })

            Text('✕')
              .fontSize(12)
              .fontColor('#DC2626')
              .padding({ left: 4 })
              .onClick(() => {
                this.cancelRenameSession();
              })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        } else {
          // Normal session display
          Row() {
            Text(item.title)
              .copyOption(CopyOptions.None)
              .fontSize(11)
              .fontWeight(this.isWorkspaceActive(item) ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.isWorkspaceActive(item) ? '#18181B' : '#52525B')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.relativeTime(this.findSessionUpdatedAt(item)))
              .fontSize(9)
              .fontColor('#A1A1AA')
              .margin({ right: 4 })

            Text('···')
              .fontSize(11)
              .fontColor('#A1A1AA')
              .padding({ left: 2, right: 2 })
              .visibility(this.hoveredSessionId === this.ensureWorkspaceBinding(item) ? Visibility.Visible : Visibility.Hidden)
              .bindContextMenu(!!this.showSessionMenuId, this.sessionContextMenuBuilder(item), { placement: Placement.TopRight })
              .onClick(() => {
                const sid: string = this.ensureWorkspaceBinding(item);
                this.showSessionMenuId = this.showSessionMenuId === sid ? '' : sid;
              })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.isWorkspaceActive(item) ? '#F4F4F5' : (this.hoveredSessionId === this.ensureWorkspaceBinding(item) ? '#F9FAFB' : 'transparent'))
          .onHover((isHover: boolean) => {
            if (this.showSessionMenuId.length === 0) {
              this.hoveredSessionId = isHover ? this.ensureWorkspaceBinding(item) : '';
            }
          })
          .onClick(() => {
            void this.selectWorkspace(item);
          })
          .bindContextMenu(this.sessionContextMenuBuilder(item), ResponseType.RightClick)
        }
      }
      .width('100%')
  }

  private findSessionUpdatedAt(item: WorkspaceItem): string {
    const summaries: SessionSummary[] = codexBackend.sessionSummaries();
    const sessionId: string = this.ensureWorkspaceBinding(item);
    for (let i: number = 0; i < summaries.length; i += 1) {
      if (summaries[i].sessionId === sessionId) {
        return summaries[i].lastUpdatedAt;
      }
    }
    return '';
  }

  @Builder
  private sessionContextMenuBuilder(item: WorkspaceItem) {
    Menu() {
      MenuItem({ content: '重命名会话' })
        .onClick(() => {
          this.renameSessionDialogId = this.ensureWorkspaceBinding(item);
          this.renameSessionDialogText = item.title;
          this.showRenameSessionDialog = true;
        })

      MenuItem({ content: '删除会话' })
        .onClick(() => {
          this.deleteSessionDialogId = this.ensureWorkspaceBinding(item);
          this.deleteSessionDialogTitle = item.title;
          this.showDeleteSessionDialog = true;
        })
    }
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .width(78)

      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#27272A')
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
        .fontColor('#A1A1AA')
        .margin({ right: 6 })

      Text(text)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor('#27272A')
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
        if (this.isCollapsibleMessage(item)) {
          Text(this.isMessageCollapsed(item) ? '▸' : '▾')
            .copyOption(CopyOptions.None)
            .fontSize(12)
            .fontColor('#71717A')
            .width(14)
            .margin({ right: 2 })
        }

        Text(this.messageIcon(item.itemType))
          .fontSize(12)
          .margin({ right: 4 })

        Text(item.author)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.authorColor(item.itemType ?? item.role))

        Text(item.timestamp)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#A1A1AA')
          .margin({ left: 8 })

        if (item.status && item.status !== 'completed') {
          Text(this.statusLabel(item.status))
            .fontSize(9)
            .fontColor(this.statusColor(item.status))
            .backgroundColor(this.statusBgColor(item.status))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .margin({ left: 8 })
        }
      }
      .constraintSize({ maxWidth: '100%' })
      .onClick(() => {
        if (this.isCollapsibleMessage(item)) {
          this.toggleMessageExpanded(item.id);
        }
      })

      if (this.isMessageCollapsed(item)) {
        Text(item.content)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(19)
          .fontColor(this.messageContentColor(item.itemType))
          .margin({ top: 6 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(item.content)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(19)
          .fontColor(this.messageContentColor(item.itemType))
          .margin({ top: 6 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: '100%' })
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.messageBackground(item.itemType ?? item.role))
    .borderRadius(10)
  }

  @Builder
  private messageLine(item: ChatMessage) {
    Row() {
      if (this.isUserMessage(item)) {
        Blank()
          .layoutWeight(1)
        this.messageCard(item)
      } else {
        this.messageCard(item)
        Blank()
          .layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 8 })
  }

  private isUserMessage(item: ChatMessage): boolean {
    return item.role === 'user';
  }

  private isCollapsibleMessage(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    return type === 'reasoning' ||
      type === 'command' ||
      type === 'tool' ||
      type === 'file' ||
      type === 'search' ||
      type === 'plan' ||
      type === 'image' ||
      type === 'hook' ||
      type === 'review' ||
      type === 'system';
  }

  private isMessageCollapsed(item: ChatMessage): boolean {
    return this.isCollapsibleMessage(item) && !this.isMessageExpanded(item.id);
  }

  private isMessageExpanded(messageId: string): boolean {
    return this.expandedIntermediateMessageIds.indexOf(messageId) >= 0;
  }

  private toggleMessageExpanded(messageId: string): void {
    if (this.isMessageExpanded(messageId)) {
      this.expandedIntermediateMessageIds = this.expandedIntermediateMessageIds.filter((id: string) => id !== messageId);
      return;
    }
    this.expandedIntermediateMessageIds = [...this.expandedIntermediateMessageIds, messageId];
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
        return '#71717A';
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
        return '#F4F4F5';
    }
  }

  private messageContentColor(itemType?: string): string {
    switch (itemType) {
      case 'reasoning':
        return '#71717A';
      case 'command':
      case 'tool':
        return '#1E40AF';
      default:
        return '#27272A';
    }
  }

  @Builder
  private diffRow(line: CodeDiffLine) {
    Row() {
      Text(line.lineNumber)
        .copyOption(CopyOptions.LocalDevice)
        .width(28)
        .fontSize(10)
        .fontColor('#A1A1AA')
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
    .borderRadius(8)
  }

  @Builder
  private diffFileRow(file: CodeDiffFile) {
    Row() {
      Column() {
        Text(file.label)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(this.isDiffFileSelected(file) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor('#18181B')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(file.path)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(9)
          .fontColor('#A1A1AA')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(file.diffStat)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor(this.isDiffFileSelected(file) ? '#2563EB' : '#16A34A')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.isDiffFileSelected(file) ? '#F4F4F5' : '#FFFFFF')
    .borderRadius(8)
    .onClick(() => {
      this.selectDiffFile(file.path);
    })
  }

  @Builder
  private actionChip(label: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor('#71717A')
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor('#FAFAFA')
      .borderRadius(6)
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
        .fontColor('#27272A')
        .lineHeight(19)
        .margin({ top: 10 })

      Row() {
        Button('允许')
          .height(34)
          .fontSize(12)
          .backgroundColor('#27272A')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            void this.approvePending();
          })

        Button('拒绝')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#FAFAFA')
          .fontColor('#27272A')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
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
    .backgroundColor('#FFFBEB')
    .borderRadius(10)
    .margin({ top: 10 })
  }

  @Builder
  private requestUserInputCard(request: CodexRequestUserInput) {
    Column() {
      Row() {
        this.panelTitle(request.title, '继续执行当前计划前，需要你补充信息')

        Blank()
          .layoutWeight(1)

        this.chip('Plan', '#FFF7ED', '#C2410C')
      }
      .width('100%')

      if (request.detail.trim().length > 0) {
        Text(request.detail)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor('#27272A')
          .lineHeight(19)
          .margin({ top: 10 })
      }

      Column() {
        ForEach(request.questions, (question: CodexRequestUserInputQuestion) => {
          Column() {
            Text(question.header)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#18181B')

            Text(question.question)
              .fontSize(11)
              .fontColor('#71717A')
              .lineHeight(18)
              .margin({ top: 4 })

            if (question.options.length > 0) {
              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                ForEach(question.options, (option: CodexRequestUserInputOption) => {
                  Column() {
                    this.optionChip(
                      new SelectorOption(option.label, option.label),
                      this.requestUserInputAnswer(question.id) === option.label,
                      () => {
                        this.setRequestUserInputAnswer(question.id, option.label);
                      }
                    )
                    if (option.description.trim().length > 0) {
                      Text(option.description)
                        .fontSize(10)
                        .fontColor('#A1A1AA')
                        .lineHeight(16)
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ right: 8, bottom: 8 })
                }, (option: CodexRequestUserInputOption) => `${question.id}:${option.label}`)
              }
              .width('100%')
              .margin({ top: 8 })
            }

            if (question.isOther || question.options.length === 0) {
              TextInput({
                text: this.requestUserInputAnswer(question.id),
                placeholder: question.isSecret ? '输入不会展示在会话流里的私密内容' : '输入你的回答'
              })
                .width('100%')
                .height(40)
                .margin({ top: 8 })
                .fontSize(11)
                .backgroundColor('#FAFAFA')
                .borderRadius(8)
                .border({ width: 0.5, color: '#E4E4E7' })
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.setRequestUserInputAnswer(question.id, value);
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 12 })
        }, (question: CodexRequestUserInputQuestion) => question.id)
      }
      .width('100%')

      Row() {
        Button('继续')
          .height(34)
          .fontSize(12)
          .backgroundColor('#27272A')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            void this.submitRequestUserInput();
          })

        Button('取消')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#FAFAFA')
          .fontColor('#27272A')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            void this.declineRequestUserInput();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 14 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFBEB')
    .borderRadius(10)
    .margin({ top: 10 })
  }

  @Builder
  private leftPanel() {
    Column() {
      // Header
      Text('ArkPilot')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#18181B')
        .width('100%')

      // Title row with + button
      Row() {
        Text('项目')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#18181B')

        Blank()
          .layoutWeight(1)

        Text('+')
          .fontSize(18)
          .fontColor('#71717A')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .onClick(() => {
            this.newProjectName = '';
            this.newProjectPath = '';
            this.showCreateProjectDialog = true;
          })
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 8, bottom: 8 })

      // Scrollable project list — takes all remaining space
      List({ scroller: this.leftScrollController }) {
        if (this.projects.length === 0) {
          ListItem() {
            Text('暂无项目，点击右上角 + 创建')
              .fontSize(10)
              .fontColor('#D4D4D8')
              .margin({ top: 4 })
          }
        } else {
          ForEach(this.projects, (proj: ProjectRecord) => {
            ListItem() {
              this.projectGroup(proj)
            }
            .padding({ left: 0, right: 0 })
          }, (proj: ProjectRecord) => `${proj.id}_${proj.expanded.toString()}`)
        }
      }
      .listDirection(Axis.Vertical)
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)

      // Settings button — always at bottom
      Button() {
        Row() {
          Text('⚙')
            .fontSize(14)
            .fontColor('#71717A')

          Text('设置')
            .fontSize(12)
            .fontColor('#71717A')
            .margin({ left: 6 })
        }
      }
      .height(38)
      .width('100%')
      .margin({ top: 8 })
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .border({ width: 0.5, color: '#E4E4E7' })
      .onClick(() => {
        router.pushUrl({ url: 'pages/SettingsPage' });
      })

      // Dialogs — below Settings button
      if (this.showCreateProjectDialog) {
        Column() {
          Text('新建项目')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .margin({ bottom: 10 })

          TextInput({ placeholder: '项目名称', text: this.newProjectName })
            .width('100%')
            .height(36)
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .border({ width: 0.5, color: '#D4D4D8' })
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.newProjectName = value;
            })

          Text(this.newProjectPath.length > 0 ? this.newProjectPath : '未选择目录')
            .width('100%')
            .fontSize(11)
            .fontColor(this.newProjectPath.length > 0 ? '#27272A' : '#A1A1AA')
            .margin({ top: 8 })
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor('#F4F4F5')
            .borderRadius(8)

          Button('选择目录')
            .width('100%')
            .height(32)
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .fontColor('#27272A')
            .border({ width: 0.5, color: '#E4E4E7' })
            .borderRadius(8)
            .margin({ top: 8 })
            .onClick(() => {
              void this.pickWorkspaceDirectoryForProject();
            })

          Row() {
            Button('取消')
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .backgroundColor('#F4F4F5')
              .fontColor('#27272A')
              .borderRadius(8)
              .onClick(() => {
                this.showCreateProjectDialog = false;
              })

            Button('创建')
              .layoutWeight(1)
              .height(32)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                void this.createProject();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E4E4E7' })
        .borderRadius(12)
      }

      if (this.showNewSessionDialog) {
        Column() {
          Text('新建会话')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .margin({ bottom: 10 })

          TextInput({ placeholder: '会话名称', text: this.newSessionName })
            .width('100%')
            .height(36)
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .border({ width: 0.5, color: '#D4D4D8' })
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.newSessionName = value;
            })

          Row() {
            Button('取消')
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .backgroundColor('#F4F4F5')
              .fontColor('#27272A')
              .borderRadius(8)
              .onClick(() => {
                this.showNewSessionDialog = false;
              })

            Button('创建')
              .layoutWeight(1)
              .height(32)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                void this.confirmCreateSession();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E4E4E7' })
        .borderRadius(12)
      }

      if (this.showRenameProjectDialog) {
        Column() {
          Text('重命名项目')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .margin({ bottom: 10 })

          TextInput({ placeholder: '项目名称', text: this.renameProjectDialogText })
            .width('100%')
            .height(36)
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .border({ width: 0.5, color: '#D4D4D8' })
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.renameProjectDialogText = value;
            })

          Row() {
            Button('取消')
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .backgroundColor('#F4F4F5')
              .fontColor('#27272A')
              .borderRadius(8)
              .onClick(() => {
                this.showRenameProjectDialog = false;
              })

            Button('确认')
              .layoutWeight(1)
              .height(32)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                const name: string = this.renameProjectDialogText.trim();
                if (name.length === 0 || this.renameProjectDialogId.length === 0) {
                  return;
                }
                const next: ProjectRecord[] = [];
                for (let i: number = 0; i < this.projects.length; i += 1) {
                  const p: ProjectRecord = this.projects[i];
                  if (p.id === this.renameProjectDialogId) {
                    next.push(new ProjectRecord(p.id, name, p.path, p.expanded));
                  } else {
                    next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded));
                  }
                }
                this.projects = next;
                this.saveProjects();
                this.showRenameProjectDialog = false;
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E4E4E7' })
        .borderRadius(12)
      }

      if (this.showDeleteProjectDialog) {
        Column() {
          Text('删除项目')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .margin({ bottom: 10 })

          Text(`确认删除项目「${this.deleteProjectDialogName}」？`)
            .fontSize(12)
            .fontColor('#52525B')
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor('#FEF2F2')
            .borderRadius(8)

          Row() {
            Button('取消')
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .backgroundColor('#F4F4F5')
              .fontColor('#27272A')
              .borderRadius(8)
              .onClick(() => {
                this.showDeleteProjectDialog = false;
              })

            Button('删除')
              .layoutWeight(1)
              .height(32)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#DC2626')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                void this.deleteProject(this.deleteProjectDialogId);
                this.showDeleteProjectDialog = false;
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E4E4E7' })
        .borderRadius(12)
      }

      if (this.showRenameSessionDialog) {
        Column() {
          Text('重命名会话')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .margin({ bottom: 10 })

          TextInput({ placeholder: '会话名称', text: this.renameSessionDialogText })
            .width('100%')
            .height(36)
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .border({ width: 0.5, color: '#D4D4D8' })
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.renameSessionDialogText = value;
            })

          Row() {
            Button('取消')
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .backgroundColor('#F4F4F5')
              .fontColor('#27272A')
              .borderRadius(8)
              .onClick(() => {
                this.showRenameSessionDialog = false;
              })

            Button('确认')
              .layoutWeight(1)
              .height(32)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                const name: string = this.renameSessionDialogText.trim();
                if (name.length === 0 || this.renameSessionDialogId.length === 0) {
                  return;
                }
                const next: WorkspaceItem[] = [];
                for (let i: number = 0; i < this.workspaces.length; i += 1) {
                  const w: WorkspaceItem = this.workspaces[i];
                  if (this.ensureWorkspaceBinding(w) === this.renameSessionDialogId) {
                    next.push(new WorkspaceItem(w.id, name, w.description, w.workspaceId, w.projectId));
                  } else {
                    next.push(new WorkspaceItem(w.id, w.title, w.description, w.workspaceId, w.projectId));
                  }
                }
                this.workspaces = next;
                this.syncRecentWorkspaces();
                this.syncCurrentWorkspaceState();
                this.persistWorkspaceBindings();
                this.showRenameSessionDialog = false;
                void codexBackend.renameSession(this.renameSessionDialogId, name);
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E4E4E7' })
        .borderRadius(12)
      }

      if (this.showDeleteSessionDialog) {
        Column() {
          Text('删除会话')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .margin({ bottom: 10 })

          Text(`确认删除会话「${this.deleteSessionDialogTitle}」？`)
            .fontSize(12)
            .fontColor('#52525B')
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor('#FEF2F2')
            .borderRadius(8)

          Row() {
            Button('取消')
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .backgroundColor('#F4F4F5')
              .fontColor('#27272A')
              .borderRadius(8)
              .onClick(() => {
                this.showDeleteSessionDialog = false;
              })

            Button('删除')
              .layoutWeight(1)
              .height(32)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#DC2626')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                void this.deleteSession(this.deleteSessionDialogId);
                this.showDeleteSessionDialog = false;
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E4E4E7' })
        .borderRadius(12)
      }
    }
    .height('100%')
    .width(this.leftPanelWidth)
    .padding(12)
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(20)
    .onClick(() => {
      this.showProjectMenuId = '';
      this.showSessionMenuId = '';
    })
  }

  @Builder
  private chatCenterView() {
    Column() {
      Row() {
        Button() {
          Stack() {
            Column()
              .width(16)
              .height(12)
              .borderRadius(3)
              .border({ width: 1.5, color: '#71717A' })
              .backgroundColor(this.showLeftDrawer ? '#F4F4F5' : '#FFFFFF')
            Column()
              .width(1.5)
              .height(8)
              .backgroundColor('#71717A')
              .position({ x: 4, y: 2 })
          }
          .width(16)
          .height(12)
        }
        .type(ButtonType.Normal)
        .width(32)
        .height(28)
        .backgroundColor('#FAFAFA')
        .borderRadius(8)
        .border({ width: 0.5, color: '#E4E4E7' })
        .onClick(() => {
          this.toggleLeftDrawer();
        })

        Blank()
          .width(6)

        Column() {
          Text(this.currentWorkspaceTitle)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')

          Text(this.currentWorkspaceDescription)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#A1A1AA')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
          .layoutWeight(1)

        Row() {
          Text(this.currentCollaborationModeLabel())
            .copyOption(CopyOptions.None)
            .fontSize(10)
            .fontColor('#C2410C')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#FFF7ED')
            .borderRadius(6)
          Blank()
            .width(6)
          Text(this.currentModelLabel())
            .copyOption(CopyOptions.None)
            .fontSize(10)
            .fontColor('#2563EB')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#EFF6FF')
            .borderRadius(6)
          Blank()
            .width(6)
          Text(this.currentEffortLabel())
            .copyOption(CopyOptions.None)
            .fontSize(10)
            .fontColor('#71717A')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#F4F4F5')
            .borderRadius(6)
          Blank()
            .width(6)
          Button() {
            Stack() {
              Column()
                .width(16)
                .height(12)
                .borderRadius(3)
                .border({ width: 1.5, color: '#71717A' })
                .backgroundColor(this.showRightDrawer ? '#F4F4F5' : '#FFFFFF')
              Column()
                .width(1.5)
                .height(8)
                .backgroundColor('#71717A')
                .position({ x: 10.5, y: 2 })
            }
            .width(16)
            .height(12)
          }
          .type(ButtonType.Normal)
          .width(32)
          .height(28)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            this.toggleRightDrawer();
          })
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
          .fontColor('#18181B')

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
            .fontColor('#71717A')
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
      .border({ width: 0.5, color: '#E4E4E7' })
      .borderRadius(12)

      if (this.pendingApproval !== null) {
        this.approvalCard(this.pendingApproval!)
      }

      if (this.pendingRequestUserInput !== null) {
        this.requestUserInputCard(this.pendingRequestUserInput!)
      }

      Scroll(this.messageScroller) {
        Column() {
          ForEach(this.visibleMessages(), (item: ChatMessage) => {
            this.messageLine(item)
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
          Row() {
            Text('模式')
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#71717A')
            Text(this.currentCollaborationModeLabel())
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#18181B')
              .margin({ left: 6 })
            Text('▾')
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#A1A1AA')
              .margin({ left: 6 })
          }
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor(this.showCollaborationModeOptions ? '#F4F4F5' : '#FAFAFA')
          .border({ width: 0.5, color: this.showCollaborationModeOptions ? '#D4D4D8' : '#E4E4E7' })
          .borderRadius(8)
          .onClick(() => {
            this.showCollaborationModeOptions = !this.showCollaborationModeOptions;
            if (this.showCollaborationModeOptions) {
              this.showEffortOptions = false;
            }
          })

          Blank()
            .width(8)
          Row() {
            Text('推理')
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#64748B')

            Text(this.currentEffortLabel())
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
          .backgroundColor(this.showEffortOptions ? '#EEF4FF' : '#FFFFFF')
          .border({ width: 1, color: this.showEffortOptions ? '#BFDBFE' : '#D7DEE8' })
          .borderRadius(12)
          .onClick(() => {
            this.showEffortOptions = !this.showEffortOptions;
            if (this.showEffortOptions) {
              this.showCollaborationModeOptions = false;
            }
          })
        }
        .width('100%')

        if (this.showCollaborationModeOptions) {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(this.collaborationModes, (item: CollaborationModeOption) => {
              this.optionChip(
                new SelectorOption(item.name, item.name),
                this.selectedCollaborationModeName === item.name,
                () => {
                  this.chooseCollaborationMode(item);
                }
              )
            }, (item: CollaborationModeOption) => item.name)
          }
          .width('100%')
          .margin({ top: 8 })
        }

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
          TextInput({ text: this.draft, placeholder: '输入要发送给 ArkPilot 的指令...' })
            .layoutWeight(1)
            .height(40)
            .fontSize(12)
            .fontColor('#18181B')
            .placeholderColor('#A1A1AA')
            .backgroundColor('#FAFAFA')
            .borderRadius(10)
            .border({ width: 0.5, color: '#E4E4E7' })
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
            .backgroundColor('#27272A')
            .borderRadius(10)
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
            .fontColor('#A1A1AA')

          Text(this.workspaceRoot.trim().length > 0 ? this.workspaceRoot : '默认 cwd')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#A1A1AA')
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
      .backgroundColor('#FAFAFA')
      .border({ width: 0.5, color: '#E4E4E7' })
      .borderRadius(10)
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private centerPanel() {
    Column() {
      if (this.workspaces.length === 0) {
        Row() {
          Button() {
          Stack() {
            Column()
              .width(16)
              .height(12)
              .borderRadius(3)
              .border({ width: 1.5, color: '#71717A' })
              .backgroundColor(this.showLeftDrawer ? '#F4F4F5' : '#FFFFFF')
            Column()
              .width(1.5)
              .height(8)
              .backgroundColor('#71717A')
              .position({ x: 4, y: 2 })
          }
          .width(16)
          .height(12)
        }
        .type(ButtonType.Normal)
        .width(32)
        .height(28)
        .backgroundColor('#FAFAFA')
        .borderRadius(8)
        .border({ width: 0.5, color: '#E4E4E7' })
        .onClick(() => {
          this.toggleLeftDrawer();
        })
          Blank()
            .layoutWeight(1)
          Button() {
            Stack() {
              Column()
                .width(16)
                .height(12)
                .borderRadius(3)
                .border({ width: 1.5, color: '#71717A' })
                .backgroundColor(this.showRightDrawer ? '#F4F4F5' : '#FFFFFF')
              Column()
                .width(1.5)
                .height(8)
                .backgroundColor('#71717A')
                .position({ x: 10.5, y: 2 })
            }
            .width(16)
            .height(12)
          }
          .type(ButtonType.Normal)
          .width(32)
          .height(28)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            this.toggleRightDrawer();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column() {
          Text('暂无会话')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontColor('#A1A1AA')
          Text('请在左侧项目中新建会话')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#D4D4D8')
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
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(12)
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
          .fontColor('#16A34A')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#F0FDF4')
          .borderRadius(6)
      }
      .width('100%')

      Text(this.changedFiles)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#71717A')
        .margin({ top: 8 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.diffFiles.length > 0) {
        Text('\u53d8\u66f4\u6587\u4ef6')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#A1A1AA')
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
            .fontColor('#A1A1AA')

          Text(this.currentDiffFilePath())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#27272A')
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
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(20)
  }

  // ── 上下文助手（Rust 侧预计算 blendedTotal / contextRemainingPercent，前端仅展示）──

  private formatTokenCount(count: number): string {
    if (count !== count) return '0';
    if (count <= 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) return (count / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return (count / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
  }

  private blendedTotal(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return 0;
    const v = this.tokenUsage.total.blendedTotal;
    if (typeof v !== 'number' || v !== v) return 0;
    return v < 0 ? 0 : v;
  }

  private contextWindow(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return 0;
    const v = this.tokenUsage.modelContextWindow;
    if (typeof v !== 'number' || v !== v) return 0;
    return v < 0 ? 0 : v;
  }

  private contextRemainingPct(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return -1;
    const v = this.tokenUsage.contextRemainingPercent;
    if (typeof v !== 'number' || v !== v) return -1;
    return v;
  }

  private usedPct(): number {
    const rem = this.contextRemainingPct();
    if (rem < 0) return -1;
    return (100 - rem);
  }

  private contextBarWidth(): string {
    const pct = this.usedPct();
    if (pct < 0) return '0%';
    const clamped: number = pct > 100 ? 100 : (pct < 0 ? 0 : pct);
    return clamped.toString() + '%';
  }

  private contextBarColor(): ResourceColor {
    const pct = this.usedPct();
    if (pct < 0) return '#3B82F6';
    if (pct >= 90) return '#EF4444';
    if (pct >= 70) return '#F59E0B';
    return '#3B82F6';
  }

  // total.total_tokens — 和 Rust 计算 remaining% 用的是同一个字段
  private totalTokensUsed(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return 0;
    const v = this.tokenUsage.total.totalTokens;
    if (typeof v !== 'number' || v !== v) return 0;
    return v < 0 ? 0 : v;
  }

  private contextText(): string {
    const used = this.totalTokensUsed();
    const win = this.contextWindow();
    const rem = this.contextRemainingPct();
    let suffix: string = '';
    if (win > 0 && rem >= 0) {
      suffix = rem <= 0 ? ' (已溢出)' : ' (' + rem.toString() + '% 剩余)';
    }
    if (win <= 0) return this.formatTokenCount(used) + suffix;
    return this.formatTokenCount(used) + ' / ' + this.formatTokenCount(win) + suffix;
  }

  private safePct(part: number, whole: number): string {
    if (whole <= 0 || part <= 0 || whole !== whole || part !== part) return '0%';
    const v = (part / whole) * 100;
    if (v !== v || v < 0) return '0%';
    return (v > 100 ? 100 : v).toFixed(0) + '%';
  }

  private tokenMiniText(): string {
    const total = this.totalTokensUsed();
    const win = this.contextWindow();
    const pct = this.contextRemainingPct();
    let suffix: string = '';
    if (win > 0 && pct >= 0) {
      suffix = pct <= 0 ? ' · 已溢出' : ' · 剩余 ' + pct.toString() + '%';
    }
    return '总 ' + this.formatTokenCount(total) + suffix;
  }

  private tokenTrendLinePath(data: DailyTokenSnapshot[], maxVal: number, w: number, h: number): string {
    if (data.length === 0 || maxVal <= 0) return '';
    const points: string[] = [];
    const stepX = w / Math.max(data.length - 1, 1);
    for (let i = 0; i < data.length; i++) {
      const x = i * stepX;
      const y = h - (data[i].totalTokens / maxVal) * (h - 4) - 2;
      if (i === 0) {
        points.push(`M ${x} ${y}`);
      } else {
        points.push(`L ${x} ${y}`);
      }
    }
    return points.join(' ');
  }

  private getTrendData(): DailyTokenSnapshot[] {
    if (this.tokenAggregate === null) return [];
    const days = this.tokenTrendRange === 1 ? 7 : 30;
    const len = this.tokenAggregate.daily.length;
    const start = Math.max(len - days, 0);
    return this.tokenAggregate.daily.slice(start, len);
  }

  private getTrendTokenPath(): string {
    const data = this.getTrendData();
    const maxVal = data.reduce((max: number, d: DailyTokenSnapshot) => Math.max(max, d.totalTokens), 0);
    return this.tokenTrendLinePath(data, maxVal, 220, 60);
  }

  private getTrendRequestPath(): string {
    const data = this.getTrendData();
    const maxReqs = data.reduce((max: number, d: DailyTokenSnapshot) => Math.max(max, d.requestCount), 0);
    const reqData = data.map((d: DailyTokenSnapshot): DailyTokenSnapshot => new DailyTokenSnapshot(d.date, d.requestCount, d.requestCount));
    return this.tokenTrendLinePath(reqData, maxReqs, 220, 60);
  }

  private getTrendSumTokens(): number {
    return this.getTrendData().reduce((s: number, d: DailyTokenSnapshot): number => s + d.totalTokens, 0);
  }

  private getTrendSumRequests(): number {
    return this.getTrendData().reduce((s: number, d: DailyTokenSnapshot): number => s + d.requestCount, 0);
  }

  private getTrendFirstDate(): string {
    const data = this.getTrendData();
    return data.length > 0 ? data[0].date.substring(5) : '';
  }

  private getTrendLastDate(): string {
    const data = this.getTrendData();
    return data.length > 0 ? data[data.length - 1].date.substring(5) : '';
  }

  @Builder tokenUsageCard() {
    Column() {
      // 箭头指示器（展开时显示，可拖拽调整高度）
      if (this.tokenCardExpanded) {
        Row() {
          Text('▼')
            .fontSize(10)
            .fontColor('#A1A1AA')
        }
        .width('100%')
        .height(16)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 10, topRight: 10 })
        .border({ width: 0.5, color: '#E4E4E7' })
        .margin({ bottom: -1 })
        .hitTestBehavior(HitTestMode.Block)
        .gesture(
          TapGesture()
            .onAction(() => {
              animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                this.tokenCardExpanded = false;
              });
            })
        )
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => {
              this.tokenCardDragStartY = 0;
              this.tokenCardDragStartH = this.tokenCardHeight;
            })
          .onActionUpdate((event: GestureEvent) => {
            const newH = this.tokenCardDragStartH - event.offsetY;
            if (newH >= 120 && newH <= 600) {
              this.tokenCardHeight = newH;
            }
          })
      )
      }

      // 卡片内容
      Column() {
        if (!this.tokenCardExpanded) {
          // 收起状态：只显示摘要
          Row() {
            Text(this.tokenMiniText())
              .fontSize(11)
              .fontColor('#71717A')
              .maxLines(1)
            Blank()
            Text('▲')
              .fontSize(10)
              .fontColor('#A1A1AA')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8, left: 12, right: 12 })
          .borderRadius({ topLeft: 10, topRight: 10 })
          .backgroundColor('#FAFAFA')
          .border({ width: 0.5, color: '#E4E4E7' })
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            TapGesture()
              .onAction(() => {
                animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                  this.tokenCardExpanded = true;
                });
              })
          )
        } else {
          // 展开状态：固定高度 + 滚动
          Scroll() {
            Column() {
              // 标题行
              Row() {
                Text('Token 用量')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#18181B')
                Blank()
                Text(this.providerName)
                  .fontSize(11)
                  .fontColor('#A1A1AA')
              }
              .width('100%')
              .padding({ bottom: 2 })

          // 上下文占用 — 仅在主视图显示
          if (this.contextWindow() > 0 && this.blendedTotal() > 0) {
            Column() {
              Row() {
                Text(this.contextText())
                  .fontSize(12)
                  .fontColor('#18181B')
              }
              .width('100%')
              Progress({ value: this.contextRemainingPct(), total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(6)
                .style({ strokeWidth: 6, enableSmoothEffect: true })
                .color(this.contextBarColor())
                .margin({ top: 4 })
            }
            .margin({ top: 8 })
          }

          // 标签页 — 分段式选择器
          Row() {
            Text('当前轮')
              .fontSize(12)
              .fontColor(this.tokenTab === 0 ? '#FFFFFF' : '#71717A')
              .fontWeight(this.tokenTab === 0 ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.tokenTab === 0 ? '#27272A' : 'transparent')
              .onClick(() => { this.tokenTab = 0; })
            Text('趋势')
              .fontSize(12)
              .fontColor(this.tokenTab === 1 ? '#FFFFFF' : '#71717A')
              .fontWeight(this.tokenTab === 1 ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.tokenTab === 1 ? '#27272A' : 'transparent')
              .onClick(() => { this.tokenTab = 1; })
          }
          .margin({ top: 10 })
          .padding(2)
          .borderRadius(8)
          .backgroundColor('#F4F4F5')
          .width('100%')

          // 当前轮 tab
          if (this.tokenTab === 0) {
            Column() {
              // 上下文窗口占用
              Column() {
                Row() {
                  Text('上下文窗口')
                    .fontSize(11)
                    .fontColor('#A1A1AA')
                  Blank()
                  Text(this.contextText())
                    .fontSize(11)
                    .fontColor('#18181B')
                  if (this.contextRemainingPct() <= 70 && this.contextRemainingPct() >= 0) {
                    Text(this.compacting ? '压缩中...' : (this.compactError.length > 0 ? this.compactError : '压缩'))
                      .fontSize(10)
                      .fontColor(this.compactError.length > 0 ? '#EF4444' : '#27272A')
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .border({ width: 1, color: this.compactError.length > 0 ? '#EF4444' : '#E4E4E7' })
                      .borderRadius(6)
                      .backgroundColor(this.compactError.length > 0 ? '#FEF2F2' : '#FAFAFA')
                      .margin({ left: 6 })
                      .onClick(() => {
                        this.compactError = '';
                        this.compacting = true;
                        const oldTotal = this.totalTokensUsed();
                        const threadId = codexBackend.compactActiveThread();
                        if (threadId.length === 0) {
                          this.compacting = false;
                          this.compactError = codexBackend.getLastCompactError();
                          setTimeout(() => { this.compactError = ''; }, 3000);
                        } else {
                          codexBackend.pollUntilTokenChange(threadId, oldTotal, (usage: TurnTokenUsage) => {
                            this.tokenUsage = usage;
                            this.compacting = false;
                            const saved = oldTotal - usage.total.totalTokens;
                            if (saved > 0) {
                              promptAction.showToast({ message: `压缩完成，释放 ${this.formatTokenCount(saved)} tokens`, duration: 3000 });
                            } else {
                              promptAction.showToast({ message: '压缩完成', duration: 2000 });
                            }
                          });
                        }
                      })
                  }
                }
                .width('100%')

                if (this.contextRemainingPct() >= 0) {
                  Progress({ value: this.contextRemainingPct(), total: 100, type: ProgressType.Linear })
                    .width('100%')
                    .height(4)
                    .style({ strokeWidth: 4, enableSmoothEffect: true })
                    .color(this.contextBarColor())
                    .margin({ top: 4 })
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 分隔线
              Row().width('100%').height(0.5).backgroundColor('#F4F4F5')

              if (this.tokenUsage === null) {
                Text('等待数据...')
                  .fontSize(11)
                  .fontColor('#A1A1AA')
                  .margin({ top: 12 })
              } else {
                // 堆叠条
                if (this.tokenUsage!.last.totalTokens <= 0) {
                  Row().width('100%').height(8).backgroundColor('#F4F4F5').borderRadius(4)
                } else {
                  Row() {
                    if (this.tokenUsage!.last.inputTokens > 0) {
                      Row()
                        .width(this.safePct(this.tokenUsage!.last.inputTokens, this.tokenUsage!.last.totalTokens))
                        .height(8)
                        .backgroundColor('#3B82F6')
                    }
                    if (this.tokenUsage!.last.cachedInputTokens > 0) {
                      Row()
                        .width(this.safePct(this.tokenUsage!.last.cachedInputTokens, this.tokenUsage!.last.totalTokens))
                        .height(8)
                        .backgroundColor('#A1A1AA')
                    }
                    if (this.tokenUsage!.last.outputTokens > 0) {
                      Row()
                        .width(this.safePct(this.tokenUsage!.last.outputTokens, this.tokenUsage!.last.totalTokens))
                        .height(8)
                        .backgroundColor('#22C55E')
                    }
                    if (this.tokenUsage!.last.reasoningOutputTokens > 0) {
                      Row()
                        .width(this.safePct(this.tokenUsage!.last.reasoningOutputTokens, this.tokenUsage!.last.totalTokens))
                        .height(8)
                        .backgroundColor('#A855F7')
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
                    Text('输入').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.inputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#A1A1AA')
                    Text('缓存').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.cachedInputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#22C55E')
                    Text('输出').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.outputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#A855F7')
                    Text('推理').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.reasoningOutputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                }
                .margin({ top: 10 })
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
                  .fontColor('#A1A1AA')
                  .margin({ top: 12 })
              } else {
                // 范围切换按钮
                Row() {
                  Text('今日')
                    .fontSize(11)
                    .fontColor(this.tokenTrendRange === 0 ? '#FFFFFF' : '#71717A')
                    .fontWeight(this.tokenTrendRange === 0 ? FontWeight.Medium : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor(this.tokenTrendRange === 0 ? '#27272A' : 'transparent')
                    .onClick(() => { this.tokenTrendRange = 0; })
                  Text('近7天')
                    .fontSize(11)
                    .fontColor(this.tokenTrendRange === 1 ? '#FFFFFF' : '#71717A')
                    .fontWeight(this.tokenTrendRange === 1 ? FontWeight.Medium : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor(this.tokenTrendRange === 1 ? '#27272A' : 'transparent')
                    .onClick(() => { this.tokenTrendRange = 1; })
                  Text('近30天')
                    .fontSize(11)
                    .fontColor(this.tokenTrendRange === 2 ? '#FFFFFF' : '#71717A')
                    .fontWeight(this.tokenTrendRange === 2 ? FontWeight.Medium : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor(this.tokenTrendRange === 2 ? '#27272A' : 'transparent')
                    .onClick(() => { this.tokenTrendRange = 2; })
                }
                .margin({ top: 8 })
                .padding(2)
                .borderRadius(7)
                .backgroundColor('#F4F4F5')
                .width('100%')

                // 今日视图：柱状图
                if (this.tokenTrendRange === 0) {
                  Column() {
                    Row() {
                      Text(`共 ${this.formatTokenCount(this.tokenAggregate!.today.totalTokens)} tokens · ${this.tokenAggregate!.today.requestCount} 次请求`)
                        .fontSize(10).fontColor('#A1A1AA')
                    }.width('100%').margin({ top: 10 })

                    // 柱状图
                    Row({ space: 8 }) {
                      Column() {
                        Column()
                          .width(28)
                          .height(this.tokenAggregate!.today.inputTokens > 0 ? `${Math.max((this.tokenAggregate!.today.inputTokens / this.tokenAggregate!.today.totalTokens) * 60, 3)}px` : '3px')
                          .backgroundColor('#3B82F6').borderRadius({ topLeft: 4, topRight: 4 })
                        Text(this.formatTokenCount(this.tokenAggregate!.today.inputTokens))
                          .fontSize(9).fontColor('#A1A1AA').margin({ top: 2 })
                        Text('输入').fontSize(9).fontColor('#A1A1AA')
                      }.alignItems(HorizontalAlign.Center).layoutWeight(1)

                      Column() {
                        Column()
                          .width(28)
                          .height(this.tokenAggregate!.today.outputTokens > 0 ? `${Math.max((this.tokenAggregate!.today.outputTokens / this.tokenAggregate!.today.totalTokens) * 60, 3)}px` : '3px')
                          .backgroundColor('#22C55E').borderRadius({ topLeft: 4, topRight: 4 })
                        Text(this.formatTokenCount(this.tokenAggregate!.today.outputTokens))
                          .fontSize(9).fontColor('#A1A1AA').margin({ top: 2 })
                        Text('输出').fontSize(9).fontColor('#A1A1AA')
                      }.alignItems(HorizontalAlign.Center).layoutWeight(1)

                      Column() {
                        Column()
                          .width(28)
                          .height(this.tokenAggregate!.today.cachedInputTokens > 0 ? `${Math.max((this.tokenAggregate!.today.cachedInputTokens / this.tokenAggregate!.today.totalTokens) * 60, 3)}px` : '3px')
                          .backgroundColor('#A1A1AA').borderRadius({ topLeft: 4, topRight: 4 })
                        Text(this.formatTokenCount(this.tokenAggregate!.today.cachedInputTokens))
                          .fontSize(9).fontColor('#A1A1AA').margin({ top: 2 })
                        Text('缓存').fontSize(9).fontColor('#A1A1AA')
                      }.alignItems(HorizontalAlign.Center).layoutWeight(1)

                      Column() {
                        Column()
                          .width(28)
                          .height(this.tokenAggregate!.today.reasoningOutputTokens > 0 ? `${Math.max((this.tokenAggregate!.today.reasoningOutputTokens / this.tokenAggregate!.today.totalTokens) * 60, 3)}px` : '3px')
                          .backgroundColor('#A855F7').borderRadius({ topLeft: 4, topRight: 4 })
                        Text(this.formatTokenCount(this.tokenAggregate!.today.reasoningOutputTokens))
                          .fontSize(9).fontColor('#A1A1AA').margin({ top: 2 })
                        Text('推理').fontSize(9).fontColor('#A1A1AA')
                      }.alignItems(HorizontalAlign.Center).layoutWeight(1)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Bottom)
                    .margin({ top: 10 })
                  }
                }

                // 近7天/近30天视图：曲线图
                if (this.tokenTrendRange === 1 || this.tokenTrendRange === 2) {
                  Column() {
                    // 总计
                    Row() {
                      Text(`共 ${this.formatTokenCount(this.getTrendSumTokens())} tokens · ${this.getTrendSumRequests()} 次请求`)
                        .fontSize(10).fontColor('#A1A1AA')
                    }.width('100%').margin({ top: 10 })

                    // 曲线图区域
                    Stack({ alignContent: Alignment.BottomStart }) {
                      // 网格线
                      Column() {
                        Row().width('100%').height(1).backgroundColor('#F4F4F5')
                        Row().width('100%').height(1).backgroundColor('#F4F4F5').margin({ top: 19 })
                        Row().width('100%').height(1).backgroundColor('#F4F4F5').margin({ top: 19 })
                      }.width(220).height(60)

                      // Token 曲线
                      Shape() {
                        Path()
                          .commands(this.getTrendTokenPath())
                          .stroke('#3B82F6')
                          .strokeWidth(1.5)
                          .fill('none')
                      }.width(220).height(60)

                      // 请求曲线
                      Shape() {
                        Path()
                          .commands(this.getTrendRequestPath())
                          .stroke('#22C55E')
                          .strokeWidth(1.5)
                          .fill('none')
                          .strokeDashArray([4, 2])
                      }.width(220).height(60)
                    }
                    .width(220)
                    .height(60)
                    .margin({ top: 10 })

                    // 图例
                    Row({ space: 16 }) {
                      Row({ space: 4 }) {
                        Row().width(12).height(2).backgroundColor('#3B82F6')
                        Text('Tokens').fontSize(9).fontColor('#A1A1AA')
                      }
                      Row({ space: 4 }) {
                        Row().width(12).height(2).backgroundColor('#22C55E')
                        Text('请求').fontSize(9).fontColor('#A1A1AA')
                      }
                    }.margin({ top: 6 })

                    // X轴日期
                    Row() {
                      Text(this.getTrendFirstDate()).fontSize(8).fontColor('#A1A1AA')
                      Blank()
                      Text(this.getTrendLastDate()).fontSize(8).fontColor('#A1A1AA')
                    }.width(220).margin({ top: 2 })
                  }
                }
              }
            }
            .margin({ top: 8 })
            .width('100%')
          }
            }
          }
          .scrollable(ScrollDirection.Vertical)
          .height(this.tokenCardHeight)
          .align(Alignment.TopStart)
        }
      }
      .padding(this.tokenCardExpanded ? 12 : 0)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius({ bottomLeft: 10, bottomRight: 10 })
      .border({ width: 0.5, color: '#E4E4E7' })
      .shadow(this.tokenCardExpanded ? { radius: 12, color: '#0A000000', offsetY: 4 } : undefined)
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
          Row() {
            this.leftPanel()

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
            .backgroundColor('#F4F4F5')
            .borderRadius(4)
            .hitTestBehavior(HitTestMode.Block)
            .gesture(
              PanGesture({ direction: PanDirection.Horizontal })
                .onActionStart(() => {
                  this.dragStartLeftW = this.leftPanelWidth;
                  this.dragStartRightW = this.rightPanelWidth;
                  this.leftHiding = false;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.leftHiding) return;
                  const newLeft = this.dragStartLeftW + event.offsetX;
                  if (newLeft <= this.leftDrawerMinWidth - 20) {
                    this.leftHiding = true;
                    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
                      this.showLeftDrawer = false;
                    });
                    setTimeout(() => {
                      this.leftPanelWidth = 280;
                    }, 350);
                  } else if (newLeft >= this.leftDrawerMinWidth) {
                    this.leftPanelWidth = newLeft;
                  }
                })
            )
          }
          .height('100%')
          .transition(TransitionEffect.move(TransitionEdge.START).animation({ duration: 300, curve: Curve.EaseOut }))
        }

        this.centerPanel()

        if (this.showRightDrawer) {
          Row() {
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
            .backgroundColor('#F4F4F5')
            .borderRadius(4)
            .hitTestBehavior(HitTestMode.Block)
            .gesture(
              PanGesture({ direction: PanDirection.Horizontal })
                .onActionStart(() => {
                  this.dragStartLeftW = this.leftPanelWidth;
                  this.dragStartRightW = this.rightPanelWidth;
                  this.rightHiding = false;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.rightHiding) return;
                  const newRight = this.dragStartRightW - event.offsetX;
                  if (newRight <= this.rightDrawerMinWidth - 20) {
                    this.rightHiding = true;
                    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
                      this.showRightDrawer = false;
                    });
                    setTimeout(() => {
                      this.rightPanelWidth = 360;
                    }, 350);
                  } else if (newRight >= this.rightDrawerMinWidth) {
                    this.rightPanelWidth = newRight;
                  }
                })
            )

            Column() {
              this.rightPanel()
            }
            .height('100%')
          }
          .transition(TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .height('100%')
      .padding(10)
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.showProjectMenuId = '';
      this.showSessionMenuId = '';
    })
  }
}
