import {
  codexBackend,
  CodexApprovalRequest,
  CodexBackendSnapshot,
  CodexConnectionState,
  CodexDiffLine,
  CodexTurnRequest,
  CodexTurnResult
} from '../backend/CodexBackend';
import { getEmbeddedCodexHostStatus } from '../backend/CodexHostNative';

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
  private readonly modelOptions: SelectorOption[] = [
    new SelectorOption('默认', 'default'),
    new SelectorOption('gpt-5.5', 'gpt-5.5'),
    new SelectorOption('gpt-5.4', 'gpt-5.4'),
    new SelectorOption('gpt-5.4-mini', 'gpt-5.4-mini'),
    new SelectorOption('gpt-5.3-codex', 'gpt-5.3-codex'),
    new SelectorOption('gpt-5.2', 'gpt-5.2')
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

  @State private activeWorkspaceId: number = 1;
  @State private selectedModelIndex: number = 0;
  @State private selectedEffortIndex: number = 0;
  @State private showModelOptions: boolean = false;
  @State private showEffortOptions: boolean = false;
  @State private serverUrl: string = 'ws://127.0.0.1:7456';
  @State private workspaceRoot: string = '';
  @State private connectionState: CodexConnectionState = 'disconnected';
  @State private connectionText: string = '未连接';
  @State private summaryTitle: string = '等待连接真实 app-server';
  @State private summaryPoints: string[] = [
    '应用启动时会自动拉起内置 Rust codex app-server。',
    '这里通过本机 WebSocket JSON-RPC 连接进程内后端，而不是本地 mock。',
    '发送消息后会流式刷新对话、计划和 diff。'
  ];
  @State private changedFiles: string = '尚未产生文件改动';
  @State private diffStat: string = '+0 -0';
  @State private isRunning: boolean = false;
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
    this.scheduleEmbeddedHostReconnect(0);
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
        '页面会自动尝试连接本地 WebSocket 服务。',
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
    return this.modelOptions[this.selectedModelIndex].label;
  }

  private currentModelValue(): string {
    return this.modelOptions[this.selectedModelIndex].value;
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
      this.summaryPoints = [JSON.stringify(err)];
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
  }

  private async connectOrDisconnect(): Promise<void> {
    codexBackend.configureServerUrl(this.serverUrl);
    if (this.connectionState === 'connected' || this.connectionState === 'connecting') {
      await codexBackend.disconnect();
      return;
    }

    try {
      await codexBackend.connect();
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
      this.summaryPoints = [JSON.stringify(err)];
    }
  }

  private async connectEmbeddedHost(): Promise<void> {
    if (this.connectionState === 'connected' || this.connectionState === 'connecting') {
      return;
    }

    try {
      codexBackend.configureServerUrl(this.serverUrl);
      await codexBackend.connect();
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
        JSON.stringify(err),
        `ç³»ç»Ÿå°†åœ¨ ${retryDelayMs} ms åŽè‡ªåŠ¨é‡è¯•è¿žæŽ¥ã€‚`,
        '可以点击连接按钮重试，或者检查 native 日志。'
      ];
      this.scheduleEmbeddedHostReconnect(retryDelayMs);
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
    this.draft = `继续处理“${item.title}”，重点关注当前工作目录。`;
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
  private leftPanel() {
    Column() {
      Row() {
        Column() {
          Text('Codex')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text('Harmony app-server client')
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
        this.panelTitle('连接', '配置真实 codex app-server 的 WebSocket 地址')

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
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .margin({ top: 12 })
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)

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
      .margin({ top: 14, bottom: 8 })

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
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)
    }
    .height('100%')
    .layoutWeight(24)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
  }

  @Builder
  private centerPanel() {
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

      List({ space: 8 }) {
        ForEach(this.messages, (item: ChatMessage) => {
          ListItem() {
            this.messageCard(item)
          }
        }, (item: ChatMessage) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 10 })
      .scrollBar(BarState.Off)

      Column() {
        Row() {
          this.selectorButton('模型', this.currentModelLabel(), this.showModelOptions, () => {
            this.showModelOptions = !this.showModelOptions;
            this.showEffortOptions = false;
          })

          Blank()
            .width(8)

          this.selectorButton('推理', this.currentEffortLabel(), this.showEffortOptions, () => {
            this.showEffortOptions = !this.showEffortOptions;
            this.showModelOptions = false;
          })
        }
        .width('100%')

        if (this.showModelOptions) {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(this.modelOptions, (item: SelectorOption, index: number) => {
              this.optionChip(item, this.selectedModelIndex === index, () => {
                this.selectedModelIndex = index;
                this.showModelOptions = false;
              })
            })
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
    .layoutWeight(43)
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(20)
    .margin({ left: 8, right: 8 })
  }

  @Builder
  private rightPanel() {
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
    .layoutWeight(33)
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
        this.centerPanel()
        this.rightPanel()
      }
      .width('100%')
      .height('100%')
      .padding(10)
    }
    .width('100%')
    .height('100%')
  }
}
