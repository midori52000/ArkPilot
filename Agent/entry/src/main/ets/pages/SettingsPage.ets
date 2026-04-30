import router from '@ohos.router';
import { codexBackend } from '../backend/CodexBackend';
import { getEmbeddedCodexProviderConfig, CodexProviderConfig } from '../backend/CodexHostNative';
import { providerCatalogService } from '../backend/ProviderCatalogService';
import { McpServerRecord, ProviderRecord, SettingsTab } from '../backend/ConsoleModels';

@Entry
@Component
struct SettingsPage {
  @State private activeTab: SettingsTab = 'mcp';

  // MCP state
  @State private mcpServers: McpServerRecord[] = [];
  @State private selectedMcpServerId: string = '';
  @State private mcpStatusText: string = '尚未加载 MCP 状态';
  @State private mcpErrorText: string = '';
  @State private isMcpReloading: boolean = false;
  @State private isMcpSaving: boolean = false;
  @State private mcpTransportTypeDraft: string = 'stdio';
  @State private mcpCommandDraft: string = '';
  @State private mcpArgsDraft: string = '[]';
  @State private mcpUrlDraft: string = '';
  @State private mcpEnvDraft: string = '{}';
  @State private mcpEnabledDraft: boolean = true;

  // Provider state
  @State private providers: ProviderRecord[] = [];
  @State private activeProviderId: string = '';
  @State private selectedProviderId: string = '';
  @State private providerNameDraft: string = '';
  @State private providerBaseUrl: string = '';
  @State private providerApiKey: string = '';
  @State private manualModel: string = '';
  @State private isSavingProvider: boolean = false;

  aboutToAppear(): void {
    this.loadProviderCatalog();
    void this.refreshMcpPanel();
  }

  // ── Helpers ──

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }

  private maskApiKey(apiKey: string): string {
    const trimmed: string = apiKey.trim();
    if (trimmed.length === 0) {
      return '未配置';
    }
    if (trimmed.length <= 8) {
      return '已配置';
    }
    return `${trimmed.slice(0, 4)}...${trimmed.slice(trimmed.length - 4)}`;
  }

  // ── MCP methods ──

  private hasMcpServer(serverId: string): boolean {
    if (serverId.length === 0) {
      return false;
    }
    for (let index: number = 0; index < this.mcpServers.length; index += 1) {
      if (this.mcpServers[index].id === serverId) {
        return true;
      }
    }
    return false;
  }

  private selectedMcpServer(): McpServerRecord | null {
    for (let index: number = 0; index < this.mcpServers.length; index += 1) {
      if (this.mcpServers[index].id === this.selectedMcpServerId) {
        return this.mcpServers[index];
      }
    }
    return null;
  }

  private loadMcpDraft(serverId: string): void {
    for (let index: number = 0; index < this.mcpServers.length; index += 1) {
      const server: McpServerRecord = this.mcpServers[index];
      if (server.id !== serverId) {
        continue;
      }
      this.selectedMcpServerId = server.id;
      this.mcpTransportTypeDraft = server.transportType;
      this.mcpCommandDraft = server.command;
      this.mcpArgsDraft = server.argsText.trim().length > 0 ? server.argsText : '[]';
      this.mcpUrlDraft = server.url;
      this.mcpEnvDraft = server.envText.trim().length > 0 ? server.envText : '{}';
      this.mcpEnabledDraft = server.enabled;
      return;
    }
  }

  private resetMcpDraft(): void {
    this.selectedMcpServerId = '';
    this.mcpTransportTypeDraft = 'stdio';
    this.mcpCommandDraft = '';
    this.mcpArgsDraft = '[]';
    this.mcpUrlDraft = '';
    this.mcpEnvDraft = '{}';
    this.mcpEnabledDraft = true;
  }

  private async refreshMcpPanel(): Promise<void> {
    try {
      this.mcpServers = await codexBackend.refreshMcpServers();
      if (!this.hasMcpServer(this.selectedMcpServerId)) {
        this.selectedMcpServerId = this.mcpServers.length > 0 ? this.mcpServers[0].id : '';
      }
      if (this.selectedMcpServerId.length > 0) {
        this.loadMcpDraft(this.selectedMcpServerId);
      } else {
        this.resetMcpDraft();
      }
      this.mcpErrorText = '';
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
      if (this.mcpServers.length === 0) {
        this.resetMcpDraft();
      }
    }
  }

  private async saveMcpDraft(): Promise<void> {
    if (this.isMcpSaving || this.selectedMcpServerId.length === 0) {
      return;
    }
    this.isMcpSaving = true;
    try {
      await codexBackend.saveMcpServerConfig(
        this.selectedMcpServerId,
        this.mcpEnabledDraft,
        this.mcpTransportTypeDraft,
        this.mcpCommandDraft,
        this.mcpArgsDraft,
        this.mcpUrlDraft,
        this.mcpEnvDraft
      );
      this.mcpServers = codexBackend.mcpServers();
      this.loadMcpDraft(this.selectedMcpServerId);
      this.mcpStatusText = `MCP server ${this.selectedMcpServerId} 已保存并重载`;
      this.mcpErrorText = '';
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    } finally {
      this.isMcpSaving = false;
    }
  }

  private async reloadMcp(): Promise<void> {
    if (this.isMcpReloading) {
      return;
    }
    this.isMcpReloading = true;
    try {
      await codexBackend.reloadMcpServers();
      this.mcpServers = codexBackend.mcpServers();
      if (this.selectedMcpServerId.length > 0) {
        this.loadMcpDraft(this.selectedMcpServerId);
      }
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    } finally {
      this.isMcpReloading = false;
    }
  }

  private async loginMcpOAuth(serverId: string): Promise<void> {
    try {
      await codexBackend.startMcpOAuthLogin(serverId);
      this.mcpStatusText = `已为 ${serverId} 发起 OAuth 登录，请在外部完成授权后刷新状态。`;
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    }
  }

  // ── Provider methods ──

  private hasProvider(providerId: string): boolean {
    if (providerId.length === 0) {
      return false;
    }
    for (let index: number = 0; index < this.providers.length; index += 1) {
      if (this.providers[index].id === providerId) {
        return true;
      }
    }
    return false;
  }

  private activeProvider(): ProviderRecord | null {
    for (let index: number = 0; index < this.providers.length; index += 1) {
      const provider: ProviderRecord = this.providers[index];
      if (provider.id === this.activeProviderId || provider.isActive) {
        return provider;
      }
    }
    return null;
  }

  private selectedProvider(): ProviderRecord | null {
    for (let index: number = 0; index < this.providers.length; index += 1) {
      if (this.providers[index].id === this.selectedProviderId) {
        return this.providers[index];
      }
    }
    return null;
  }

  private loadProviderCatalog(): void {
    const catalog = providerCatalogService.load();
    this.providers = catalog.providers;
    this.activeProviderId = catalog.activeProviderId;
    if (!this.hasProvider(this.selectedProviderId)) {
      this.selectedProviderId = this.activeProviderId.length > 0
        ? this.activeProviderId
        : (this.providers.length > 0 ? this.providers[0].id : '');
    }
    if (this.selectedProviderId.length > 0) {
      this.loadProviderDraft(this.selectedProviderId);
    }
  }

  private loadProviderDraft(providerId: string): void {
    for (let index: number = 0; index < this.providers.length; index += 1) {
      const provider: ProviderRecord = this.providers[index];
      if (provider.id !== providerId) {
        continue;
      }
      this.selectedProviderId = provider.id;
      this.providerNameDraft = provider.name;
      this.providerBaseUrl = provider.baseUrl;
      this.providerApiKey = provider.apiKey;
      this.manualModel = provider.model;
      return;
    }
  }

  private startCreatingProvider(): void {
    this.selectedProviderId = '';
    this.providerNameDraft = '';
    this.providerBaseUrl = 'https://api.openai.com/v1';
    this.providerApiKey = '';
    this.manualModel = '';
  }

  private async importLiveProvider(): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }
    this.isSavingProvider = true;
    try {
      const catalog = providerCatalogService.importCurrentProvider();
      this.providers = catalog.providers;
      this.activeProviderId = catalog.activeProviderId;
      this.selectedProviderId = catalog.activeProviderId;
      this.loadProviderDraft(this.selectedProviderId);
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    } finally {
      this.isSavingProvider = false;
    }
  }

  private async saveProviderDraft(): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }
    this.isSavingProvider = true;
    try {
      const isEditing: boolean = this.selectedProviderId.length > 0;
      const name: string = this.providerNameDraft.trim();
      const baseUrl: string = this.providerBaseUrl.trim();
      const apiKey: string = this.providerApiKey.trim();
      const model: string = this.manualModel.trim();
      const catalog = isEditing
        ? providerCatalogService.updateProvider(this.selectedProviderId, name, baseUrl, apiKey, model)
        : providerCatalogService.addProvider(name, baseUrl, apiKey, model);
      this.providers = catalog.providers;
      this.activeProviderId = catalog.activeProviderId;
      if (!isEditing && this.providers.length > 0) {
        this.selectedProviderId = this.providers[this.providers.length - 1].id;
      }
      this.loadProviderDraft(this.selectedProviderId);
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    } finally {
      this.isSavingProvider = false;
    }
  }

  private async activateProvider(providerId: string): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }
    this.isSavingProvider = true;
    try {
      const catalog = providerCatalogService.activateProvider(providerId);
      this.providers = catalog.providers;
      this.activeProviderId = catalog.activeProviderId;
      this.selectedProviderId = providerId;
      this.loadProviderDraft(providerId);
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    } finally {
      this.isSavingProvider = false;
    }
  }

  private async removeProvider(providerId: string): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }
    this.isSavingProvider = true;
    try {
      const catalog = providerCatalogService.removeProvider(providerId);
      this.providers = catalog.providers;
      this.activeProviderId = catalog.activeProviderId;
      this.selectedProviderId = this.activeProviderId.length > 0
        ? this.activeProviderId
        : (this.providers.length > 0 ? this.providers[0].id : '');
      if (this.selectedProviderId.length > 0) {
        this.loadProviderDraft(this.selectedProviderId);
      } else {
        this.startCreatingProvider();
      }
    } catch (err) {
      this.mcpErrorText = this.describeError(err);
    } finally {
      this.isSavingProvider = false;
    }
  }

  private providerEditorButtonLabel(): string {
    if (this.isSavingProvider) {
      return '处理中...';
    }
    if (this.selectedProviderId.length > 0) {
      return '更新 Provider';
    }
    return '创建 Provider';
  }

  // ── Builder helpers ──

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

  // ── Tab bar ──

  @Builder
  private tabBar() {
    Row() {
      this.tabChip('MCP', 'mcp')
      this.tabChip('Skills', 'skills')
      this.tabChip('Prompts', 'prompts')
      this.tabChip('API', 'api')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(16)
    .margin({ top: 8 })
  }

  @Builder
  private tabChip(label: string, tab: SettingsTab) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.activeTab === tab ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.activeTab === tab ? '#1D4ED8' : '#64748B')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.activeTab === tab ? '#EEF4FF' : '#FFFFFF')
      .border({ width: 1, color: this.activeTab === tab ? '#BFDBFE' : '#E5E7EB' })
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        this.activeTab = tab;
      })
  }

  // ── MCP views ──

  @Builder
  private mcpServerRow(server: McpServerRecord) {
    Column() {
      Row() {
        Column() {
          Text(server.name)
            .fontSize(12)
            .fontWeight(server.id === this.selectedMcpServerId ? FontWeight.Medium : FontWeight.Regular)
            .fontColor('#0F172A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${server.transportType} · tools ${server.toolCount} · resources ${server.resourceCount}`)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        this.chip(server.enabled ? 'enabled' : 'disabled', server.enabled ? '#DCFCE7' : '#F8FAFC', server.enabled ? '#166534' : '#64748B')
      }
      .width('100%')

      Row() {
        this.chip(server.healthStatus, '#EEF4FF', '#1D4ED8')
        this.chip(server.authStatus, '#FFF7ED', '#C2410C')
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor(server.id === this.selectedMcpServerId ? '#F8FAFF' : '#FFFFFF')
    .border({ width: 1, color: server.id === this.selectedMcpServerId ? '#BFDBFE' : '#E5E7EB' })
    .borderRadius(16)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.loadMcpDraft(server.id);
    })
  }

  @Builder
  private mcpTab() {
    Column() {
      Row() {
        this.panelTitle('MCP', '统一管理当前用户 config.toml 中的 MCP servers')

        Blank()
          .layoutWeight(1)

        Button('刷新状态')
          .height(34)
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(16)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            void this.refreshMcpPanel();
          })

        Button('重载 MCP')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => {
            void this.reloadMcp();
          })
      }
      .width('100%')

      Text(this.mcpStatusText)
        .fontSize(12)
        .fontColor('#334155')
        .lineHeight(20)
        .margin({ top: 10, bottom: 8 })

      if (this.mcpErrorText.trim().length > 0) {
        Text(this.mcpErrorText)
          .fontSize(11)
          .fontColor('#B91C1C')
          .lineHeight(18)
          .margin({ bottom: 8 })
      }

      if (this.mcpServers.length > 0) {
        List({ space: 0 }) {
          ForEach(this.mcpServers, (server: McpServerRecord) => {
            ListItem() {
              this.mcpServerRow(server)
            }
          }, (server: McpServerRecord) => server.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      } else {
        Column() {
          Text('当前没有已配置的 MCP server。')
            .fontSize(12)
            .fontColor('#334155')

          Text('请先在用户 config.toml 中添加 mcp_servers，再回到这里刷新状态。')
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(18)
      }

      if (this.mcpServers.length > 0 && this.selectedMcpServerId.length > 0) {
        Column() {
          this.panelTitle('编辑 MCP Server', '支持 enabled、transport、command/url、args 和 env 的基础编辑')

          TextInput({ text: this.mcpTransportTypeDraft, placeholder: 'stdio / http' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.mcpTransportTypeDraft = value.trim().toLowerCase();
            })

          TextInput({ text: this.mcpEnabledDraft ? 'true' : 'false', placeholder: 'true / false' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.mcpEnabledDraft = value.trim().toLowerCase() !== 'false';
            })

          TextInput({ text: this.mcpCommandDraft, placeholder: 'stdio transport command' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.mcpCommandDraft = value;
            })

          TextInput({ text: this.mcpArgsDraft, placeholder: '["arg1", "arg2"]' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.mcpArgsDraft = value;
            })

          TextInput({ text: this.mcpUrlDraft, placeholder: 'http transport url' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.mcpUrlDraft = value;
            })

          TextInput({ text: this.mcpEnvDraft, placeholder: '{"KEY":"VALUE"}' })
            .width('100%')
            .height(38)
            .margin({ top: 10 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.mcpEnvDraft = value;
            })

          Row() {
            Button('保存并重载')
              .height(34)
              .fontSize(12)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                void this.saveMcpDraft();
              })

            Button('发起 OAuth 登录')
              .height(34)
              .margin({ left: 8 })
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .fontColor('#334155')
              .borderRadius(16)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                if (this.selectedMcpServerId.length > 0) {
                  void this.loginMcpOAuth(this.selectedMcpServerId);
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(14)
        .margin({ top: 10 })
        .backgroundColor('#F8FAFC')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(18)
        .flexShrink(0)
      }
    }
    .height('100%')
    .width('100%')
  }

  // ── Provider views ──

  @Builder
  private providerRow(provider: ProviderRecord) {
    Column() {
      Row() {
        Column() {
          Text(provider.name)
            .fontSize(12)
            .fontWeight(provider.id === this.selectedProviderId ? FontWeight.Medium : FontWeight.Regular)
            .fontColor('#0F172A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${provider.baseUrl.trim().length > 0 ? provider.baseUrl : 'default base_url'} · ${provider.model.trim().length > 0 ? provider.model : 'default model'}`)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (provider.isActive) {
          this.chip('当前', '#DCFCE7', '#166534')
        } else {
          this.chip(provider.syncStatus, '#F8FAFC', '#64748B')
        }
      }
      .width('100%')

      Row() {
        Button('编辑')
          .height(30)
          .fontSize(11)
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(14)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            this.loadProviderDraft(provider.id);
          })

        Button(provider.isActive ? '已启用' : '设为当前')
          .height(30)
          .margin({ left: 8 })
          .fontSize(11)
          .backgroundColor(provider.isActive ? '#DBEAFE' : '#111827')
          .fontColor(provider.isActive ? '#1D4ED8' : '#FFFFFF')
          .borderRadius(14)
          .onClick(() => {
            if (provider.isActive === false) {
              void this.activateProvider(provider.id);
            }
          })

        Button('删除')
          .height(30)
          .margin({ left: 8 })
          .fontSize(11)
          .backgroundColor('#FFFFFF')
          .fontColor('#B91C1C')
          .borderRadius(14)
          .border({ width: 1, color: '#FECACA' })
          .onClick(() => {
            void this.removeProvider(provider.id);
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor(provider.id === this.selectedProviderId ? '#F8FAFF' : '#FFFFFF')
    .border({ width: 1, color: provider.id === this.selectedProviderId ? '#BFDBFE' : '#E5E7EB' })
    .borderRadius(16)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.loadProviderDraft(provider.id);
    })
  }

  @Builder
  private apiTab() {
    Column() {
      Row() {
        this.panelTitle('API', '统一管理和切换 Provider')

        Blank()
          .layoutWeight(1)

        this.chip(`${this.providers.length} 个`, '#EEF4FF', '#1D4ED8')
      }
      .width('100%')

      Row() {
        Button('导入当前 Live Provider')
          .height(34)
          .fontSize(12)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => {
            void this.importLiveProvider();
          })

        Button('新建 Provider')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(16)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            this.startCreatingProvider();
          })
      }
      .width('100%')
      .margin({ top: 10 })

      List({ space: 0 }) {
        ForEach(this.providers, (provider: ProviderRecord) => {
          ListItem() {
            this.providerRow(provider)
          }
        }, (provider: ProviderRecord) => provider.id)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 10 })
      .scrollBar(BarState.Off)

      Column() {
        this.panelTitle(this.selectedProviderId.length > 0 ? '编辑 Provider' : '创建 Provider', 'Provider 目录是事实源，设为当前时同步到 live config')

        TextInput({ text: this.providerNameDraft, placeholder: '例如 OpenRouter / 公司网关 / 本地代理' })
          .width('100%')
          .height(38)
          .margin({ top: 10 })
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.providerNameDraft = value;
          })

        TextInput({ text: this.providerBaseUrl, placeholder: 'https://api.openai.com/v1' })
          .width('100%')
          .height(38)
          .margin({ top: 10 })
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.providerBaseUrl = value;
          })

        TextInput({ text: this.providerApiKey, placeholder: 'sk-...' })
          .width('100%')
          .height(38)
          .margin({ top: 10 })
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.providerApiKey = value;
          })

        TextInput({ text: this.manualModel, placeholder: 'gpt-5.5 / claude-opus / custom model id' })
          .width('100%')
          .height(38)
          .margin({ top: 10 })
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.manualModel = value;
          })

        Row() {
          Button(this.providerEditorButtonLabel())
            .height(34)
            .fontSize(12)
            .backgroundColor('#111827')
            .fontColor('#FFFFFF')
            .borderRadius(16)
            .onClick(() => {
              void this.saveProviderDraft();
            })

          Button('清空编辑器')
            .height(34)
            .margin({ left: 8 })
            .fontSize(12)
            .backgroundColor('#FFFFFF')
            .fontColor('#334155')
            .borderRadius(16)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => {
              this.startCreatingProvider();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .margin({ top: 10 })
      .backgroundColor('#F8FAFC')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(18)
      .flexShrink(0)
    }
    .height('100%')
    .width('100%')
  }

  // ── Placeholder tabs ──

  @Builder
  private skillsTab() {
    Column() {
      this.panelTitle('Skills', '统一技能安装与启停将在后续阶段接入')

      Text('这一块将提供统一的技能管理入口。')
        .fontSize(12)
        .fontColor('#334155')
        .lineHeight(20)
        .margin({ top: 14 })

      Column() {
        this.summaryBullet('安装、启用、禁用技能。')
        this.summaryBullet('搜索和筛选可用技能。')
        this.summaryBullet('技能配置同步到 config.toml。')
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(18)
  }

  @Builder
  private promptsTab() {
    Column() {
      this.panelTitle('Prompts', '统一提示词编辑与同步将在后续阶段接入')

      Text('这一块将提供统一的提示词管理入口。')
        .fontSize(12)
        .fontColor('#334155')
        .lineHeight(20)
        .margin({ top: 14 })

      Column() {
        this.summaryBullet('创建和编辑自定义提示词。')
        this.summaryBullet('提示词模板管理。')
        this.summaryBullet('提示词同步到 config.toml。')
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(18)
  }

  build() {
    Column() {
      // Top bar
      Row() {
        Button() {
          Text('< 返回')
            .fontSize(13)
            .fontColor('#334155')
        }
        .height(34)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .border({ width: 1, color: '#CBD5E1' })
        .onClick(() => {
          router.back();
        })

        Blank()
          .layoutWeight(1)

        Text('Settings')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
      }
      .width('100%')

      // Tab bar
      this.tabBar()

      // Content
      if (this.activeTab === 'mcp') {
        this.mcpTab()
      } else if (this.activeTab === 'skills') {
        this.skillsTab()
      } else if (this.activeTab === 'prompts') {
        this.promptsTab()
      } else {
        this.apiTab()
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#EEF2F7')
  }
}
