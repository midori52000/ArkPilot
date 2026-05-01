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
  getEmbeddedCodexHostStatus,
  getEmbeddedCodexProviderConfig,
  saveEmbeddedCodexProviderConfig
} from '../backend/CodexNative';
import { SidebarView } from '../backend/ConsoleModels';
import { PromptsPage } from './PromptsPage';
import router from '@ohos.router';

class WorkspaceItem {
  id: number;
  title: string;
  description: string;

  constructor(id: number, title: string, description: string) {
    this.id = id;
    this.title = title;
    this.description = description;
  }
}

class SelectorOption {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

class SidebarItem {
  view: SidebarView;
  label: string;
  description: string;

  constructor(view: SidebarView, label: string, description: string) {
    this.view = view;
    this.label = label;
    this.description = description;
  }
}

class ChatMessage {
  id: string;
  author: string;
  role: string;
  content: string;
  timestamp: string;

  constructor(id: string, author: string, role: string, content: string, timestamp: string) {
    this.id = id;
    this.author = author;
    this.role = role;
    this.content = content;
    this.timestamp = timestamp;
  }
}

class CodeDiffLine {
  id: string;
  lineNumber: string;
  sign: string;
  content: string;
  kind: string;

  constructor(id: string, lineNumber: string, sign: string, content: string, kind: string) {
    this.id = id;
    this.lineNumber = lineNumber;
    this.sign = sign;
    this.content = content;
    this.kind = kind;
  }
}

@Entry
@Component
struct Index {
  private readonly workspaces: WorkspaceItem[] = [
    new WorkspaceItem(1, '默认会话', '通用 Codex 对话线程'),
    new WorkspaceItem(2, 'Rust app-server 移植', '用于跟踪 codex-rs 的鸿蒙适配'),
    new WorkspaceItem(3, '鸿蒙前端适配', '用于跟踪 Agent ArkTS 改造')
  ];
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
    new SidebarItem('chat', 'Chat', '继续与内置 Codex 协作'),
    new SidebarItem('sessions', 'Sessions', '查看与切换项目会话'),
    new SidebarItem('usage', 'Usage', '查看当前工作台统计'),
    new SidebarItem('prompts', 'Prompts', '自定义指令管理')
  ];
  private backendSubscriptionId: number = -1;
  private reconnectTimerId: number = -1;
  private reconnectAttemptCount: number = 0;
  private readonly workspaceRoots: Map<number, string> = new Map();
  private readonly messageScroller: Scroller = new Scroller();

  @State private activeSidebarView: SidebarView = 'chat';
  @State private activeWorkspaceId: number = 1;
  @State private selectedEffortIndex: number = 0;
  @State private showEffortOptions: boolean = false;
  @State private serverUrl: string = 'ws://127.0.0.1:7456';
  @State private workspaceRoot: string = '';
  @State private providerBaseUrl: string = '';
  @State private providerApiKey: string = '';
  @State private manualModel: string = '';
  @State private providerStatusText: string = 'Provider config not loaded yet.';
  @State private isSavingProvider: boolean = false;
  @State private apiKey: string = '';
  @State private isAuthenticating: boolean = false;
  @State private authStatusText: string = '未登录';
  @State private connectionState: CodexConnectionState = 'disconnected';
  @State private connectionText: string = '未连接';
  @State private summaryTitle: string = '等待连接原生桥接后端';
  @State private summaryPoints: string[] = [
    '应用启动时会自动拉起内置 Rust codex host。',
    '这里通过 libentry.so 同步调用原生桥接层，而不是本地 mock。',
    '发送消息后会刷新对话、计划和 diff。'
  ];
  @State private changedFiles: string = '尚未产生文件改动';
  @State private diffStat: string = '+0 -0';
  @State private isRunning: boolean = false;
  @State private leftPanelWidth: number = 240;
  @State private rightPanelWidth: number = 330;
  private rowContainerWidth: number = 1000;
  private readonly panelMinWidth: number = 120;
  private readonly splitterBarWidth: number = 8;
  private dragStartLeftW: number = 0;
  private dragStartRightW: number = 0;
  @State private draft: string = '检查当前工作目录，并说明需要我批准的操作。';
  @State private pendingApproval: CodexApprovalRequest | null = null;
  @State private messages: ChatMessage[] = [
    new ChatMessage(
      'welcome-1',
      'Codex',
      'assistant',
      '前端会自动连接应用内置 app-server。必要时你仍然可以手动重连或修改工作目录。',
      '刚刚'
    )
  ];
  @State private codeLines: CodeDiffLine[] = [
    new CodeDiffLine('placeholder-1', '1', ' ', '等待 turn/diff/updated 通知。', 'context')
  ];

  aboutToAppear(): void {
    this.backendSubscriptionId = codexBackend.subscribe((snapshot: CodexBackendSnapshot) => {
      this.applyBackendSnapshot(snapshot);
    });
    this.applyBackendSnapshot(codexBackend.snapshot());
    this.applyEmbeddedHostStatus();
    this.loadProviderConfig();
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

  private activeWorkspace(): WorkspaceItem {
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      if (this.workspaces[index].id === this.activeWorkspaceId) {
        return this.workspaces[index];
      }
    }
    return this.workspaces[0];
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
    void this.runTurn(prompt);
  }

  private async runTurn(prompt: string): Promise<void> {
    this.isRunning = true;
    this.workspaceRoots.set(this.activeWorkspaceId, this.workspaceRoot);
    codexBackend.configureServerUrl(this.serverUrl);

    const workspace: WorkspaceItem = this.activeWorkspace();
    this.applyEmbeddedHostStatus();
    try {
      const result: CodexTurnResult = await codexBackend.startTurn(
        new CodexTurnRequest(
          workspace.id.toString(),
          workspace.title,
          this.workspaceRoot.trim(),
          this.currentModelValue(),
          this.currentEffortValue(),
          prompt
        ),
        (update: CodexTurnResult) => {
          this.applyBackendResult(update);
        }
      );
      this.applyBackendResult(result);
      this.draft = '';
    } catch (err) {
      this.summaryTitle = '调用失败';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isRunning = false;
    }
  }

  private applyBackendResult(result: CodexTurnResult): void {
    this.messages = result.messages.map((item) => {
      return new ChatMessage(item.messageId, item.author, item.role, item.content, item.timestamp);
    });
    this.codeLines = result.diffLines.length > 0
      ? result.diffLines.map((line: CodexDiffLine) => {
          return new CodeDiffLine(line.lineId, line.lineNumber, line.sign, line.content, line.kind);
        })
      : [new CodeDiffLine('placeholder-2', '1', ' ', '本轮尚未产生 diff。', 'context')];
    this.summaryTitle = result.summaryTitle;
    this.summaryPoints = result.summaryPoints.length > 0 ? result.summaryPoints : ['没有可展示的摘要信息。'];
    this.changedFiles = result.changedFiles;
    this.diffStat = result.diffStat;
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
    this.providerBaseUrl = config.baseUrl;
    this.providerApiKey = config.apiKey;
    this.manualModel = config.model;
    this.providerStatusText = this.describeProviderConfig(config);
  }

  private async saveProviderConfig(): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }

    this.isSavingProvider = true;
    try {
      const config: CodexProviderConfig = saveEmbeddedCodexProviderConfig(
        this.providerBaseUrl.trim(),
        this.providerApiKey.trim(),
        this.manualModel.trim()
      );
      this.providerBaseUrl = config.baseUrl;
      this.providerApiKey = config.apiKey;
      this.manualModel = config.model;
      this.providerStatusText = this.describeProviderConfig(config);
      this.summaryTitle = 'Provider config saved';
      this.summaryPoints = [
        'base_url, api_key, and default model were written to CODEX_HOME/config.toml.',
        'Restart the app to apply provider changes to the embedded app-server.',
        this.providerStatusText
      ];
    } catch (err) {
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

  private selectWorkspace(item: WorkspaceItem): void {
    this.activeWorkspaceId = item.id;
    this.workspaceRoot = this.workspaceRoots.get(item.id) ?? '';
    this.draft = `继续处理”${item.title}”，重点关注当前工作目录。`;
    this.activeSidebarView = 'chat';
  }

  private createWorkspace(): void {
    let nextId: number = 1;
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      if (this.workspaces[index].id >= nextId) {
        nextId = this.workspaces[index].id + 1;
      }
    }
    const workspace: WorkspaceItem = new WorkspaceItem(nextId, `新会话 ${nextId}`, '从侧边栏创建的新线程');
    this.workspaces.push(workspace);
    this.selectWorkspace(workspace);
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
    if (role === 'assistant') {
      return '#FFFFFF';
    }
    if (role === 'system') {
      return '#F8FAFC';
    }
    return '#F6F3FF';
  }

  private messageBorder(role: string): string {
    if (role === 'assistant') {
      return '#DBEAFE';
    }
    if (role === 'system') {
      return '#CBD5E1';
    }
    return '#DDD6FE';
  }

  private authorColor(role: string): string {
    if (role === 'assistant') {
      return '#1D4ED8';
    }
    if (role === 'system') {
      return '#475569';
    }
    return '#7C3AED';
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

  private computeCenterWidth(): number {
    const totalSplitterW = this.splitterBarWidth * 2;
    const available = this.rowContainerWidth - 20 - totalSplitterW;
    const centerW = available - this.leftPanelWidth - this.rightPanelWidth;
    return Math.max(this.panelMinWidth, centerW);
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
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
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')

      Text(subtitle)
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
        .fontSize(10)
        .fontColor('#64748B')

      Text(value)
        .fontSize(10)
        .fontColor('#0F172A')
        .margin({ left: 6 })

      Text('▾')
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
        .fontSize(12)
        .fontWeight(this.isWorkspaceActive(item) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor('#0F172A')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(item.description)
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
      this.selectWorkspace(item);
    })
  }

  @Builder
  private sidebarRow(item: SidebarItem) {
    Column() {
      Row() {
        Text(item.label)
          .fontSize(12)
          .fontWeight(this.isSidebarActive(item.view) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor('#0F172A')

        Blank()
          .layoutWeight(1)
      }
      .width('100%')

      Text(item.description)
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
      this.activeSidebarView = item.view;
    })
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(10)
        .fontColor('#94A3B8')
        .width(78)

      Text(value)
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
  private metricCard(title: string, value: string, hint: string) {
    Column() {
      Text(title)
        .fontSize(10)
        .fontColor('#94A3B8')

      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
        .margin({ top: 8 })

      Text(hint)
        .fontSize(10)
        .fontColor('#64748B')
        .margin({ top: 6 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .width('48%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(16)
    .margin({ bottom: 8 })
  }

  @Builder
  private summaryBullet(text: string) {
    Row() {
      Text('•')
        .fontSize(12)
        .fontColor('#475569')
        .margin({ right: 6 })

      Text(text)
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
        Text(item.author)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.authorColor(item.role))

        Text(item.timestamp)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ left: 8 })
      }
      .width('100%')

      Text(item.content)
        .fontSize(12)
        .lineHeight(19)
        .fontColor('#334155')
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor(this.messageBackground(item.role))
    .border({
      width: 1,
      color: this.messageBorder(item.role)
    })
    .borderRadius(16)
  }

  @Builder
  private diffRow(line: CodeDiffLine) {
    Row() {
      Text(line.lineNumber)
        .width(28)
        .fontSize(10)
        .fontColor('#94A3B8')
        .fontFamily('monospace')

      Text(line.sign)
        .width(12)
        .fontSize(11)
        .fontColor(this.diffColor(line.kind))
        .fontFamily('monospace')

      Text(line.content)
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
  private actionChip(label: string) {
    Text(label)
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
  private splitterBar(isLeft: boolean) {
    Column() {
      Column()
        .width(2)
        .height('60%')
        .backgroundColor('#CBD5E1')
        .borderRadius(1)
    }
    .width(this.splitterBarWidth)
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
          const totalSplit = this.splitterBarWidth * 2;
          const available = this.rowContainerWidth - 20 - totalSplit;
          if (isLeft) {
            const newLeft = this.dragStartLeftW + event.offsetX;
            const centerW = available - newLeft - this.rightPanelWidth;
            if (newLeft >= this.panelMinWidth && centerW >= this.panelMinWidth) {
              this.leftPanelWidth = newLeft;
            }
          } else {
            const newRight = this.dragStartRightW - event.offsetX;
            const centerW = available - this.leftPanelWidth - newRight;
            if (newRight >= this.panelMinWidth && centerW >= this.panelMinWidth) {
              this.rightPanelWidth = newRight;
            }
          }
        })
    )
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
  private sessionsCenterView() {
    Column() {
      Row() {
        this.panelTitle('Sessions', '将当前 ArkPilot 线程状态可视化为会话面板')

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

      List({ space: 0 }) {
        ForEach(this.workspaces, (item: WorkspaceItem) => {
          ListItem() {
            this.workspaceRow(item)
          }
        }, (item: WorkspaceItem) => item.id.toString())
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
  private usageCenterView() {
    Column() {
      Row() {
        this.panelTitle('Usage', '基于当前对话线程派生的基础统计')

        Blank()
          .layoutWeight(1)

        this.chip(this.connectionText, '#F8FAFC', '#64748B')
      }
      .width('100%')

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.metricCard('会话数', this.workspaces.length.toString(), '当前工作台中已创建的线程数')
        this.metricCard('消息总数', this.messages.length.toString(), '当前线程缓存的消息条数')
        this.metricCard('Diff 行数', this.codeLines.length.toString(), '右栏当前缓存的 diff 行')
        this.metricCard('连接状态', this.connectionText, '当前 原生桥接 连接状态')
      }
      .width('100%')
      .margin({ top: 12 })

      Column() {
        this.panelTitle('说明', '第一阶段先做本地派生统计，不做精确 token/cost 账单')
        this.summaryBullet('统计来自 CodexBackend 内部线程快照，后续会继续收敛到原生桥接主链路。')
        this.summaryBullet('Provider / MCP / Skills 管理请通过左下角 Settings 按钮进入。')
      }
      .width('100%')
      .padding(14)
      .margin({ top: 6 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private leftPanel() {
    Column() {
      Row() {
        Column() {
          Text('ArkPilot')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text('项目侧边栏控制台')
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
          .layoutWeight(1)

        this.chip(this.connectionText, this.connectionChipBackground(), this.connectionChipColor())
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

      if (this.activeSidebarView === 'chat') {
        Column() {
          this.panelTitle('Chat 上下文', '保留连接、当前会话与工作目录')

          TextInput({ text: this.serverUrl, placeholder: 'ws://127.0.0.1:7456' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.serverUrl = value;
            })

          Button(this.connectionButtonLabel())
            .height(34)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#111827')
            .fontColor('#FFFFFF')
            .borderRadius(16)
            .onClick(() => {
              void this.connectOrDisconnect();
            })

          this.infoRow('认证', this.authStatusText)
          this.infoRow('Provider', this.providerStatusText)

          Row() {
            Text('会话')
              .fontSize(10)
              .fontColor('#94A3B8')

            Blank()
              .layoutWeight(1)

            Text(this.workspaces.length.toString())
              .fontSize(10)
              .fontColor('#94A3B8')
          }
          .width('100%')
          .margin({ top: 12, bottom: 8 })

          List({ space: 6 }) {
            ForEach(this.workspaces, (item: WorkspaceItem) => {
              ListItem() {
                this.workspaceRow(item)
              }
            }, (item: WorkspaceItem) => item.id.toString())
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)

          Column() {
            this.panelTitle('工作目录', '为空时由 app-server 使用自己的默认 cwd')

            TextInput({ text: this.workspaceRoot, placeholder: '例如 /data/storage/el2/base/files/project' })
              .width('100%')
              .height(38)
              .margin({ top: 10 })
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.workspaceRoot = value;
                this.workspaceRoots.set(this.activeWorkspaceId, value);
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(12)
          .margin({ top: 10 })
          .backgroundColor('#F8FAFC')
          .border({ width: 1, color: '#E2E8F0' })
          .borderRadius(16)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .layoutWeight(1)
        .padding(12)
        .margin({ top: 10 })
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(18)
      } else if (this.activeSidebarView === 'sessions') {
        Column() {
          this.panelTitle('会话概览', '查看当前项目线程与消息状态')
          this.infoRow('会话数', this.workspaces.length.toString())
          this.infoRow('当前会话', this.activeWorkspace().title)
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
        .layoutWeight(1)
        .padding(12)
        .margin({ top: 10 })
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(18)
      } else {
        Column() {
          this.panelTitle('Usage 概览', '基于当前 ArkPilot 线程状态派生')
          this.infoRow('会话', this.workspaces.length.toString())
          this.infoRow('状态', this.connectionText)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .layoutWeight(1)
        .padding(12)
        .margin({ top: 10 })
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(18)
      }

      // Settings button
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
        this.panelTitle(this.activeWorkspace().title, this.activeWorkspace().description)

        Blank()
          .layoutWeight(1)

        Row() {
          this.chip(this.currentModelLabel(), '#EEF4FF', '#1D4ED8')
          Blank()
            .width(6)
          this.chip(this.currentEffortLabel(), '#F8FAFC', '#64748B')
        }
      }
      .width('100%')

      Column() {
        Text(this.summaryTitle)
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
            .fontSize(11)
            .fontColor('#64748B')
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.diffStat)
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
          TextInput({ text: this.draft, placeholder: '输入要发送给真实 Codex 的指令...' })
            .layoutWeight(1)
            .height(40)
            .fontSize(12)
            .fontColor('#0F172A')
            .placeholderColor('#94A3B8')
            .backgroundColor('#FFFFFF')
            .borderRadius(19)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.draft = value;
            })

          Button(this.isRunning ? '...' : '发送')
            .width(52)
            .height(36)
            .margin({ left: 8 })
            .fontSize(12)
            .backgroundColor('#111827')
            .fontColor('#FFFFFF')
            .borderRadius(18)
            .onClick(() => {
              this.sendMessage();
            })
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          Text(this.connectionText)
            .fontSize(10)
            .fontColor('#94A3B8')

          Text(this.workspaceRoot.trim().length > 0 ? this.workspaceRoot : '默认 cwd')
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
  private promptsCenterView() {
    PromptsPage({ codexHome: '' })
  }

  @Builder
  private centerPanel() {
    Column() {
      if (this.activeSidebarView === 'chat') {
        this.chatCenterView()
      } else if (this.activeSidebarView === 'sessions') {
        this.sessionsCenterView()
      } else if (this.activeSidebarView === 'prompts') {
        this.promptsCenterView()
      } else {
        this.usageCenterView()
      }
    }
    .height('100%')
    .width(this.computeCenterWidth())
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

        this.chip(this.diffStat, '#ECFDF3', '#15803D')
      }
      .width('100%')

      Text(this.changedFiles)
        .fontSize(11)
        .fontColor('#64748B')
        .margin({ top: 8 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

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
      if (this.activeSidebarView === 'chat') {
        this.chatContextPanel()
      } else if (this.activeSidebarView === 'sessions') {
        Column() {
          this.panelTitle('会话上下文', '显示当前选中会话的摘要与工作目录')
          this.infoRow('当前会话', this.activeWorkspace().title)
          this.infoRow('工作目录', this.workspaceRoot.trim().length > 0 ? this.workspaceRoot : '默认 cwd')
          this.infoRow('消息数', this.messages.length.toString())
          this.infoRow('连接状态', this.connectionText)
        }
        .alignItems(HorizontalAlign.Start)
        .height('100%')
        .width('100%')
      } else if (this.activeSidebarView === 'prompts') {
        Column() {
          this.panelTitle('Prompts 上下文', '管理自定义指令（AGENTS.md）')
          this.infoRow('说明', '创建和切换 Prompt 版本，启用后写入 AGENTS.md')
          this.infoRow('生效方式', '切换 Prompt 后需新建会话')
          this.infoRow('连接状态', this.connectionText)
        }
        .alignItems(HorizontalAlign.Start)
        .height('100%')
        .width('100%')
      } else {
        Column() {
          this.panelTitle('Usage 上下文', '当前统计口径与最近状态')
          this.infoRow('会话数', this.workspaces.length.toString())
          this.infoRow('消息总数', this.messages.length.toString())
          this.infoRow('Diff 行数', this.codeLines.length.toString())
          this.infoRow('连接状态', this.connectionText)
          this.infoRow('当前 Provider', this.providerStatusText)
        }
        .alignItems(HorizontalAlign.Start)
        .height('100%')
        .width('100%')
      }
    }
    .height('100%')
    .width(this.rightPanelWidth)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#EEF2F7')

      Row() {
        this.leftPanel()
        this.splitterBar(true)
        this.centerPanel()
        this.splitterBar(false)
        this.rightPanel()
      }
      .width('100%')
      .height('100%')
      .padding(10)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const newW = newValue.width as number;
        if (newW > 0 && this.rowContainerWidth !== newW) {
          if (this.rowContainerWidth > 0) {
            const scale = newW / this.rowContainerWidth;
            this.leftPanelWidth = Math.max(this.panelMinWidth, this.leftPanelWidth * scale);
            this.rightPanelWidth = Math.max(this.panelMinWidth, this.rightPanelWidth * scale);
          }
          this.rowContainerWidth = newW;
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
