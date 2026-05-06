import {
  codexBackend,
  CodexBackendSnapshot
} from '../backend/CodexBackend';
import {
  checkWorkspaceAccess,
  WorkspaceAccessStatus
} from '../backend/CodexNative';
import {
  SessionSummary,
  WorkspaceAccessKind,
  WorkspacePermissionState,
  WorkspaceItem,
  WorkspaceBindingDraft,
  WorkspaceDirectorySelection
} from '../backend/ConsoleModels';
import { StoredWorkspaceItem, workspaceBindingStore } from '../backend/WorkspaceBindingStore';
import router from '@ohos.router';
import { picker } from '@kit.CoreFileKit';
import uri from '@ohos.uri';

const SESSIONS_DOMAIN = 0x0001;
const SESSIONS_TAG = 'SessionsPage';

@Entry
@Component
struct SessionsPage {
  private readonly workspaceRoots: Map<number, string> = new Map();
  private readonly workspaceIds: Map<number, string> = new Map();
  private readonly workspaceUris: Map<number, string> = new Map();

  @State private workspaces: WorkspaceItem[] = [];
  @State private activeWorkspaceId: number = 0;
  @State private activeWorkspaceBindingId: string = '';
  @State private currentWorkspaceTitle: string = '';
  @State private currentWorkspaceDescription: string = '';
  @State private workspaceRoot: string = '';
  @State private workspaceDraftText: string = '';
  @State private sessionSummaries: SessionSummary[] = [];
  @State private recentWorkspaces: WorkspaceItem[] = [];
  @State private directoryFilter: string = '';
  @State private directoryFilterText: string = '使用默认工作区';
  @State private showLeftDrawer: boolean = true;
  @State private showRightDrawer: boolean = true;
  @State private leftPanelWidth: number = 280;
  @State private rightPanelWidth: number = 360;
  private readonly leftDrawerMinWidth: number = 200;
  private readonly rightDrawerMinWidth: number = 240;
  private dragStartLeftW: number = 0;
  private dragStartRightW: number = 0;

  @State private showCreateWorkspaceDialog: boolean = false;
  @State private createWorkspaceNameDraft: string = '';
  @State private createWorkspaceRootDraft: string = '';
  @State private createWorkspaceUriDraft: string = '';
  @State private createWorkspaceSelectionText: string = '使用默认工作区';
  @State private createWorkspaceStatusText: string = '未选择目录，将由 app-server 使用默认 cwd。';
  @State private isCreatingWorkspace: boolean = false;

  @State private showRenameSessionDialog: boolean = false;
  @State private renameSessionIdDraft: string = '';
  @State private renameSessionNameDraft: string = '';
  @State private renameSessionStatusText: string = '修改名称后会立即同步到会话列表。';
  @State private isRenamingSession: boolean = false;
  @State private deletingSessionId: string = '';

  @State private summaryTitle: string = '等待连接原生桥接后端';
  @State private summaryPoints: string[] = [
    '应用启动时会自动拉起内置 Rust ArkPilot host。',
    '这里通过 libentry.so 同步调用原生桥接层，而不是本地 mock。',
    '发送消息后会刷新对话、计划和 diff。'
  ];

  private backendSubscriptionId: number = -1;

  aboutToAppear(): void {
    this.backendSubscriptionId = codexBackend.subscribe((snapshot: CodexBackendSnapshot) => {
      this.applyBackendSnapshot(snapshot);
    });
    this.restoreWorkspaceBindings();
    void this.restoreSessionsFromBackend();

    // Check if Index passed a flag to open create dialog
    const openCreateDialog: boolean = (AppStorage.get('sessionsPageOpenCreateDialog') as boolean) ?? false;
    if (openCreateDialog) {
      AppStorage.setOrCreate('sessionsPageOpenCreateDialog', false);
      this.openCreateWorkspaceDialog();
    }
  }

  aboutToDisappear(): void {
    if (this.backendSubscriptionId >= 0) {
      codexBackend.unsubscribe(this.backendSubscriptionId);
      this.backendSubscriptionId = -1;
    }
  }

  private applyBackendSnapshot(snapshot: CodexBackendSnapshot): void {
    this.syncSessionSummariesFromCache();
  }

  // ── Workspace helpers ──

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
      return;
    }
    const active: WorkspaceItem = this.activeWorkspace()!;
    this.activeWorkspaceBindingId = this.ensureWorkspaceBinding(active);
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

  // ── Session data management ──

  private async restoreSessionsFromBackend(preferredThreadId?: string): Promise<void> {
    const sessions: SessionSummary[] = await codexBackend.loadPersistedSessions();
    this.sessionSummaries = [...sessions];
    this.applySessionSummariesToWorkspaces(sessions, preferredThreadId);
  }

  private syncSessionSummariesFromCache(preferredThreadId?: string): void {
    const sessions: SessionSummary[] = codexBackend.sessionSummaries();
    this.sessionSummaries = [...sessions];
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
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
  }

  private restoreWorkspaceBindings(): void {
    const snapshot = workspaceBindingStore.load();
    const restoredItems: WorkspaceBindingDraft[] = [];
    this.sessionSummaries = [];
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
        item.title.trim().length > 0 ? item.title : `会话 ${item.id}`,
        item.description,
        item.workspaceId.trim().length > 0 ? item.workspaceId : `session:${item.id.toString()}`,
        item.workspaceRoot,
        item.workspaceUri
      ));
    }

    if (restoredItems.length === 0) {
      this.activeWorkspaceId = snapshot.activeWorkspaceId > 0 ? snapshot.activeWorkspaceId : 1;
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

  // ── Session operations ──

  private findWorkspaceBySessionId(sessionId: string): WorkspaceItem | undefined {
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const workspace: WorkspaceItem = this.workspaces[index];
      if (this.ensureWorkspaceBinding(workspace) === sessionId) {
        return workspace;
      }
    }
    return undefined;
  }

  private isSessionSummaryActive(summary: SessionSummary): boolean {
    return summary.sessionId === this.activeWorkspaceBindingId;
  }

  private async openSessionSummary(summary: SessionSummary): Promise<void> {
    const existing: WorkspaceItem | undefined = this.findWorkspaceBySessionId(summary.sessionId);
    if (existing !== undefined) {
      const summaryRoot: string = summary.workspaceRoot.trim();
      if (summaryRoot.length > 0) {
        this.workspaceRoots.set(existing.id, summaryRoot);
      }
    }
    // Store the selected session ID and navigate to Index
    AppStorage.setOrCreate('sessionsPageSelectedSessionId', summary.sessionId);
    router.pushUrl({ url: 'pages/Index' });
  }

  private openRenameSessionDialog(summary: SessionSummary): void {
    this.renameSessionIdDraft = summary.sessionId;
    this.renameSessionNameDraft = summary.title;
    this.renameSessionStatusText = '修改名称后会立即同步到会话列表。';
    this.showRenameSessionDialog = true;
  }

  private closeRenameSessionDialog(): void {
    if (this.isRenamingSession) {
      return;
    }
    this.showRenameSessionDialog = false;
  }

  private async confirmRenameSession(): Promise<void> {
    if (this.isRenamingSession) {
      return;
    }
    const threadId: string = this.renameSessionIdDraft.trim();
    const title: string = this.renameSessionNameDraft.trim();
    if (threadId.length === 0) {
      return;
    }
    if (title.length === 0) {
      this.renameSessionStatusText = '请输入新的会话名称。';
      return;
    }
    this.isRenamingSession = true;
    this.renameSessionStatusText = '正在保存新的会话名称。';
    try {
      await codexBackend.renameSession(threadId, title);
      this.summaryTitle = '会话已重命名';
      this.summaryPoints = [`已更新会话名称：${title}`];
      this.syncSessionSummariesFromCache(threadId);
      this.showRenameSessionDialog = false;
    } catch (err) {
      this.renameSessionStatusText = `重命名失败: ${this.describeError(err)}`;
      this.summaryTitle = '重命名会话失败';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isRenamingSession = false;
    }
  }

  private async deleteSessionSummary(summary: SessionSummary): Promise<void> {
    if (this.deletingSessionId === summary.sessionId) {
      return;
    }
    this.deletingSessionId = summary.sessionId;
    try {
      await codexBackend.archiveSession(summary.sessionId);
      this.summaryTitle = '会话已删除';
      this.summaryPoints = [`已删除会话：${summary.title}`];
      if (this.activeWorkspaceBindingId === summary.sessionId) {
        this.activeWorkspaceBindingId = '';
      }
      await this.restoreSessionsFromBackend();
    } catch (err) {
      this.summaryTitle = '删除会话失败';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.deletingSessionId = '';
    }
  }

  // ── Create workspace ──

  private createWorkspace(): void {
    this.openCreateWorkspaceDialog();
  }

  private openCreateWorkspaceDialog(): void {
    const nextId: number = this.nextWorkspaceId();
    const currentWorkspaceRoot: string = this.workspaceDraftText.trim().length > 0 ? this.workspaceDraftText.trim() : this.workspaceRoot.trim();
    this.createWorkspaceNameDraft = `新会话 ${nextId}`;
    this.createWorkspaceRootDraft = currentWorkspaceRoot;
    this.createWorkspaceUriDraft = this.workspaceUris.get(this.activeWorkspaceId) ?? '';
    this.syncCreateWorkspaceSelectionText();
    this.refreshCreateWorkspaceDraftState();
    this.showCreateWorkspaceDialog = true;
  }

  private closeCreateWorkspaceDialog(): void {
    if (this.isCreatingWorkspace) {
      return;
    }
    this.showCreateWorkspaceDialog = false;
  }

  private clearCreateWorkspaceDirectorySelection(): void {
    if (this.isCreatingWorkspace) {
      return;
    }
    this.createWorkspaceRootDraft = '';
    this.createWorkspaceUriDraft = '';
    this.syncCreateWorkspaceSelectionText();
    this.refreshCreateWorkspaceDraftState();
  }

  private syncCreateWorkspaceSelectionText(): void {
    if (this.createWorkspaceUriDraft.trim().length > 0) {
      this.createWorkspaceSelectionText = `已选择目录: ${this.createWorkspaceUriDraft}`;
      return;
    }
    if (this.createWorkspaceRootDraft.trim().length > 0) {
      this.createWorkspaceSelectionText = `当前工作目录: ${this.createWorkspaceRootDraft}`;
      return;
    }
    this.createWorkspaceSelectionText = '使用默认工作区';
  }

  private refreshCreateWorkspaceDraftState(): void {
    const trimmedWorkspaceRoot: string = this.createWorkspaceRootDraft.trim();
    if (trimmedWorkspaceRoot.length === 0) {
      this.createWorkspaceStatusText = '未选择目录，将由 app-server 使用默认 cwd。';
      return;
    }
    const status: WorkspaceAccessStatus = checkWorkspaceAccess(trimmedWorkspaceRoot);
    this.createWorkspaceStatusText = status.message.trim().length > 0 ? status.message : '工作区已配置';
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

  private async pickCreateWorkspaceDirectory(): Promise<void> {
    try {
      const selection: WorkspaceDirectorySelection | null = await this.pickDirectorySelection();
      if (selection === null) {
        this.createWorkspaceStatusText = '未选择目录，继续使用默认工作区。';
        return;
      }
      this.createWorkspaceRootDraft = selection.rootPath;
      this.createWorkspaceUriDraft = selection.sourceUri;
      this.syncCreateWorkspaceSelectionText();
      this.refreshCreateWorkspaceDraftState();
    } catch (err) {
      this.createWorkspaceStatusText = `选择目录失败: ${this.describeError(err)}`;
    }
  }

  private async confirmCreateWorkspace(): Promise<void> {
    if (this.isCreatingWorkspace) {
      return;
    }
    const nextId: number = this.nextWorkspaceId();
    const title: string = this.createWorkspaceNameDraft.trim().length > 0 ? this.createWorkspaceNameDraft.trim() : `新会话 ${nextId}`;
    const trimmedWorkspaceRoot: string = this.createWorkspaceRootDraft.trim();
    let workspacePermissionState: WorkspacePermissionState = 'unavailable';
    let workspaceAccessKind: WorkspaceAccessKind = 'unknown';
    if (trimmedWorkspaceRoot.length > 0) {
      const status: WorkspaceAccessStatus = checkWorkspaceAccess(trimmedWorkspaceRoot);
      workspacePermissionState = this.mapWorkspacePermissionState(status.permissionState);
      workspaceAccessKind = this.mapWorkspaceAccessKind(status.accessKind);
      this.createWorkspaceStatusText = status.message.trim().length > 0 ? status.message : '工作区已配置';
    } else {
      this.createWorkspaceStatusText = '未选择目录，将由 app-server 使用默认 cwd。';
    }
    this.isCreatingWorkspace = true;
    this.summaryTitle = '正在创建会话';
    this.summaryPoints = ['正在通过 app-server 创建新的线程。'];
    try {
      const session: SessionSummary = await codexBackend.createThreadSession(
        title,
        '',
        trimmedWorkspaceRoot,
        workspacePermissionState,
        workspaceAccessKind,
        trimmedWorkspaceRoot.length > 0 ? [trimmedWorkspaceRoot] : [],
        'default'
      );
      this.directoryFilter = trimmedWorkspaceRoot;
      this.directoryFilterText = trimmedWorkspaceRoot.length > 0 ? trimmedWorkspaceRoot : '使用默认工作区';
      this.syncSessionSummariesFromCache(session.sessionId);
      this.showCreateWorkspaceDialog = false;
      // Navigate to Index with the new session
      AppStorage.setOrCreate('sessionsPageSelectedSessionId', session.sessionId);
      router.pushUrl({ url: 'pages/Index' });
    } catch (err) {
      this.createWorkspaceStatusText = `创建失败: ${this.describeError(err)}`;
      this.summaryTitle = '创建会话失败';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isCreatingWorkspace = false;
    }
  }

  // ── Utility ──

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
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

  // ── UI Builders ──

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

      if (subtitle.trim().length > 0) {
        Text(subtitle)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ top: 4 })
          .lineHeight(16)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
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

  @Builder
  private sessionSummaryCard(summary: SessionSummary) {
    Column() {
      Row() {
        Column() {
          Text(summary.title)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(summary.sessionId)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      this.infoRow('工作目录', summary.workspaceRoot.trim().length > 0 ? summary.workspaceRoot : '默认 cwd')
      this.infoRow('最近更新', summary.lastUpdatedAt)

      Row() {
        if (this.isSessionSummaryActive(summary)) {
          this.chip('当前会话', '#DBEAFE', '#1D4ED8')
        }

        Blank()
          .layoutWeight(1)

        Button('打开')
          .height(30)
          .fontSize(11)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(14)
          .onClick(() => {
            void this.openSessionSummary(summary);
          })

        Button('重命名')
          .height(30)
          .margin({ left: 8 })
          .fontSize(11)
          .backgroundColor('#FFFFFF')
          .fontColor('#1D4ED8')
          .borderRadius(14)
          .border({ width: 1, color: '#BFDBFE' })
          .enabled(this.deletingSessionId !== summary.sessionId)
          .onClick(() => {
            this.openRenameSessionDialog(summary);
          })

        Button(this.deletingSessionId === summary.sessionId ? '删除中...' : '删除')
          .height(30)
          .margin({ left: 8 })
          .fontSize(11)
          .backgroundColor('#FFFFFF')
          .fontColor('#B91C1C')
          .borderRadius(14)
          .border({ width: 1, color: '#FECACA' })
          .enabled(this.deletingSessionId !== summary.sessionId)
          .onClick(() => {
            void this.deleteSessionSummary(summary);
          })
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(10)
    .backgroundColor(this.isSessionSummaryActive(summary) ? '#F8FBFF' : '#FFFFFF')
    .border({
      width: 1,
      color: this.isSessionSummaryActive(summary) ? '#BFDBFE' : '#E2E8F0'
    })
    .borderRadius(18)
  }

  @Builder
  private sessionsCenterView() {
    Column() {
      Row() {
        this.leftDrawerToggle()

        Blank()
          .width(6)

        this.panelTitle('Sessions', '集中查看、切换并删除当前项目的会话')

        Blank()
          .layoutWeight(1)

        Button('新建会话')
          .height(34)
          .fontSize(12)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => {
            this.createWorkspace();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.sessionSummaries.length === 0) {
        Column() {
          this.panelTitle('暂无会话', '连接后会从 app-server 恢复历史线程')
          this.summaryBullet('点击右上角"新建会话"可以立即创建一个新的线程。')
          this.summaryBullet('如果你刚删除了最后一个会话，这里会保持为空。')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(14)
        .margin({ top: 12 })
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(18)
      } else {
        List({ space: 10 }) {
          ForEach(this.sessionSummaries, (summary: SessionSummary) => {
            ListItem() {
              this.sessionSummaryCard(summary)
            }
          }, (summary: SessionSummary) => `${summary.sessionId}:${summary.title}`)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 12 })
        .scrollBar(BarState.Off)
      }
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private leftPanel() {
    Column() {
      // Back button at top left
      Button() {
        Row() {
          Text('←')
            .fontSize(16)
            .fontColor('#0F172A')
          Text('Back')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .margin({ left: 8 })
        }
      }
      .height(42)
      .padding({ left: 14, right: 14 })
      .backgroundColor('#FFFFFF')
      .borderRadius(18)
      .border({ width: 1, color: '#D8E1EE' })
      .onClick(() => { router.back(); })

    Scroll() {
    Column() {
      Column() {
        this.panelTitle('会话概览', '查看当前项目线程并进入会话管理页')
        this.infoRow('会话数', this.sessionSummaries.length.toString())
        this.infoRow('当前会话', this.activeWorkspace()?.title ?? '-')

        Button('新建会话')
          .height(34)
          .margin({ top: 12 })
          .fontSize(12)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => {
            this.createWorkspace();
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .margin({ top: 12 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)

    }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .layoutWeight(1)
    .width('100%')
    }
    .height('100%')
    .width(this.leftPanelWidth)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  @Builder
  private centerPanel() {
    Column() {
      this.sessionsCenterView()
    }
    .height('100%')
    .layoutWeight(1)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  @Builder
  private rightPanel() {
    Column() {
      Column() {
        this.panelTitle('会话上下文', '显示当前选中会话与管理说明')
        this.infoRow('当前会话', this.activeWorkspace()?.title ?? '-')
        this.infoRow('会话总数', this.sessionSummaries.length.toString())
        this.infoRow('工作目录', this.workspaceRoot.trim().length > 0 ? this.workspaceRoot : '默认 cwd')
        this.summaryBullet('在中间列表里点击"打开"会切回 Chat 并加载该会话。')
        this.summaryBullet('点击"删除"会归档该线程，并从左侧/中间列表里移除。')
      }
      .alignItems(HorizontalAlign.Start)
      .height('100%')
      .width('100%')
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
  private createWorkspaceDialog() {
    if (this.showCreateWorkspaceDialog) {
      Column() {
        Column() {
          Row() {
            Text('新建会话')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A')

            Blank()
              .layoutWeight(1)

            Button('关闭')
              .height(28)
              .fontSize(10)
              .backgroundColor('#FFFFFF')
              .fontColor('#64748B')
              .borderRadius(10)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.closeCreateWorkspaceDialog();
              })
          }
          .width('100%')

          Text('会话名称')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ top: 14 })

          TextInput({ text: this.createWorkspaceNameDraft, placeholder: '输入新会话名称' })
            .width('100%')
            .height(40)
            .margin({ top: 8 })
            .fontSize(12)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.createWorkspaceNameDraft = value;
            })

          Text('工作区')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ top: 14 })

          Text(this.createWorkspaceRootDraft.trim().length > 0 ? this.createWorkspaceRootDraft : '未选择目录，当前将使用默认工作区')
            .width('100%')
            .margin({ top: 8 })
            .fontSize(12)
            .fontColor('#111827')
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .copyOption(CopyOptions.LocalDevice)

          Row() {
            Button('选择目录')
              .layoutWeight(1)
              .height(34)
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                void this.pickCreateWorkspaceDirectory();
              })

            Button('使用默认工作区')
              .layoutWeight(1)
              .height(34)
              .margin({ left: 10 })
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .fontColor('#64748B')
              .borderRadius(16)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.clearCreateWorkspaceDirectorySelection();
              })
          }
          .width('100%')
          .margin({ top: 10 })

          Text(this.createWorkspaceSelectionText)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ top: 8 })

          Text(this.createWorkspaceStatusText)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ top: 6 })

          Row() {
            Button(this.isCreatingWorkspace ? '创建中...' : '创建会话')
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .enabled(!this.isCreatingWorkspace)
              .onClick(() => {
                void this.confirmCreateWorkspace();
              })

            Button('取消')
              .layoutWeight(1)
              .height(36)
              .margin({ left: 10 })
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .fontColor('#64748B')
              .borderRadius(16)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.closeCreateWorkspaceDialog();
              })
          }
          .width('100%')
          .margin({ top: 18 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('36%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(20)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#660F172A')
    }
  }

  @Builder
  private renameSessionDialog() {
    if (this.showRenameSessionDialog) {
      Column() {
        Column() {
          Row() {
            Text('重命名会话')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A')

            Blank()
              .layoutWeight(1)

            Button('关闭')
              .height(28)
              .fontSize(10)
              .backgroundColor('#FFFFFF')
              .fontColor('#64748B')
              .borderRadius(10)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.closeRenameSessionDialog();
              })
          }
          .width('100%')

          Text('会话名称')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ top: 14 })

          TextInput({ text: this.renameSessionNameDraft, placeholder: '输入新的会话名称' })
            .width('100%')
            .height(40)
            .margin({ top: 8 })
            .fontSize(12)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.renameSessionNameDraft = value;
            })

          Text('会话 ID')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ top: 14 })

          Text(this.renameSessionIdDraft)
            .width('100%')
            .margin({ top: 8 })
            .fontSize(11)
            .fontColor('#111827')
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .copyOption(CopyOptions.LocalDevice)

          Text(this.renameSessionStatusText)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ top: 12 })

          Row() {
            Button(this.isRenamingSession ? '保存中...' : '保存名称')
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .enabled(!this.isRenamingSession)
              .onClick(() => {
                void this.confirmRenameSession();
              })

            Button('取消')
              .layoutWeight(1)
              .height(36)
              .margin({ left: 10 })
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .fontColor('#64748B')
              .borderRadius(16)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.closeRenameSessionDialog();
              })
          }
          .width('100%')
          .margin({ top: 18 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('36%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(20)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#660F172A')
    }
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

      this.createWorkspaceDialog()
      this.renameSessionDialog()
    }
    .width('100%')
    .height('100%')
  }
}
