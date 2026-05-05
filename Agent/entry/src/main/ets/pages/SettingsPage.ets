import router from '@ohos.router';
import { McpServerRecord, SettingsTab, ProviderRecord, ProviderCategory, ApiWireFormat } from '../backend/ConsoleModels';
import { codexBackend } from '../backend/CodexBackend';
import { BUILTIN_PROVIDER_PRESETS, EndpointSpeedResult, ChatProbeResult } from '../apim/ApiTypes';
import { apiManagementVM } from '../apim/ApiManagementViewModel';
import { InstalledSkill, SkillRepo, SkillBackupEntry } from '../skills/SkillTypes';
import { skillsVM } from '../skills/SkillsViewModel';
import { PromptsViewModel } from '../prompts/PromptsViewModel';
import { PromptsBackendService } from '../prompts/PromptsBackendService';
import { PromptRecord } from '../prompts/PromptTypes';

type ToastTone = 'info' | 'success' | 'warning' | 'error';
type SkillsSubTab = 'installed' | 'repos' | 'backups';
type ApiSubTab = 'providers' | 'presets';

class SettingsNavItem {
  tab: SettingsTab;
  label: string;
  subtitle: string;
  accent: string;

  constructor(tab: SettingsTab, label: string, subtitle: string, accent: string) {
    this.tab = tab;
    this.label = label;
    this.subtitle = subtitle;
    this.accent = accent;
  }
}

class UiToastItem {
  id: number;
  tone: ToastTone;
  message: string;

  constructor(id: number, tone: ToastTone, message: string) {
    this.id = id;
    this.tone = tone;
    this.message = message;
  }
}

class ApiEndpointMockItem {
  label: string;
  value: string;
  status: string;

  constructor(label: string, value: string, status: string) {
    this.label = label;
    this.value = value;
    this.status = status;
  }
}

class ApiPresetMockItem {
  id: string;
  name: string;
  category: ProviderCategory;
  wireApi: string;
  baseUrl: string;
  description: string;
  websiteUrl: string;
  accent: string;

  constructor(
    id: string,
    name: string,
    category: ProviderCategory,
    wireApi: string,
    baseUrl: string,
    description: string,
    websiteUrl: string,
    accent: string
  ) {
    this.id = id;
    this.name = name;
    this.category = category;
    this.wireApi = wireApi;
    this.baseUrl = baseUrl;
    this.description = description;
    this.websiteUrl = websiteUrl;
    this.accent = accent;
  }
}

@Entry
@Component
struct SettingsPage {
  private readonly navItems: SettingsNavItem[] = [
    new SettingsNavItem('api', 'API', 'Provider 与模型接入', '#8B5CF6'),
    new SettingsNavItem('skills', 'Skills', '能力包与仓库源', '#14B8A6'),
    new SettingsNavItem('prompts', 'Prompts', '预设指令与工作约束', '#F59E0B'),
    new SettingsNavItem('mcp', 'MCP', '桥接与工具通道', '#0A84FF')
  ];

  @State private activeTab: SettingsTab = 'api';
  @State private pressedKey: string = '';
  @State private sparkSeed: number = 0;
  @State private toasts: UiToastItem[] = [];
  @State private toastIdSeed: number = 1;

  @State private mcpServers: McpServerRecord[] = [];
  @State private selectedMcpServerId: string = '';
  @State private mcpTransportTypeDraft: string = 'stdio';
  @State private mcpCommandDraft: string = '';
  @State private mcpArgsDraft: string = '[]';
  @State private mcpUrlDraft: string = '';
  @State private mcpEnvDraft: string = '{}';
  @State private mcpEnabledDraft: boolean = true;
  @State private mcpStatusText: string = '等待 MCP backend 加载状态。';
  @State private mcpNewServerName: string = '';
  @State private showMcpAddDialog: boolean = false;
  @State private showMcpDeleteDialog: boolean = false;
  @State private pendingDeleteMcpName: string = '';

  @State private installedSkills: InstalledSkill[] = [];
  @State private skillRepos: SkillRepo[] = [];
  @State private skillBackups: SkillBackupEntry[] = [];
  @State private skillsActiveSubTab: SkillsSubTab = 'installed';
  @State private newRepoOwner: string = 'anthropics';
  @State private newRepoName: string = 'skills';
  @State private newRepoBranch: string = 'main';
  @State private skillsStatusText: string = '等待 Skills façade 加载状态。';
  @State private pendingDeleteSkillId: string = '';
  @State private pendingDeleteSkillName: string = '';
  @State private showSkillDeleteDialog: boolean = false;
  @State private showSkillDetailDialog: boolean = false;
  @State private selectedSkillDetail: InstalledSkill | null = null;

  @State private promptsViewModel: PromptsViewModel = new PromptsViewModel(new PromptsBackendService(''));
  @State private prompts: PromptRecord[] = [];
  @State private selectedPromptId: string = '';
  @State private promptDraftName: string = '';
  @State private promptDraftSummary: string = '';
  @State private promptDraftContent: string = '';
  @State private promptLiveContent: string = '';
  @State private promptsStatusText: string = '等待 Prompts façade 加载状态。';

  @State private apiProviderName: string = 'OpenAI Gateway';
  @State private apiBaseUrl: string = 'https://api.openai.com/v1';
  @State private apiModel: string = 'gpt-5.1';
  @State private apiWireApi: ApiWireFormat = 'responses';
  @State private apiAuthState: string = 'sk-live-************************';
  @State private apiEndpoints: ApiEndpointMockItem[] = [];
  @State private apiProviders: ProviderRecord[] = [];
  @State private apiPresets: ApiPresetMockItem[] = [];
  @State private apiActiveSubTab: ApiSubTab = 'providers';
  @State private selectedApiProviderId: string = '';
  @State private apiEditorExpanded: boolean = false;
  @State private apiPresetCategory: string = 'all';
  @State private apiSpeedTesting: boolean = false;
  @State private apiSpeedResults: EndpointSpeedResult[] = [];
  @State private apiShowSpeedResults: boolean = false;
  @State private dragTargetName: string = '';
  @State private dragFromIndex: number = -1;
  @State private dragOverIndex: number = -1;
  private dragStartY: number = 0;
  private dragStartIndex: number = -1;
  private dragDownTime: number = 0;
  private dragMoved: boolean = false;
  private readonly CARD_HEIGHT_ESTIMATE: number = 76;
  private readonly LONG_PRESS_MS: number = 500;

  aboutToAppear(): void {
    this.loadMockData();
    const codexHome: string = (AppStorage.get('codexHome') as string) ?? '';
    if (codexHome.length > 0) {
      this.promptsViewModel = new PromptsViewModel(new PromptsBackendService(codexHome));
    }
    this.syncMcpStateFromBackend();
    this.syncApiStateFromViewModel();
    this.syncSkillsStateFromViewModel();
    this.syncPromptsStateFromViewModel();
    this.loadSettingsFacadeState();
  }

  onPageShow(): void {
    apiManagementVM.loadProviders();
    this.syncApiStateFromViewModel();
    this.syncSkillsStateFromViewModel();
    this.syncPromptsStateFromViewModel();
  }

  private loadMockData(): void {
    const presets: ApiPresetMockItem[] = [];
    for (let index = 0; index < BUILTIN_PROVIDER_PRESETS.length; index += 1) {
      const preset = BUILTIN_PROVIDER_PRESETS[index];
      presets.push(new ApiPresetMockItem(
        preset.id,
        preset.name,
        preset.category,
        preset.wireApi,
        preset.baseUrl,
        preset.description,
        preset.websiteUrl,
        preset.iconColor.length > 0 ? preset.iconColor : '#8B5CF6'
      ));
    }
    this.apiPresets = presets;
  }

  private loadMcpDraft(serverId: string): void {
    for (let index = 0; index < this.mcpServers.length; index += 1) {
      const server = this.mcpServers[index];
      if (server.id !== serverId) {
        continue;
      }
      this.applyMcpDraft(server);
      return;
    }
  }

  private applyMcpDraft(server: McpServerRecord): void {
    this.selectedMcpServerId = server.id;
    this.mcpTransportTypeDraft = server.transportType;
    this.mcpCommandDraft = server.command;
    this.mcpArgsDraft = server.argsText.trim().length > 0 ? server.argsText : '[]';
    this.mcpUrlDraft = server.url;
    this.mcpEnvDraft = server.envText.trim().length > 0 ? server.envText : '{}';
    this.mcpEnabledDraft = server.enabled;
  }

  private selectedMcpServer(): McpServerRecord | null {
    for (let index = 0; index < this.mcpServers.length; index += 1) {
      if (this.mcpServers[index].id === this.selectedMcpServerId) {
        return this.mcpServers[index];
      }
    }
    return null;
  }

  private selectedPrompt(): PromptRecord | null {
    for (let index = 0; index < this.prompts.length; index += 1) {
      if (this.prompts[index].id === this.selectedPromptId) {
        return this.prompts[index];
      }
    }
    return null;
  }

  private triggerFeedback(message: string, tone: ToastTone = 'info'): void {
    this.sparkSeed += 1;
    this.showToast(message, tone);
  }

  private syncApiStateFromViewModel(): void {
    this.apiProviders = [...apiManagementVM.state.providers];
    if (this.apiProviders.length === 0) {
      this.selectedApiProviderId = '';
      this.apiEditorExpanded = false;
      this.apiProviderName = '';
      this.apiBaseUrl = '';
      this.apiModel = '';
      this.apiWireApi = 'responses';
      this.apiAuthState = '';
      this.apiEndpoints = [];
      return;
    }
    const currentId = this.selectedApiProviderId.length > 0 ? this.selectedApiProviderId : this.apiProviders[0].id;
    this.syncApiDraftFromProvider(currentId);
  }

  private syncSkillsStateFromViewModel(): void {
    this.installedSkills = [...skillsVM.state.installed];
    this.skillRepos = [...skillsVM.state.repos];
    this.skillBackups = [...skillsVM.state.backups];
    if (skillsVM.state.statusText.trim().length > 0) {
      this.skillsStatusText = skillsVM.state.statusText;
    } else if (skillsVM.state.errorText.trim().length > 0) {
      this.skillsStatusText = skillsVM.state.errorText;
    }
  }

  private syncMcpStateFromBackend(): void {
    this.mcpServers = codexBackend.mcpServers();
    const snapshot = codexBackend.snapshot();
    this.mcpStatusText = snapshot.mcpErrorText.trim().length > 0
      ? snapshot.mcpErrorText
      : snapshot.mcpStatusText;
    if (this.mcpServers.length === 0) {
      this.selectedMcpServerId = '';
      this.mcpTransportTypeDraft = 'stdio';
      this.mcpCommandDraft = '';
      this.mcpArgsDraft = '[]';
      this.mcpUrlDraft = '';
      this.mcpEnvDraft = '{}';
      this.mcpEnabledDraft = true;
      return;
    }
    const hasCurrent = this.selectedMcpServerId.length > 0
      && this.mcpServers.some((server: McpServerRecord) => server.id === this.selectedMcpServerId);
    const nextId = hasCurrent ? this.selectedMcpServerId : this.mcpServers[0].id;
    const nextServer = this.mcpServers.find((server: McpServerRecord) => server.id === nextId);
    if (nextServer !== undefined) {
      this.applyMcpDraft(nextServer);
    }
  }

  private syncPromptsStateFromViewModel(): void {
    this.prompts = [...this.promptsViewModel.state.prompts];
    this.promptLiveContent = this.promptsViewModel.state.liveContent;
    if (this.prompts.length === 0) {
      this.selectedPromptId = '';
      this.promptDraftName = '';
      this.promptDraftSummary = '';
      this.promptDraftContent = '';
      this.promptsStatusText = this.promptLiveContent.trim().length > 0
        ? '当前 AGENTS.md 已有 live 内容。'
        : '当前还没有 Prompt。';
      return;
    }
    const hasCurrent = this.selectedPromptId.length > 0
      && this.prompts.some((prompt: PromptRecord) => prompt.id === this.selectedPromptId);
    const nextId = hasCurrent ? this.selectedPromptId : this.prompts[0].id;
    this.selectedPromptId = nextId;
    const prompt = this.selectedPrompt();
    if (prompt !== null) {
      this.promptDraftName = prompt.name;
      this.promptDraftSummary = prompt.description;
      this.promptDraftContent = prompt.content;
    }
    const activeName = this.promptsViewModel.activePromptName;
    this.promptsStatusText = activeName !== 'None'
      ? `当前启用：${activeName}`
      : (this.promptLiveContent.trim().length > 0 ? '当前仅存在 live 内容，未绑定启用 Prompt。' : '当前没有启用 Prompt。');
  }

  private loadSettingsFacadeState(): void {
    codexBackend.refreshMcpServers()
      .then(() => {
        this.syncMcpStateFromBackend();
      })
      .catch((err: Object) => {
        this.mcpStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.mcpStatusText, 'error');
      });
    apiManagementVM.loadProviders();
    this.syncApiStateFromViewModel();
    skillsVM.loadInstalled(true)
      .then(() => {
        this.syncSkillsStateFromViewModel();
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
    skillsVM.loadRepos()
      .then(() => {
        this.syncSkillsStateFromViewModel();
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
    skillsVM.loadBackups()
      .then(() => {
        this.syncSkillsStateFromViewModel();
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
    this.promptsViewModel.loadAll()
      .then(() => {
        this.syncPromptsStateFromViewModel();
      })
      .catch((err: Object) => {
        this.promptsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.promptsStatusText, 'error');
      });
  }

  private describeRuntimeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }

  private showToast(message: string, tone: ToastTone = 'info', duration: number = 1800): void {
    const toastId = this.toastIdSeed;
    this.toastIdSeed += 1;
    this.toasts = [...this.toasts, new UiToastItem(toastId, tone, message)];
    setTimeout(() => {
      this.dismissToast(toastId);
    }, duration);
  }

  private dismissToast(toastId: number): void {
    this.toasts = this.toasts.filter((toast: UiToastItem) => toast.id !== toastId);
  }

  private notePending(action: string): void {
    this.triggerFeedback(`${action}暂未接入后端，当前仅前端模拟。`, 'warning');
  }

  private updatePressed(key: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedKey = key;
      return;
    }
    if (this.pressedKey === key) {
      this.pressedKey = '';
    }
  }

  private pressScale(key: string): number {
    return this.pressedKey === key ? 0.98 : 1;
  }

  private tabAccent(tab: SettingsTab): string {
    switch (tab) {
      case 'mcp':
        return '#0A84FF';
      case 'skills':
        return '#14B8A6';
      case 'prompts':
        return '#F59E0B';
      default:
        return '#8B5CF6';
    }
  }

  private toneBackground(tone: ToastTone): string {
    switch (tone) {
      case 'success':
        return '#DCFCE7';
      case 'warning':
        return '#FEF3C7';
      case 'error':
        return '#FEE2E2';
      default:
        return '#E0F2FE';
    }
  }

  private toneColor(tone: ToastTone): string {
    switch (tone) {
      case 'success':
        return '#166534';
      case 'warning':
        return '#92400E';
      case 'error':
        return '#B91C1C';
      default:
        return '#0C4A6E';
    }
  }

  private statusChipBackground(status: string): string {
    switch (status) {
      case 'Healthy':
      case 'ok':
      case 'authenticated':
        return '#DCFCE7';
      case 'Standby':
      case 'pending':
      case 'required':
      case 'degraded':
      case 'warning':
        return '#FEF3C7';
      case 'Draft':
      case 'unknown':
        return '#E0F2FE';
      default:
        return '#F1F5F9';
    }
  }

  private statusChipColor(status: string): string {
    switch (status) {
      case 'Healthy':
      case 'ok':
      case 'authenticated':
        return '#166534';
      case 'Standby':
      case 'pending':
      case 'required':
      case 'degraded':
      case 'warning':
        return '#92400E';
      case 'Draft':
      case 'unknown':
        return '#0C4A6E';
      default:
        return '#475569';
    }
  }

  private authLabel(status: string): string {
    switch (status) {
      case 'notRequired':
        return 'No Auth';
      case 'required':
        return 'OAuth Required';
      case 'pending':
        return 'OAuth Pending';
      case 'authenticated':
        return 'Authenticated';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  private healthLabel(status: string): string {
    switch (status) {
      case 'ok':
        return 'Healthy';
      case 'warning':
        return 'No Tools';
      case 'degraded':
        return 'Attention';
      case 'error':
        return 'Error';
      default:
        return 'Draft';
    }
  }

  private formatTimestamp(ts: number): string {
    if (ts <= 0) {
      return '-';
    }
    return new Date(ts).toISOString().replace('T', ' ').substring(0, 19);
  }

  private selectTab(tab: SettingsTab): void {
    this.activeTab = tab;
    this.triggerFeedback(`已切换到 ${this.navLabel(tab)} 面板。`, 'info');
  }

  private navLabel(tab: SettingsTab): string {
    switch (tab) {
      case 'mcp':
        return 'MCP';
      case 'skills':
        return 'Skills';
      case 'prompts':
        return 'Prompts';
      default:
        return 'API';
    }
  }

  private saveMcpDraft(): void {
    const server = this.selectedMcpServer();
    if (server === null) {
      this.triggerFeedback('当前没有可保存的 MCP server。', 'warning');
      return;
    }
    codexBackend.saveMcpServerConfig(
      server.name,
      this.mcpEnabledDraft,
      this.mcpTransportTypeDraft,
      this.mcpCommandDraft,
      this.mcpArgsDraft,
      this.mcpUrlDraft,
      this.mcpEnvDraft
    )
      .then(() => {
        this.syncMcpStateFromBackend();
        this.triggerFeedback(`已保存 ${server.name} 的 MCP 配置。`, 'success');
      })
      .catch((err: Object) => {
        this.mcpStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.mcpStatusText, 'error');
      });
  }

  private revertMcpDraft(): void {
    const server = this.selectedMcpServer();
    if (server === null) {
      this.triggerFeedback('当前没有可还原的 MCP server。', 'warning');
      return;
    }
    this.loadMcpDraft(server.id);
    this.triggerFeedback(`已还原 ${server.name} 的草稿。`, 'info');
  }

  private reloadMcpDraft(): void {
    codexBackend.reloadMcpServers()
      .then(() => {
        this.syncMcpStateFromBackend();
        const server = this.selectedMcpServer();
        this.triggerFeedback(server !== null ? `${server.name} 已完成 MCP 重载。` : 'MCP 配置已重载。', 'info');
      })
      .catch((err: Object) => {
        this.mcpStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.mcpStatusText, 'error');
      });
  }

  private startSelectedMcpOauth(): void {
    const server = this.selectedMcpServer();
    if (server === null) {
      this.triggerFeedback('当前没有可登录的 MCP server。', 'warning');
      return;
    }
    codexBackend.startMcpOAuthLogin(server.name)
      .then(() => {
        this.syncMcpStateFromBackend();
        this.triggerFeedback(`已为 ${server.name} 发起 OAuth 登录。`, 'success');
      })
      .catch((err: Object) => {
        this.mcpStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.mcpStatusText, 'error');
      });
  }

  private openMcpAddDialog(): void {
    this.mcpNewServerName = '';
    this.showMcpAddDialog = true;
  }

  private cancelMcpAdd(): void {
    this.showMcpAddDialog = false;
    this.mcpNewServerName = '';
  }

  private confirmMcpAdd(): void {
    const name: string = this.mcpNewServerName.trim();
    if (name.length === 0) {
      this.triggerFeedback('server 名称不能为空。', 'warning');
      return;
    }
    for (let i: number = 0; i < this.mcpServers.length; i += 1) {
      if (this.mcpServers[i].name === name) {
        this.triggerFeedback('已存在同名 MCP server。', 'warning');
        return;
      }
    }
    codexBackend.addMcpServer(name, 'stdio', '', '[]', '', '{}')
      .then(() => {
        this.showMcpAddDialog = false;
        this.mcpNewServerName = '';
        this.syncMcpStateFromBackend();
        this.triggerFeedback(`已添加 MCP server: ${name}`, 'success');
      })
      .catch((err: Object) => {
        this.mcpStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.mcpStatusText, 'error');
      });
  }

  private openMcpDeleteDialog(): void {
    const server = this.selectedMcpServer();
    if (server === null) {
      this.triggerFeedback('当前没有可删除的 MCP server。', 'warning');
      return;
    }
    this.pendingDeleteMcpName = server.name;
    this.showMcpDeleteDialog = true;
  }

  private cancelMcpDelete(): void {
    this.showMcpDeleteDialog = false;
    this.pendingDeleteMcpName = '';
  }

  private confirmMcpDelete(): void {
    const name: string = this.pendingDeleteMcpName;
    this.cancelMcpDelete();
    if (name.length === 0) {
      return;
    }
    codexBackend.removeMcpServer(name)
      .then(() => {
        this.syncMcpStateFromBackend();
        this.triggerFeedback(`已删除 MCP server: ${name}`, 'success');
      })
      .catch((err: Object) => {
        this.mcpStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.mcpStatusText, 'error');
      });
  }

  private toggleSkillEnabled(skillId: string): void {
    let nextEnabled: boolean | null = null;
    for (let index = 0; index < this.installedSkills.length; index += 1) {
      if (this.installedSkills[index].id !== skillId) {
        continue;
      }
      nextEnabled = !this.installedSkills[index].enabled;
      break;
    }
    if (nextEnabled === null) {
      return;
    }
    skillsVM.toggleEnabled(skillId, nextEnabled)
      .then(() => {
        this.syncSkillsStateFromViewModel();
        this.skillsStatusText = skillsVM.state.errorText.trim().length > 0
          ? skillsVM.state.errorText
          : skillsVM.state.statusText;
        this.triggerFeedback(this.skillsStatusText, skillsVM.state.errorText.trim().length > 0 ? 'warning' : 'success');
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
  }

  private requestUninstallSkill(skillId: string): void {
    for (let index = 0; index < this.installedSkills.length; index += 1) {
      if (this.installedSkills[index].id !== skillId) {
        continue;
      }
      this.pendingDeleteSkillId = skillId;
      this.pendingDeleteSkillName = this.installedSkills[index].name;
      this.showSkillDeleteDialog = true;
      return;
    }
  }

  private cancelUninstallSkill(): void {
    this.showSkillDeleteDialog = false;
    this.pendingDeleteSkillId = '';
    this.pendingDeleteSkillName = '';
  }

  private confirmUninstallSkill(): void {
    const skillId = this.pendingDeleteSkillId;
    this.cancelUninstallSkill();
    if (skillId.length === 0) {
      return;
    }
    skillsVM.uninstall(skillId)
      .then(() => {
        this.syncSkillsStateFromViewModel();
        this.skillsStatusText = skillsVM.state.errorText.trim().length > 0
          ? skillsVM.state.errorText
          : skillsVM.state.statusText;
        this.triggerFeedback(this.skillsStatusText, skillsVM.state.errorText.trim().length > 0 ? 'warning' : 'success');
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
  }

  private showSkillDetail(skill: InstalledSkill): void {
    this.selectedSkillDetail = skill;
    this.showSkillDetailDialog = true;
  }

  private closeSkillDetail(): void {
    this.showSkillDetailDialog = false;
    this.selectedSkillDetail = null;
  }

  private addSkillRepo(): void {
    const owner = this.newRepoOwner.trim();
    const name = this.newRepoName.trim();
    const branch = this.newRepoBranch.trim().length > 0 ? this.newRepoBranch.trim() : 'main';
    if (owner.length === 0 || name.length === 0) {
      this.triggerFeedback('仓库 owner 与 name 不能为空。', 'error');
      return;
    }
    skillsVM.addRepo(new SkillRepo(owner, name, branch, true))
      .then(() => {
        this.syncSkillsStateFromViewModel();
        this.skillsStatusText = skillsVM.state.errorText.trim().length > 0
          ? skillsVM.state.errorText
          : skillsVM.state.statusText;
        this.triggerFeedback(this.skillsStatusText, skillsVM.state.errorText.trim().length > 0 ? 'warning' : 'success');
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
  }

  private toggleRepoEnabled(owner: string, name: string): void {
    let nextEnabled: boolean | null = null;
    for (let index = 0; index < this.skillRepos.length; index += 1) {
      const repo = this.skillRepos[index];
      if (repo.owner !== owner || repo.name !== name) {
        continue;
      }
      nextEnabled = !repo.enabled;
      break;
    }
    if (nextEnabled === null) {
      return;
    }
    skillsVM.toggleRepoEnabled(owner, name, nextEnabled)
      .then(() => {
        this.syncSkillsStateFromViewModel();
        this.skillsStatusText = skillsVM.state.errorText.trim().length > 0
          ? skillsVM.state.errorText
          : skillsVM.state.statusText;
        this.triggerFeedback(this.skillsStatusText, skillsVM.state.errorText.trim().length > 0 ? 'warning' : 'success');
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
  }

  private removeSkillRepo(owner: string, name: string): void {
    skillsVM.removeRepo(owner, name)
      .then(() => {
        this.syncSkillsStateFromViewModel();
        this.skillsStatusText = skillsVM.state.errorText.trim().length > 0
          ? skillsVM.state.errorText
          : skillsVM.state.statusText;
        this.triggerFeedback(this.skillsStatusText, skillsVM.state.errorText.trim().length > 0 ? 'warning' : 'success');
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
  }

  private removeSkillBackup(backupId: string): void {
    skillsVM.deleteBackup(backupId)
      .then(() => {
        this.syncSkillsStateFromViewModel();
        this.skillsStatusText = skillsVM.state.errorText.trim().length > 0
          ? skillsVM.state.errorText
          : skillsVM.state.statusText;
        this.triggerFeedback(this.skillsStatusText, skillsVM.state.errorText.trim().length > 0 ? 'warning' : 'success');
      })
      .catch((err: Object) => {
        this.skillsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.skillsStatusText, 'error');
      });
  }

  private selectPrompt(promptId: string): void {
    this.selectedPromptId = promptId;
    const prompt = this.selectedPrompt();
    if (prompt !== null) {
      this.promptDraftName = prompt.name;
      this.promptDraftSummary = prompt.description;
      this.promptDraftContent = prompt.content;
      this.triggerFeedback(`已载入 ${prompt.name} 的真实草稿。`, 'info');
    }
  }

  private togglePromptEnabled(promptId: string): void {
    const prompt = this.prompts.find((item: PromptRecord) => item.id === promptId) ?? null;
    if (prompt === null) {
      return;
    }
    const wasEnabled = prompt.enabled;
    const action = wasEnabled
      ? this.promptsViewModel.disableAll()
      : this.promptsViewModel.enablePrompt(promptId);
    action
      .then(() => {
        this.syncPromptsStateFromViewModel();
        this.triggerFeedback(`${prompt.name} 已${wasEnabled ? '停用' : '启用'}。`, 'success');
      })
      .catch((err: Object) => {
        this.promptsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.promptsStatusText, 'error');
      });
  }

  private deletePromptById(promptId: string): void {
    const prompt = this.prompts.find((item: PromptRecord) => item.id === promptId) ?? null;
    if (prompt === null) {
      return;
    }
    this.promptsViewModel.deletePrompt(promptId)
      .then(() => {
        this.syncPromptsStateFromViewModel();
        this.triggerFeedback(`${prompt.name} 已删除。`, 'success');
      })
      .catch((err: Object) => {
        this.promptsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.promptsStatusText, 'error');
      });
  }

  private createNewPrompt(): void {
    const newId = `prompt-${Date.now()}`;
    const newPrompt = new PromptRecord(
      newId,
      '',
      '',
      '',
      false,
      Date.now(),
      0
    );
    this.promptsViewModel.savePrompt(newPrompt)
      .then(() => {
        this.syncPromptsStateFromViewModel();
        this.selectedPromptId = newId;
        this.promptDraftName = '';
        this.promptDraftSummary = '';
        this.promptDraftContent = '';
        this.triggerFeedback('已创建新 Prompt，请编辑后保存。', 'success');
      })
      .catch((err: Object) => {
        this.promptsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.promptsStatusText, 'error');
      });
  }

  private savePromptDraft(): void {
    const prompt = this.selectedPrompt();
    const draft = prompt !== null
      ? new PromptRecord(
          prompt.id,
          this.promptDraftName,
          this.promptDraftContent,
          this.promptDraftSummary,
          prompt.enabled,
          prompt.createdAt,
          prompt.updatedAt
        )
      : new PromptRecord(
          `prompt-${Date.now()}`,
          this.promptDraftName,
          this.promptDraftContent,
          this.promptDraftSummary,
          false,
          Date.now(),
          0
        );
    this.promptsViewModel.savePrompt(draft)
      .then(() => {
        this.syncPromptsStateFromViewModel();
        this.triggerFeedback('Prompt 草稿已保存。', 'success');
      })
      .catch((err: Object) => {
        this.promptsStatusText = this.describeRuntimeError(err);
        this.triggerFeedback(this.promptsStatusText, 'error');
      });
  }

  private selectedApiProvider(): ProviderRecord | null {
    for (let index = 0; index < this.apiProviders.length; index += 1) {
      if (this.apiProviders[index].id === this.selectedApiProviderId) {
        return this.apiProviders[index];
      }
    }
    return null;
  }

  private apiCategoryLabel(category: string): string {
    switch (category) {
      case 'official':
        return '官方';
      case 'third_party':
        return '第三方';
      case 'cloud_provider':
        return '云服务商';
      case 'aggregator':
        return '聚合';
      case 'custom':
        return '自定义';
      default:
        return category;
    }
  }

  private apiWireApiLabel(wireApi: string): string {
    switch (wireApi) {
      case 'responses':
        return 'Responses';
      case 'chat':
        return 'Chat';
      case 'anthropic':
        return 'Anthropic';
      default:
        return wireApi;
    }
  }

  private apiHealthColor(status: string): string {
    switch (status) {
      case 'healthy':
        return '#166534';
      case 'degraded':
        return '#C2410C';
      case 'unhealthy':
      case 'error':
        return '#B91C1C';
      default:
        return '#94A3B8';
    }
  }

  private apiHealthBg(status: string): string {
    switch (status) {
      case 'healthy':
        return '#DCFCE7';
      case 'degraded':
        return '#FFF7ED';
      case 'unhealthy':
      case 'error':
        return '#FEE2E2';
      default:
        return '#F1F5F9';
    }
  }

  private apiHealthLabel(provider: ProviderRecord): string {
    if (provider.healthStatus === 'healthy') {
      return provider.healthLatencyMs > 0 ? `可用 ${provider.healthLatencyMs}ms` : '可用';
    }
    if (provider.healthStatus === 'error' || provider.healthStatus === 'unhealthy') {
      return '不可用';
    }
    if (provider.healthStatus === 'degraded') {
      return '不可对话';
    }
    return '未测速';
  }

  private chatProbeLabel(probe: ChatProbeResult | null): string {
    if (probe === null) {
      return '未测试';
    }
    if (probe.success) {
      return '可对话';
    }
    return '不可用';
  }

  private chatProbeColor(probe: ChatProbeResult | null): string {
    if (probe === null) {
      return '#94A3B8';
    }
    if (probe.success) {
      return '#166534';
    }
    return '#B91C1C';
  }

  private apiProviderInitial(provider: ProviderRecord): string {
    const name = provider.name.trim();
    if (name.length > 0) {
      return name.substring(0, 1).toUpperCase();
    }
    if (provider.icon.trim().length > 0) {
      return provider.icon.substring(0, 1).toUpperCase();
    }
    return 'P';
  }

  private maskApiKey(key: string): string {
    const trimmed = key.trim();
    if (trimmed.length <= 8) return '***';
    return trimmed.substring(0, 4) + '****' + trimmed.substring(trimmed.length - 4);
  }

  private apiProviderSecondaryText(provider: ProviderRecord): string {
    if (provider.baseUrl.trim().length > 0) {
      return provider.baseUrl;
    }
    if (provider.description.trim().length > 0) {
      return provider.description;
    }
    return '未配置官方网址';
  }

  private apiProviderCardBorder(provider: ProviderRecord): string {
    if (provider.id === this.selectedApiProviderId || provider.isActive) {
      return '#6AA7FF';
    }
    return '#D7E2F1';
  }

  private apiProviderCardBackground(provider: ProviderRecord): string {
    if (provider.id === this.selectedApiProviderId || provider.isActive) {
      return '#EEF6FF';
    }
    return '#FFFFFF';
  }

  private apiProviderEmphasized(provider: ProviderRecord): boolean {
    return provider.id === this.selectedApiProviderId || provider.isActive;
  }

  private syncApiDraftFromProvider(providerId: string): void {
    for (let index = 0; index < this.apiProviders.length; index += 1) {
      const provider = this.apiProviders[index];
      if (provider.id !== providerId) {
        continue;
      }
      this.selectedApiProviderId = provider.id;
      this.apiProviderName = provider.name;
      this.apiBaseUrl = provider.baseUrl;
      this.apiModel = provider.model;
      this.apiWireApi = provider.wireApi;
      this.apiAuthState = this.maskApiKey(provider.apiKey);
      if (provider.endpoints.length > 0) {
        const endpoints: ApiEndpointMockItem[] = [];
        for (let endpointIndex = 0; endpointIndex < provider.endpoints.length; endpointIndex += 1) {
          const endpoint = provider.endpoints[endpointIndex];
          endpoints.push(new ApiEndpointMockItem(
            endpointIndex === 0 ? 'Primary' : (endpoint.isActive ? 'Fallback' : 'Preview'),
            endpoint.url,
            endpoint.isActive ? 'Healthy' : (endpoint.latencyMs > 0 ? 'Standby' : 'Draft')
          ));
        }
        this.apiEndpoints = endpoints;
      } else {
        this.apiEndpoints = [];
      }
      return;
    }
    this.selectedApiProviderId = '';
    this.apiProviderName = '';
    this.apiBaseUrl = '';
    this.apiModel = '';
    this.apiAuthState = '';
    this.apiEndpoints = [];
  }

  private selectApiProvider(providerId: string): void {
    this.syncApiDraftFromProvider(providerId);
    this.apiEditorExpanded = false;
  }

  private startEditingApiProvider(providerId: string): void {
    this.syncApiDraftFromProvider(providerId);
    this.apiEditorExpanded = true;
    const provider = this.selectedApiProvider();
    if (provider !== null) {
      this.triggerFeedback(`正在编辑 ${provider.name} 的前端草稿。`, 'info');
    }
  }

  private activateApiProvider(providerId: string): void {
    for (let i = 0; i < this.apiProviders.length; i += 1) {
      this.apiProviders[i].isActive = this.apiProviders[i].id === providerId;
    }
    this.apiProviders = [...this.apiProviders];

    apiManagementVM.activateProvider(providerId);

    if (apiManagementVM.state.errorText.trim().length > 0) {
      this.triggerFeedback(apiManagementVM.state.errorText, 'warning');
      return;
    }
    this.triggerFeedback(apiManagementVM.state.statusText, 'success');
  }

  private removeApiProvider(providerId: string): void {
    this.apiProviders = this.apiProviders.filter((p: ProviderRecord) => p.id !== providerId);
    if (this.selectedApiProviderId === providerId) {
      this.selectedApiProviderId = this.apiProviders.length > 0 ? this.apiProviders[0].id : '';
    }
    this.apiEditorExpanded = false;

    apiManagementVM.deleteProvider(providerId);

    if (apiManagementVM.state.errorText.trim().length > 0) {
      this.triggerFeedback(apiManagementVM.state.errorText, 'warning');
      return;
    }
    this.triggerFeedback(apiManagementVM.state.statusText, 'success');
  }

  private startNewApiProvider(): void {
    apiManagementVM.startEditing(null);
    const editing = apiManagementVM.state.editingProvider;
    if (editing === null) {
      return;
    }
    editing.name = 'New Provider Draft';
    editing.baseUrl = 'https://your-provider.example.com/v1';
    editing.apiKey = 'sk-draft-************************';
    editing.model = 'gpt-5.1';
    editing.description = '等待接入真实后端前的本地草稿。';
    editing.icon = 'N';
    editing.iconColor = '#6366F1';
    apiManagementVM.saveEditing();
    this.syncApiStateFromViewModel();
    if (apiManagementVM.state.errorText.trim().length > 0) {
      this.triggerFeedback(apiManagementVM.state.errorText, 'warning');
      return;
    }
    if (apiManagementVM.state.providers.length > 0) {
      const created = apiManagementVM.state.providers[apiManagementVM.state.providers.length - 1];
      this.syncApiDraftFromProvider(created.id);
    }
    this.apiEditorExpanded = true;
    this.triggerFeedback(apiManagementVM.state.statusText, 'success');
  }

  private applyApiPreset(presetId: string): void {
    apiManagementVM.state.selectedPresetId = presetId;
    apiManagementVM.state.newApiKey = 'sk-preset-************************';
    apiManagementVM.confirmAddFromPreset();
    this.syncApiStateFromViewModel();
    if (apiManagementVM.state.errorText.trim().length > 0) {
      this.triggerFeedback(apiManagementVM.state.errorText, 'warning');
      return;
    }
    if (apiManagementVM.state.providers.length > 0) {
      const created = apiManagementVM.state.providers[apiManagementVM.state.providers.length - 1];
      this.syncApiDraftFromProvider(created.id);
    }
    this.apiActiveSubTab = 'providers';
    this.apiEditorExpanded = true;
    this.triggerFeedback(apiManagementVM.state.statusText, 'success');
  }

  private filteredApiPresets(): ApiPresetMockItem[] {
    if (this.apiPresetCategory === 'all') {
      return this.apiPresets;
    }
    const result: ApiPresetMockItem[] = [];
    for (let index = 0; index < this.apiPresets.length; index += 1) {
      if (this.apiPresets[index].category === this.apiPresetCategory) {
        result.push(this.apiPresets[index]);
      }
    }
    return result;
  }

  private saveApiDraft(): void {
    const provider = this.selectedApiProvider();
    if (provider === null) {
      return;
    }
    apiManagementVM.startEditing(provider);
    const editing = apiManagementVM.state.editingProvider;
    if (editing === null) {
      return;
    }
    editing.name = this.apiProviderName;
    editing.baseUrl = this.apiBaseUrl;
    editing.model = this.apiModel;
    editing.wireApi = this.apiWireApi;
    editing.apiKey = this.apiAuthState;
    apiManagementVM.saveEditing();
    this.syncApiStateFromViewModel();
    if (apiManagementVM.state.errorText.trim().length > 0) {
      this.triggerFeedback(apiManagementVM.state.errorText, 'warning');
      return;
    }
    this.triggerFeedback(apiManagementVM.state.statusText, 'success');
  }

  private validateApiDraft(): void {
    const provider = this.selectedApiProvider();
    if (provider === null) {
      this.triggerFeedback('请先选择 Provider。', 'warning');
      return;
    }
    apiManagementVM.validateProvider(provider)
      .then(() => {
        if (apiManagementVM.state.validationResult !== null && apiManagementVM.state.validationResult.errorMessage.trim().length > 0) {
          this.triggerFeedback(apiManagementVM.state.validationResult.errorMessage, 'warning');
          return;
        }
        const message = apiManagementVM.state.errorText.trim().length > 0
          ? apiManagementVM.state.errorText
          : '已生成前端校验结果。';
        this.triggerFeedback(message, 'warning');
      })
      .catch((err: Object) => {
        this.triggerFeedback(this.describeRuntimeError(err), 'error');
      });
  }

  private runApiSpeedTest(provider: ProviderRecord): void {
    this.apiSpeedTesting = true;
    this.apiSpeedResults = [];
    this.apiShowSpeedResults = true;
    this.selectedApiProviderId = provider.id;
    apiManagementVM.testSpeed(provider, false)
      .then(() => {
        this.apiSpeedResults = [...apiManagementVM.state.speedResults];
        this.apiSpeedTesting = false;
        this.apiProviders = [...apiManagementVM.state.providers];
        const hasSuccess = this.apiSpeedResults.some((r: EndpointSpeedResult) => r.success);
        if (hasSuccess) {
          this.triggerFeedback('端点测速已完成。', 'success');
          return;
        }
        const msg = apiManagementVM.state.errorText.trim().length > 0
          ? apiManagementVM.state.errorText
          : '测速未获得可用结果，请检查网络与 API Key。';
        this.triggerFeedback(msg, 'warning');
      })
      .catch((err: Object) => {
        this.apiSpeedTesting = false;
        this.triggerFeedback(this.describeRuntimeError(err), 'error');
      });
  }

  @Builder
  private apiSpeedResultsPanel() {
    if (this.apiShowSpeedResults && (this.apiSpeedResults.length > 0 || this.apiSpeedTesting)) {
      Column() {
        Row() {
          Text('端点测速结果')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
          Blank()
            .layoutWeight(1)
          if (this.apiSpeedTesting) {
            Text('测速中...')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(10)
              .fontColor('#2563EB')
              .margin({ right: 10 })
          }
          Button('关闭')
            .height(26)
            .fontSize(10)
            .fontColor('#64748B')
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .border({ width: 1, color: '#E5E7EB' })
            .onClick(() => { this.apiShowSpeedResults = false; })
        }
        .width('100%')

        if (this.apiSpeedTesting && this.apiSpeedResults.length === 0) {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
              .color('#2563EB')
            Text('正在测速，请稍候...')
              .fontSize(11)
              .fontColor('#64748B')
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
        }

        List({ space: 0 }) {
          ForEach(this.apiSpeedResults, (r: EndpointSpeedResult) => {
            ListItem() {
              Column() {
                Row() {
                  Text(r.endpointUrl)
                    .copyOption(CopyOptions.LocalDevice)
                    .fontSize(10)
                    .fontColor('#334155')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(r.success ? `${r.latencyMs}ms` : 'FAIL')
                    .copyOption(CopyOptions.LocalDevice)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(r.success ? '#166534' : '#B91C1C')
                    .margin({ left: 8, right: 8 })
                  Text(r.success ? 'OK' : 'ERR')
                    .copyOption(CopyOptions.LocalDevice)
                    .fontSize(9)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(r.success ? '#166534' : '#B91C1C')
                    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                    .backgroundColor(r.success ? '#DCFCE7' : '#FEE2E2')
                    .borderRadius(8)
                }
                .width('100%')

                Row() {
                  Text('对话测试')
                    .copyOption(CopyOptions.None)
                    .fontSize(9)
                    .fontColor('#94A3B8')
                  Text(this.chatProbeLabel(r.chatProbe))
                    .copyOption(CopyOptions.None)
                    .fontSize(9)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.chatProbeColor(r.chatProbe))
                    .margin({ left: 6 })
                  if (r.chatProbe !== null && r.chatProbe.success) {
                    Text(`${r.chatProbe.latencyMs}ms`)
                      .copyOption(CopyOptions.LocalDevice)
                      .fontSize(9)
                      .fontColor('#64748B')
                      .margin({ left: 4 })
                  }
                  if (r.chatProbe !== null && !r.chatProbe.success && r.chatProbe.errorMessage.length > 0) {
                    Text(r.chatProbe.errorMessage)
                      .copyOption(CopyOptions.LocalDevice)
                      .fontSize(8)
                      .fontColor('#94A3B8')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ left: 6 })
                  }
                }
                .width('100%')
                .margin({ top: 4 })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }
          }, (r: EndpointSpeedResult) => r.endpointUrl)
        }
        .width('100%')
        .margin({ top: 6 })
        .height(140)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2EAF3' })
      .borderRadius(18)
      .margin({ top: 12 })
    }
  }

  @Builder
  private backdropLayer() {
    Stack() {
      Column()
        .width(320)
        .height(320)
        .backgroundColor('#D7E8FF')
        .opacity(0.42)
        .borderRadius(180)
        .position({ x: -80, y: -40 })

      Column()
        .width(260)
        .height(260)
        .backgroundColor('#DCFCE7')
        .opacity(0.28)
        .borderRadius(180)
        .position({ x: 860, y: 120 })

      Column()
        .width(220)
        .height(220)
        .backgroundColor('#FDE68A')
        .opacity(0.18)
        .borderRadius(140)
        .position({ x: 720, y: 540 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private topBar() {
    Row() {
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
      .scale({ x: this.pressScale('back'), y: this.pressScale('back') })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed('back', event); })
      .onClick(() => { router.back(); })

      Column() {
        Text('Settings Console')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Text('前端先行 · 独立控制台视图 · 保留后端接入接口')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor('#64748B')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 18 })

      Blank()
        .layoutWeight(1)

      this.particleCluster()

      Text('Frontend Mock Mode')
        .copyOption(CopyOptions.None)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0A84FF')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#EAF3FF')
        .border({ width: 1, color: '#BFDBFE' })
        .borderRadius(14)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 24, bottom: 16 })
  }

  @Builder
  private particleCluster() {
    Row() {
      ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
        Column()
          .width(index % 2 === 0 ? 8 : 5)
          .height(index % 2 === 0 ? 8 : 5)
          .backgroundColor(index % 3 === 0 ? '#60A5FA' : (index % 3 === 1 ? '#34D399' : '#FBBF24'))
          .borderRadius(12)
          .opacity((this.sparkSeed + index) % 2 === 0 ? 0.95 : 0.35)
          .scale({ x: (this.sparkSeed + index) % 2 === 0 ? 1.2 : 0.82, y: (this.sparkSeed + index) % 2 === 0 ? 1.2 : 0.82 })
          .margin({ left: index === 0 ? 0 : 8, top: index % 2 === 0 ? 0 : 10 })
          .animation({ duration: 220, curve: Curve.EaseOut })
      })
    }
    .margin({ right: 2 })
  }

  @Builder
  private sidebar() {
    Column() {
      this.sidebarHero()

      Column() {
        ForEach(this.navItems, (item: SettingsNavItem) => {
          this.sidebarEntry(item)
        }, (item: SettingsNavItem) => item.tab)
      }
      .margin({ top: 16 })

      Blank()
        .layoutWeight(1)

      this.sideFootnote()
    }
    .width(288)
    .height('100%')
    .padding(18)
    .backgroundColor('#F8FBFF')
    .border({ width: 1, color: '#D6E2F0' })
    .borderRadius(28)
  }

  @Builder
  private sidebarHero() {
    Column() {
      Row() {
        Text('CONTROL')
          .copyOption(CopyOptions.None)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0A84FF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#EAF3FF')
          .borderRadius(10)

        Text('MOCK')
          .copyOption(CopyOptions.None)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#166534')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#DCFCE7')
          .borderRadius(10)
          .margin({ left: 6 })
      }

      Text('Settings Shell')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
        .margin({ top: 14 })

      Text('与主会话页分离的管理控制台，先完成视觉、交互与状态语义，再衔接 native façade。')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor('#475569')
        .lineHeight(20)
        .margin({ top: 8 })

      Row() {
        this.metricPill('4', '核心分区')
        this.metricPill('0', '真实写入')
        this.metricPill('∞', '可扩展槽位')
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#DFE9F5' })
    .borderRadius(24)
  }

  @Builder
  private metricPill(value: string, label: string) {
    Column() {
      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#64748B')
        .margin({ top: 2 })
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#F8FAFC')
    .borderRadius(14)
    .margin({ right: 8 })
  }

  @Builder
  private sidebarEntry(item: SettingsNavItem) {
    Button() {
      Row() {
        Column() {
          Text(item.label)
            .copyOption(CopyOptions.None)
            .fontSize(15)
            .fontWeight(this.activeTab === item.tab ? FontWeight.Bold : FontWeight.Medium)
            .fontColor('#0F172A')

          Text(item.subtitle)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor(this.activeTab === item.tab ? '#334155' : '#64748B')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
          .layoutWeight(1)

        Column()
          .width(10)
          .height(10)
          .backgroundColor(item.accent)
          .opacity(this.activeTab === item.tab ? 1 : 0.26)
          .borderRadius(10)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }
    .width('100%')
    .margin({ top: 10 })
    .backgroundColor(this.activeTab === item.tab ? '#FFFFFF' : '#F3F7FC')
    .borderRadius(20)
    .border({ width: 1.4, color: this.activeTab === item.tab ? item.accent : '#D9E5F1' })
    .scale({ x: this.pressScale(`nav-${item.tab}`), y: this.pressScale(`nav-${item.tab}`) })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => { this.updatePressed(`nav-${item.tab}`, event); })
    .onClick(() => { this.selectTab(item.tab); })
  }

  @Builder
  private sideFootnote() {
    Column() {
      Text('接口预留')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
      Text('所有 CTA 已预留为 façade 入口；接后端时只替换 action 实现，不改页面结构。')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .lineHeight(18)
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#DFE9F5' })
    .borderRadius(20)
  }

  @Builder
  private contentArea() {
    Scroll() {
      Column() {
        this.contentHero()

        if (this.activeTab === 'mcp') {
          this.mcpPanel()
        } else if (this.activeTab === 'skills') {
          this.skillsPanel()
        } else if (this.activeTab === 'prompts') {
          this.promptsPanel()
        } else {
          this.apiPanel()
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 24, right: 24, top: 12, bottom: 28 })
    }
    .layoutWeight(1)
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#D6E2F0' })
    .borderRadius(28)
    .margin({ left: 18 })
  }

  @Builder
  private contentHero() {
    Column() {
      Row() {
        Column() {
          Text(`${this.navLabel(this.activeTab)} / Settings`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tabAccent(this.activeTab))
          Text(this.heroTitle())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')
            .margin({ top: 6 })
          Text(this.heroSubtitle())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#475569')
            .lineHeight(20)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  private heroTitle(): string {
    switch (this.activeTab) {
      case 'mcp':
        return 'MCP 通道与工具源管理';
      case 'skills':
        return 'Skills 目录、仓库与备份控制';
      case 'prompts':
        return 'Prompt 套件与会话前置约束';
      default:
        return 'Provider、Model 与 Endpoint 布局';
    }
  }

  private heroSubtitle(): string {
    switch (this.activeTab) {
      case 'mcp':
        return '把工具桥接、授权状态与连接参数收敛到独立控制台，先完成交互语义。';
      case 'skills':
        return '统一管理已安装能力、仓库源和备份快照，保持高密度但不混乱。';
      case 'prompts':
        return '在 UI 里显式展示当前指令集合、启用状态和草稿编辑区。';
      default:
        return '以卡片化布局管理 Provider 接入信息，并为真实校验留出接口。';
    }
  }

  @Builder
  private heroSummaryCard() {
    Column() {
      Text('Interaction hint')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#64748B')
      Text('点击任意主操作都会触发缩放与轻粒子反馈，并给出自动消散提示。')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#334155')
        .lineHeight(18)
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width(240)
    .padding(14)
    .backgroundColor('#F8FBFF')
    .border({ width: 1, color: '#DCE8F4' })
    .borderRadius(20)
  }

  @Builder
  private summaryCard(title: string, value: string, color: string, background: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#64748B')
      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
        .margin({ top: 6 })
      Row() {
        Column()
          .width(8)
          .height(8)
          .backgroundColor(color)
          .borderRadius(10)
        Text('Ready')
          .copyOption(CopyOptions.None)
          .fontSize(10)
          .fontColor(color)
          .margin({ left: 6 })
      }
      .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(16)
    .backgroundColor(background)
    .border({ width: 1, color: '#DCE7F3' })
    .borderRadius(20)
    .margin({ right: 12 })
  }

  @Builder
  private sectionCard(title: string, subtitle: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(22)
  }

  @Builder
  private pill(label: string, background: string, color: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(background)
      .borderRadius(10)
  }

  @Builder
  private actionButton(label: string, key: string, primary: boolean, onClick: () => void) {
    Button(label)
      .height(38)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(primary ? '#FFFFFF' : '#0F172A')
      .backgroundColor(primary ? '#111827' : '#FFFFFF')
      .borderRadius(16)
      .border({ width: primary ? 0 : 1, color: '#D5E0ED' })
      .padding({ left: 16, right: 16 })
      .scale({ x: this.pressScale(key), y: this.pressScale(key) })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed(key, event); })
      .onClick(onClick)
  }

  @Builder
  private optionChip(label: string, selected: boolean, key: string, onClick: () => void) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(11)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? '#0A84FF' : '#475569')
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(selected ? '#EAF3FF' : '#F8FAFC')
      .border({ width: 1, color: selected ? '#BFDBFE' : '#DCE5EF' })
      .borderRadius(12)
      .margin({ right: 8, top: 8 })
      .scale({ x: this.pressScale(key), y: this.pressScale(key) })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed(key, event); })
      .onClick(onClick)
  }

  @Builder
  private formLabel(label: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor('#64748B')
      .margin({ top: 12 })
  }

  @Builder
  private mcpPanel() {
    Column() {
      Row() {
        Column() {
          this.sectionCard('Servers', '左侧快速切换工具通道，右侧编辑真实 MCP 配置。')
          if (this.mcpServers.length === 0) {
            Column() {
              Text('暂无 MCP Server')
                .fontSize(14)
                .fontColor('#94A3B8')
                .margin({ top: 24 })
              Text('点击下方按钮添加第一个 MCP server')
                .fontSize(12)
                .fontColor('#CBD5E1')
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          Column() {
            ForEach(this.mcpServers, (server: McpServerRecord) => {
              this.mcpServerCard(server)
            }, (server: McpServerRecord) => server.id)
          }
          .width('100%')
          .margin({ top: 12 })

          Button('+ Add Server')
            .width('100%')
            .height(40)
            .margin({ top: 10 })
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0A84FF')
            .backgroundColor('#F0F7FF')
            .borderRadius(16)
            .border({ width: 1, color: '#BDD7FF' })
            .scale({ x: this.pressScale('mcp-add'), y: this.pressScale('mcp-add') })
            .animation({ duration: 120, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => { this.updatePressed('mcp-add', event); })
            .onClick(() => { this.openMcpAddDialog(); })
        }
        .width('34%')

        Column() {
          this.mcpEditorCard()
        }
        .layoutWeight(1)
        .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private mcpServerCard(server: McpServerRecord) {
    Button() {
      Column() {
        Row() {
          Column() {
            Text(server.name)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A')
            Text(server.id)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(10)
              .fontColor('#64748B')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
            .layoutWeight(1)

          this.pill(this.healthLabel(server.healthStatus), this.statusChipBackground(server.healthStatus), this.statusChipColor(server.healthStatus))
        }
        .width('100%')

        Row() {
          this.pill(server.enabled ? 'Enabled' : 'Disabled', server.enabled ? '#DCFCE7' : '#F1F5F9', server.enabled ? '#166534' : '#64748B')
          this.pill(this.authLabel(server.authStatus), this.statusChipBackground(server.authStatus), this.statusChipColor(server.authStatus))
        }
        .width('100%')
        .margin({ top: 10 })

        Text(`${server.toolCount} tools · ${server.resourceCount} resources · ${server.transportType}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#64748B')
          .margin({ top: 10 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .margin({ top: 10 })
    .backgroundColor(this.selectedMcpServerId === server.id ? '#F8FBFF' : '#FFFFFF')
    .border({ width: 1.3, color: this.selectedMcpServerId === server.id ? '#0A84FF' : '#E2EAF3' })
    .borderRadius(22)
    .scale({ x: this.pressScale(`mcp-${server.id}`), y: this.pressScale(`mcp-${server.id}`) })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => { this.updatePressed(`mcp-${server.id}`, event); })
    .onClick(() => {
      this.loadMcpDraft(server.id);
      this.triggerFeedback(`已切换到 ${server.name} 草稿。`, 'info');
    })
  }

  @Builder
  private mcpEditorCard() {
    Column() {
      this.sectionCard('Editor', '字段直接绑定 codexBackend MCP façade，保存后会写入真实配置。')

      Column() {
        Row() {
          this.pill(this.selectedMcpServer() !== null && this.selectedMcpServer()!.enabled ? 'Live Layout' : 'Draft Layout', '#EAF3FF', '#0A84FF')
          this.pill('Backend Connected', '#DCFCE7', '#166534')
        }
        .width('100%')

        Text(this.mcpStatusText)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor('#334155')
          .margin({ top: 14 })

        this.formLabel('Transport')
        Row() {
          this.optionChip('stdio', this.mcpTransportTypeDraft === 'stdio', 'transport-stdio', () => { this.mcpTransportTypeDraft = 'stdio'; })
          this.optionChip('http', this.mcpTransportTypeDraft === 'http', 'transport-http', () => { this.mcpTransportTypeDraft = 'http'; })
        }

        this.formLabel('Enabled')
        Row() {
          this.optionChip('true', this.mcpEnabledDraft, 'mcp-enabled-true', () => { this.mcpEnabledDraft = true; })
          this.optionChip('false', !this.mcpEnabledDraft, 'mcp-enabled-false', () => { this.mcpEnabledDraft = false; })
        }

        if (this.mcpTransportTypeDraft === 'stdio') {
          this.formLabel('Command')
          TextInput({ text: this.mcpCommandDraft, placeholder: '例如 npx / node / binary path' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.mcpCommandDraft = value; })

          this.formLabel('Args JSON')
          TextInput({ text: this.mcpArgsDraft, placeholder: '["--flag"]' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.mcpArgsDraft = value; })
        }

        if (this.mcpTransportTypeDraft === 'http') {
          this.formLabel('URL')
          TextInput({ text: this.mcpUrlDraft, placeholder: 'https://example.com/mcp' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.mcpUrlDraft = value; })
        }

        this.formLabel('Environment')
        TextArea({ text: this.mcpEnvDraft, placeholder: '{"KEY":"VALUE"}' })
          .width('100%')
          .height(94)
          .backgroundColor('#F8FAFC')
          .borderRadius(16)
          .padding(12)
          .margin({ top: 6 })
          .onChange((value: string) => { this.mcpEnvDraft = value; })

        Row() {
          this.actionButton('Delete Server', 'mcp-delete', false, () => { this.openMcpDeleteDialog(); })
          this.actionButton('Revert', 'mcp-revert', false, () => { this.revertMcpDraft(); })
          this.actionButton('OAuth Login', 'mcp-oauth', false, () => { this.startSelectedMcpOauth(); })
          this.actionButton('Reload MCP', 'mcp-reload', false, () => { this.reloadMcpDraft(); })
          this.actionButton('Save Config', 'mcp-save', true, () => { this.saveMcpDraft(); })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 18 })
      }
      .width('100%')
      .margin({ top: 12 })
      .padding(18)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2EAF3' })
      .borderRadius(22)
    }
    .width('100%')
  }

  @Builder
  private skillsPanel() {
    Column() {
      Row() {
        this.summaryCard('Installed', `${this.installedSkills.length} skills`, '#14B8A6', '#ECFDF5')
        this.summaryCard('Repos', `${this.skillRepos.length} sources`, '#0A84FF', '#EAF3FF')
        this.summaryCard('Backups', `${this.skillBackups.length} archives`, '#F59E0B', '#FFFBEB')
      }
      .width('100%')

      Row() {
        this.optionChip('Installed', this.skillsActiveSubTab === 'installed', 'skill-tab-installed', () => { this.skillsActiveSubTab = 'installed'; })
        this.optionChip('Repos', this.skillsActiveSubTab === 'repos', 'skill-tab-repos', () => { this.skillsActiveSubTab = 'repos'; })
        this.optionChip('Backups', this.skillsActiveSubTab === 'backups', 'skill-tab-backups', () => { this.skillsActiveSubTab = 'backups'; })

        Blank().layoutWeight(1)

        Button('刷新')
          .height(30)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#6366F1')
          .backgroundColor('#EEF2FF')
          .borderRadius(10)
          .border({ width: 1, color: '#C7D2FE' })
          .padding({ left: 12, right: 12 })
          .scale({ x: this.pressScale('skill-refresh'), y: this.pressScale('skill-refresh') })
          .animation({ duration: 120, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => { this.updatePressed('skill-refresh', event); })
          .onClick(() => {
            skillsVM.loadInstalled(true)
              .then(() => {
                this.syncSkillsStateFromViewModel();
                this.triggerFeedback(`扫描完成，发现 ${this.installedSkills.length} 个 skill`, 'success');
              })
              .catch((err: Object) => {
                this.triggerFeedback(this.describeRuntimeError(err), 'error');
              });
          })
      }
      .width('100%')
      .margin({ top: 16 })

      Text(this.skillsStatusText)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor(skillsVM.state.errorText.trim().length > 0 ? '#B91C1C' : '#334155')
        .margin({ top: 10 })

      if (this.skillsActiveSubTab === 'installed') {
        this.installedSkillsPanel()
      } else if (this.skillsActiveSubTab === 'repos') {
        this.skillReposPanel()
      } else {
        this.skillBackupsPanel()
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  private skillSourceText(skill: InstalledSkill): string {
    return skill.source === 'github' ? 'GitHub' : '本地';
  }

  private skillMetaText(skill: InstalledSkill): string {
    if (skill.repoOwner.length > 0 && skill.repoName.length > 0) {
      return `${skill.repoOwner}/${skill.repoName}`;
    }
    return skill.directory;
  }

  private skillUpdatedText(skill: InstalledSkill): string {
    return skill.updatedAt > 0 ? `updated ${this.formatTimestamp(skill.updatedAt)}` : '刚刚安装';
  }

  @Builder
  private skillInlineTag(label: string, accent: boolean = false) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(accent ? '#94A3B8' : '#A3AFBF')
      .margin({ left: 6 })
  }

  @Builder
  private skillActionButton(label: string, key: string, color: string, bg: string, border: string, onClick: () => void) {
    Button(label)
      .height(30)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .backgroundColor(bg)
      .borderRadius(10)
      .border({ width: 1, color: border })
      .padding({ left: 10, right: 10 })
      .margin({ left: 6 })
      .scale({ x: this.pressScale(key), y: this.pressScale(key) })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed(key, event); })
      .onClick(onClick)
  }

  @Builder
  private installedSkillsPanel() {
    Column() {
      ForEach(this.installedSkills, (skill: InstalledSkill) => {
        Row() {
          Column() {
            Row() {
              Text(skill.name)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (skill.enabled) {
                Text('启用')
                  .copyOption(CopyOptions.None)
                  .fontSize(9)
                  .fontColor('#16A34A')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor('#DCFCE7')
                  .borderRadius(8)
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Text(skill.description)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(11)
              .fontColor('#667085')
              .lineHeight(17)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })

            Row() {
              Text(this.skillSourceText(skill))
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(10)
                .fontColor('#94A3B8')
              Text(this.skillMetaText(skill))
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(10)
                .fontColor('#94A3B8')
                .margin({ left: 10 })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .padding({ right: 12 })

          Row() {
            this.skillActionButton(
              skill.enabled ? '启用中' : '禁用中',
              `skill-toggle-${skill.id}`,
              skill.enabled ? '#16A34A' : '#94A3B8',
              skill.enabled ? '#DCFCE7' : '#F5F7FA',
              skill.enabled ? '#BBF7D0' : '#E5EAF1',
              () => { this.toggleSkillEnabled(skill.id); }
            )
            this.skillActionButton(
              '打开',
              `skill-open-${skill.id}`,
              '#6366F1',
              '#EEF2FF',
              '#C7D2FE',
              () => { this.showSkillDetail(skill); }
            )
            this.skillActionButton(
              '删除',
              `skill-delete-${skill.id}`,
              '#EF4444',
              '#FEF2F2',
              '#FECACA',
              () => { this.requestUninstallSkill(skill.id); }
            )
          }
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
        .border({ width: 1, color: skill.enabled ? '#D1FAE5' : '#E7ECF3' })
        .margin({ top: 0 })
      }, (skill: InstalledSkill) => `${skill.id}-${skill.enabled}`)
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E6EBF2' })
    .borderRadius(18)
    .clip(true)
  }

  @Builder
  private skillReposPanel() {
    Column() {
      Column() {
        this.sectionCard('Repository source', '添加新的 skill 仓库源，但当前只保存在 settings mock 状态中。')

        Row() {
          TextInput({ text: this.newRepoOwner, placeholder: 'owner' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => { this.newRepoOwner = value; })

          TextInput({ text: this.newRepoName, placeholder: 'repo' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ left: 10 })
            .onChange((value: string) => { this.newRepoName = value; })

          TextInput({ text: this.newRepoBranch, placeholder: 'branch' })
            .width(120)
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ left: 10 })
            .onChange((value: string) => { this.newRepoBranch = value; })

          Column() {
            this.actionButton('Add Repo', 'repo-add', true, () => { this.addSkillRepo(); })
          }
          .margin({ left: 10 })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')

      Column() {
        ForEach(this.skillRepos, (repo: SkillRepo) => {
          Row() {
            Column() {
              Text(`${repo.owner}/${repo.name}`)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#0F172A')
              Text(`branch: ${repo.branch}`)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(10)
                .fontColor('#64748B')
                .margin({ top: 5 })
            }
            .alignItems(HorizontalAlign.Start)

            Blank()
              .layoutWeight(1)

            this.pill(repo.enabled ? 'Enabled' : 'Disabled', repo.enabled ? '#DCFCE7' : '#F1F5F9', repo.enabled ? '#166534' : '#64748B')

            Column() {
              this.actionButton(repo.enabled ? 'Disable' : 'Enable', `repo-toggle-${repo.owner}-${repo.name}`, false, () => { this.toggleRepoEnabled(repo.owner, repo.name); })
            }
            .margin({ left: 12 })
            Column() {
              this.actionButton('Remove', `repo-remove-${repo.owner}-${repo.name}`, true, () => { this.removeSkillRepo(repo.owner, repo.name); })
            }
            .margin({ left: 10 })
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E2EAF3' })
          .borderRadius(22)
          .margin({ top: 12 })
        }, (repo: SkillRepo) => `${repo.owner}/${repo.name}`)
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
  }

  @Builder
  private skillBackupsPanel() {
    Column() {
      if (this.skillBackups.length === 0) {
        Column() {
          Text('暂无备份')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
          Text('这里将用于展示 native 卸载动作留下的历史快照。')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ top: 6 })
        }
        .width('100%')
        .padding(28)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2EAF3' })
        .borderRadius(22)
        .margin({ top: 12 })
      } else {
        ForEach(this.skillBackups, (backup: SkillBackupEntry) => {
          Column() {
            Row() {
              Column() {
                Text(backup.skill.name)
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#0F172A')
                Text(backup.backupPath)
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(11)
                  .fontColor('#64748B')
                  .margin({ top: 6 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              this.pill('Archive', '#FFFBEB', '#B45309')
            }
            .width('100%')

            Text(`created at ${this.formatTimestamp(backup.createdAt)}`)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(10)
              .fontColor('#64748B')
              .margin({ top: 12 })

            Row() {
              this.actionButton('Delete Backup', `backup-remove-${backup.backupId}`, true, () => { this.removeSkillBackup(backup.backupId); })
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
            .margin({ top: 16 })
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E2EAF3' })
          .borderRadius(22)
          .margin({ top: 12 })
        }, (backup: SkillBackupEntry) => backup.backupId)
      }
    }
    .width('100%')
  }

  @Builder
  private promptsPanel() {
    Column() {
      Row() {
        Column() {
          Row() {
            Button('刷新')
              .fontSize(12)
              .height(28)
              .backgroundColor('#FFFFFF')
              .fontColor('#334155')
              .borderRadius(14)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.promptsViewModel.loadAll()
                  .then(() => {
                    this.syncPromptsStateFromViewModel();
                    this.triggerFeedback('已刷新', 'success');
                  })
                  .catch((err: Object) => {
                    this.promptsStatusText = this.describeRuntimeError(err);
                    this.triggerFeedback(this.promptsStatusText, 'error');
                  });
              })
            Button('新增')
              .fontSize(12)
              .height(28)
              .backgroundColor('#F59E0B')
              .fontColor('#FFFFFF')
              .borderRadius(14)
              .onClick(() => {
                this.createNewPrompt();
              })
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.sectionCard('Prompt list', '通过卡片显式展示启用状态、更新时间与说明。')

          Column() {
            ForEach(this.prompts, (prompt: PromptRecord) => {
              this.promptCard(prompt)
            }, (prompt: PromptRecord) => `${prompt.id}-${prompt.enabled}`)
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('38%')

        Column() {
          this.promptEditor()
        }
        .layoutWeight(1)
        .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: 18 })
    }
    .width('100%')
  }

  @Builder
  private promptCard(prompt: PromptRecord) {
    Button() {
      Column() {
        Row() {
          Column() {
            Text(prompt.name)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A')
            Text(prompt.description)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(11)
              .fontColor('#64748B')
              .lineHeight(18)
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          this.pill(prompt.enabled ? 'Enabled' : 'Draft', prompt.enabled ? '#DCFCE7' : '#F1F5F9', prompt.enabled ? '#166534' : '#64748B')
        }
        .width('100%')

        Row() {
          Text(`updated ${this.formatTimestamp(prompt.updatedAt > 0 ? prompt.updatedAt : prompt.createdAt)}`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#64748B')
            .layoutWeight(1)

          Button(prompt.enabled ? '禁用' : '启用')
            .fontSize(10)
            .height(24)
            .backgroundColor(prompt.enabled ? '#FEF3C7' : '#DCFCE7')
            .fontColor(prompt.enabled ? '#92400E' : '#166534')
            .borderRadius(12)
            .onClick(() => {
              this.togglePromptEnabled(prompt.id);
            })
            .margin({ right: 6 })

          Button('编辑')
            .fontSize(10)
            .height(24)
            .backgroundColor('#E0F2FE')
            .fontColor('#0C4A6E')
            .borderRadius(12)
            .onClick(() => {
              this.selectPrompt(prompt.id);
            })
            .margin({ right: 6 })

          Button('删除')
            .fontSize(10)
            .height(24)
            .backgroundColor('#FEE2E2')
            .fontColor('#991B1B')
            .borderRadius(12)
            .onClick(() => {
              this.deletePromptById(prompt.id);
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .margin({ top: 10 })
    .backgroundColor(this.selectedPromptId === prompt.id ? '#FFFDF5' : '#FFFFFF')
    .border({ width: 1.3, color: this.selectedPromptId === prompt.id ? '#F59E0B' : '#E2EAF3' })
    .borderRadius(22)
    .scale({ x: this.pressScale(`prompt-${prompt.id}`), y: this.pressScale(`prompt-${prompt.id}`) })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => { this.updatePressed(`prompt-${prompt.id}`, event); })
    .onClick(() => { this.selectPrompt(prompt.id); })
  }

  @Builder
  private promptEditor() {
    Column() {
      this.sectionCard('Prompt editor', '草稿区直接绑定 Prompt registry，启用后会同步更新 AGENTS.md。')

      Column() {
        Row() {
          if (this.selectedPrompt() !== null) {
            this.pill(this.selectedPrompt()!.enabled ? 'Session Ready' : 'Draft Only', this.selectedPrompt()!.enabled ? '#DCFCE7' : '#F1F5F9', this.selectedPrompt()!.enabled ? '#166534' : '#64748B')
          }
          this.pill(this.promptLiveContent.trim().length > 0 ? 'AGENTS.md Live' : 'AGENTS.md Empty', this.promptLiveContent.trim().length > 0 ? '#E0F2FE' : '#FEF3C7', this.promptLiveContent.trim().length > 0 ? '#0C4A6E' : '#92400E')
        }
        .width('100%')

        Text(this.promptsStatusText)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor('#64748B')
          .margin({ top: 10 })
          .width('100%')

        this.formLabel('Name')
        TextInput({ text: this.promptDraftName, placeholder: 'Prompt 名称' })
          .width('100%')
          .height(40)
          .backgroundColor('#F8FAFC')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6 })
          .onChange((value: string) => { this.promptDraftName = value; })

        this.formLabel('Summary')
        TextInput({ text: this.promptDraftSummary, placeholder: '一句话说明这个 prompt 的作用' })
          .width('100%')
          .height(40)
          .backgroundColor('#F8FAFC')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6 })
          .onChange((value: string) => { this.promptDraftSummary = value; })

        this.formLabel('Prompt content')
        TextArea({ text: this.promptDraftContent, placeholder: 'Prompt content' })
          .width('100%')
          .height(220)
          .backgroundColor('#F8FAFC')
          .borderRadius(18)
          .padding(14)
          .margin({ top: 6 })
          .onChange((value: string) => { this.promptDraftContent = value; })

        if (this.promptLiveContent.trim().length > 0) {
          this.formLabel('Live AGENTS.md')
          Text(this.promptLiveContent)
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .fontSize(11)
            .fontColor('#475569')
            .lineHeight(18)
            .padding(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(18)
            .margin({ top: 6 })
            .maxLines(10)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row() {
          if (this.selectedPrompt() !== null) {
            this.actionButton(this.selectedPrompt()!.enabled ? 'Disable' : 'Enable', `prompt-toggle-${this.selectedPrompt()!.id}`, false, () => { this.togglePromptEnabled(this.selectedPrompt()!.id); })
          }
          Column() {
            this.actionButton('Save Draft', 'prompt-save', true, () => { this.savePromptDraft(); })
          }
          .margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 18 })
      }
      .width('100%')
      .margin({ top: 12 })
      .padding(18)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2EAF3' })
      .borderRadius(22)
    }
    .width('100%')
  }

  @Builder
  private apiSubTabChip(label: string, tab: ApiSubTab) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(11)
      .fontWeight(this.apiActiveSubTab === tab ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.apiActiveSubTab === tab ? '#1D4ED8' : '#64748B')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.apiActiveSubTab === tab ? '#EEF4FF' : '#F8FAFC')
      .border({ width: 1, color: this.apiActiveSubTab === tab ? '#BFDBFE' : '#E5E7EB' })
      .borderRadius(12)
      .margin({ right: 8 })
      .scale({ x: this.pressScale(`api-subtab-${tab}`), y: this.pressScale(`api-subtab-${tab}`) })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed(`api-subtab-${tab}`, event); })
      .onClick(() => { this.apiActiveSubTab = tab; })
  }

  @Builder
  private apiFilterChip(label: string, category: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontWeight(this.apiPresetCategory === category ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.apiPresetCategory === category ? '#1D4ED8' : '#64748B')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.apiPresetCategory === category ? '#EEF4FF' : '#FFFFFF')
      .border({ width: 1, color: this.apiPresetCategory === category ? '#BFDBFE' : '#DCE7F3' })
      .borderRadius(10)
      .margin({ right: 8, top: 8 })
      .scale({ x: this.pressScale(`api-filter-${category}`), y: this.pressScale(`api-filter-${category}`) })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed(`api-filter-${category}`, event); })
      .onClick(() => { this.apiPresetCategory = category; })
  }

  @Builder
  private apiSpeedTestButton(provider: ProviderRecord) {
    Row() {
      if (this.apiSpeedTesting && this.selectedApiProviderId === provider.id) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color('#2563EB')
        Text('测速中')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#2563EB')
          .margin({ left: 4 })
      } else {
        Text('测速')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#475569')
      }
    }
    .height(30)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .border({ width: 1, color: (this.apiSpeedTesting && this.selectedApiProviderId === provider.id) ? '#93C5FD' : '#D9E2EE' })
    .padding({ left: 12, right: 12 })
    .scale({ x: this.pressScale(`api-speed-${provider.id}`), y: this.pressScale(`api-speed-${provider.id}`) })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => { this.updatePressed(`api-speed-${provider.id}`, event); })
    .onClick(() => {
      if (!this.apiSpeedTesting) {
        this.runApiSpeedTest(provider);
      }
    })
  }

  @Builder
  private apiProviderActionButton(label: string, key: string, danger: boolean, onClick: () => void) {
    Button(label)
      .height(30)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(danger ? '#B91C1C' : '#475569')
      .backgroundColor('#FFFFFF')
      .borderRadius(10)
      .border({ width: 1, color: danger ? '#F4C9C9' : '#D9E2EE' })
      .padding({ left: 12, right: 12 })
      .scale({ x: this.pressScale(key), y: this.pressScale(key) })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => { this.updatePressed(key, event); })
      .onClick(onClick)
  }

  @Builder
  private apiDragPreviewBuilder() {
    Column() {
      Text(this.dragTargetName.length > 0 ? this.dragTargetName : '未命名')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
        .maxLines(1)
    }
    .width(280)
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .border({ width: 2, color: '#2E8BFF' })
    .borderRadius(20)
    .shadow({ radius: 20, color: '#1E3A5F33', offsetX: 0, offsetY: 10 })
  }

  @Builder
  private apiProviderCard(provider: ProviderRecord) {
    Row() {
      Row() {
        Text('⋮⋮')
          .fontSize(12)
          .fontColor('#C0CAD8')
          .opacity(0.95)
      }
      .width(22)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 8 })

      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(42)
          .height(42)
          .backgroundColor(provider.isActive ? '#FFF5EC' : '#F8FAFC')
          .border({ width: 1, color: provider.isActive ? '#FAD4B4' : '#E2E8F0' })
          .borderRadius(21)

        Text(this.apiProviderInitial(provider))
          .copyOption(CopyOptions.None)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(provider.iconColor.trim().length > 0 ? provider.iconColor : (provider.isActive ? '#D97757' : '#64748B'))
      }
      .margin({ right: 12 })

      Column() {
        Row() {
          Text(provider.name.length > 0 ? provider.name : '未命名')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontWeight(provider.isActive ? FontWeight.Bold : FontWeight.Medium)
            .fontColor('#0F172A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (provider.isActive) {
            Text('当前')
              .copyOption(CopyOptions.None)
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1D4ED8')
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor('#EAF2FF')
              .border({ width: 1, color: '#C7DAFF' })
              .borderRadius(999)
              .margin({ left: 8 })
          }
        }
        .width('100%')

        Text(this.apiProviderSecondaryText(provider))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor(provider.baseUrl.trim().length > 0 ? '#2563EB' : '#94A3B8')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          this.pill(this.apiCategoryLabel(provider.category), '#F4F8FF', '#3563C8')
          this.pill(this.apiWireApiLabel(provider.wireApi), '#F8FAFC', '#64748B')
          this.pill(this.apiHealthLabel(provider), this.apiHealthBg(provider.healthStatus), this.apiHealthColor(provider.healthStatus))
        }
        .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.apiProviderEmphasized(provider)) {
        Row() {
          Button(provider.isActive ? '启用中' : '启用')
            .height(30)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 14, right: 14 })
            .backgroundColor(provider.isActive ? '#2E8BFF' : '#F7FAFF')
            .fontColor(provider.isActive ? '#FFFFFF' : '#2E6EEB')
            .borderRadius(12)
            .border({ width: provider.isActive ? 0 : 1, color: '#BFD3F7' })
            .scale({ x: this.pressScale(`api-activate-${provider.id}`), y: this.pressScale(`api-activate-${provider.id}`) })
            .animation({ duration: 120, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => { this.updatePressed(`api-activate-${provider.id}`, event); })
            .onClick(() => {
              if (!provider.isActive) {
                this.activateApiProvider(provider.id);
              } else {
                this.triggerFeedback('当前 Provider 已启用。', 'info');
              }
            })

          this.apiProviderActionButton('编辑', `api-edit-${provider.id}`, false, () => { this.startEditingApiProvider(provider.id); })
          this.apiProviderActionButton('验证', `api-validate-${provider.id}`, false, () => {
            this.syncApiDraftFromProvider(provider.id);
            this.validateApiDraft();
          })
          this.apiSpeedTestButton(provider)
          this.apiProviderActionButton('删除', `api-delete-${provider.id}`, true, () => { this.removeApiProvider(provider.id); })
        }
        .margin({ left: 12 })
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ left: 14, right: 14, top: 16, bottom: 16 })
    .backgroundColor(this.apiProviderCardBackground(provider))
    .border({
      width: this.dragFromIndex >= 0 && provider.id === this.apiProviders[this.dragFromIndex]?.id ? 2 : (this.apiProviderEmphasized(provider) ? 2 : 1),
      color: this.dragFromIndex >= 0 && provider.id === this.apiProviders[this.dragFromIndex]?.id ? '#2E8BFF' : this.apiProviderCardBorder(provider)
    })
    .borderRadius(20)
    .opacity(this.dragFromIndex >= 0 && provider.id === this.apiProviders[this.dragFromIndex]?.id ? 0.6 : 1.0)
    .scale({ x: this.dragFromIndex >= 0 && provider.id === this.apiProviders[this.dragFromIndex]?.id ? 0.97 : 1.0, y: this.dragFromIndex >= 0 && provider.id === this.apiProviders[this.dragFromIndex]?.id ? 0.97 : 1.0 })
    .animation({ duration: 200, curve: Curve.FastOutSlowIn })
    .onTouch((event: TouchEvent) => {
      if (event.sourceTool !== SourceTool.Finger) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.dragStartY = event.touches[0].y;
        this.dragDownTime = Date.now();
        this.dragMoved = false;
      }
      if (event.type === TouchType.Move) {
        const currentY = event.touches[0].y;
        if (Math.abs(currentY - this.dragStartY) > 10) {
          this.dragMoved = true;
        }
        if (this.dragFromIndex < 0) {
          if (!this.dragMoved && Date.now() - this.dragDownTime >= this.LONG_PRESS_MS) {
            const idx = this.apiProviders.findIndex((p: ProviderRecord) => p.id === provider.id);
            if (idx >= 0) {
              this.dragFromIndex = idx;
              this.dragStartIndex = idx;
              this.dragTargetName = provider.name;
            }
          }
          return;
        }
        const deltaY = currentY - this.dragStartY;
        const step = this.CARD_HEIGHT_ESTIMATE;
        this.dragOverIndex = Math.max(0, Math.min(this.apiProviders.length - 1, this.dragStartIndex + Math.round(deltaY / step)));
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.dragFromIndex < 0) {
          if (!this.dragMoved && Date.now() - this.dragDownTime >= this.LONG_PRESS_MS) {
            const idx = this.apiProviders.findIndex((p: ProviderRecord) => p.id === provider.id);
            if (idx >= 0) {
              this.dragFromIndex = idx;
              this.dragStartIndex = idx;
              this.dragTargetName = provider.name;
              this.dragOverIndex = idx;
            }
          }
        }
        if (this.dragFromIndex >= 0) {
          const deltaY = event.touches[0].y - this.dragStartY;
          const step = this.CARD_HEIGHT_ESTIMATE;
          this.dragOverIndex = Math.max(0, Math.min(this.apiProviders.length - 1, this.dragStartIndex + Math.round(deltaY / step)));
        }
        if (this.dragFromIndex >= 0 && this.dragOverIndex >= 0 && this.dragFromIndex !== this.dragOverIndex) {
          const from = this.dragFromIndex;
          const to = this.dragOverIndex;
          const moved = this.apiProviders.splice(from, 1)[0];
          this.apiProviders.splice(to > from ? to - 1 : to, 0, moved);
          this.apiProviders = [...this.apiProviders];
        }
        this.dragFromIndex = -1;
        this.dragOverIndex = -1;
      }
    })
    .onClick(() => {
      if (this.dragFromIndex >= 0) {
        return;
      }
      this.selectApiProvider(provider.id);
    })
  }

  @Builder
  private apiDropIndicator() {
    Row()
      .width('90%')
      .height(3)
      .backgroundColor('#2E8BFF')
      .borderRadius(2)
      .margin({ top: -5, bottom: -5 })
      .opacity(0.9)
  }

  @Builder
  private apiProvidersPanel() {
    Column() {
      Row() {
        Column() {
          Text('Provider 列表')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
          Text('长按卡片拖动可调整顺序。')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
          .layoutWeight(1)

        this.pill(`${this.apiProviders.length} Providers`, '#EEF4FF', '#1D4ED8')
      }
      .width('100%')

      Column({ space: 12 }) {
        ForEach(this.apiProviders, (provider: ProviderRecord, index: number) => {
          if (this.dragOverIndex === index && this.dragFromIndex !== index) {
            this.apiDropIndicator()
          }
          Column() {
            this.apiProviderCard(provider)
            if (this.apiEditorExpanded && this.selectedApiProviderId === provider.id) {
              this.apiEditorPanel()
            }
          }
          .width('100%')
        }, (provider: ProviderRecord) => `${provider.id}-${provider.isActive}`)
      }
      .width('100%')
      .margin({ top: 14 })

      if (!this.apiEditorExpanded || this.selectedApiProvider() === null) {
        Column() {
          Text('编辑器处于折叠状态')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
          Text('点卡片右侧”编辑”，在当前面板下方展开前端草稿编辑区。')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(18)
        .backgroundColor('#F8FBFF')
        .border({ width: 1, color: '#DCE8F4' })
        .borderRadius(22)
        .margin({ top: 4 })
      }
    }
    .width('100%')
  }

  @Builder
  private apiEditorPanel() {
    if (this.selectedApiProvider() !== null) {
      Column() {


        Column() {
          this.formLabel('Provider name')
          TextInput({ text: this.apiProviderName, placeholder: 'Provider name' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.apiProviderName = value; })

          this.formLabel('Base URL')
          TextInput({ text: this.apiBaseUrl, placeholder: 'https://api.openai.com/v1' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.apiBaseUrl = value; })

          this.formLabel('Model')
          TextInput({ text: this.apiModel, placeholder: 'gpt-5.1' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.apiModel = value; })

          this.formLabel('Wire format')
          Row() {
            this.optionChip('responses', this.apiWireApi === 'responses', 'wire-responses', () => { this.apiWireApi = 'responses'; })
            this.optionChip('chat', this.apiWireApi === 'chat', 'wire-chat', () => { this.apiWireApi = 'chat'; })
            this.optionChip('anthropic', this.apiWireApi === 'anthropic', 'wire-anthropic', () => { this.apiWireApi = 'anthropic'; })
          }

          this.formLabel('API key preview')
          TextInput({ text: this.apiAuthState, placeholder: 'sk-...' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((value: string) => { this.apiAuthState = value; })

          Row() {
            this.actionButton('验证', 'api-validate', false, () => { this.validateApiDraft(); })
            Column() {
              this.actionButton('保存草稿', 'api-save', true, () => { this.saveApiDraft(); })
            }
            .margin({ left: 10 })
            Column() {
              this.actionButton('折叠', 'api-collapse', false, () => { this.apiEditorExpanded = false; })
            }
            .margin({ left: 10 })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .margin({ top: 18 })
        }
        .width('100%')
        .margin({ top: 12 })
        .padding(18)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2EAF3' })
        .borderRadius(22)

        this.apiEndpointDetailPanel()
      }
      .width('100%')
      .margin({ top: 4 })
    }
  }

  @Builder
  private apiEndpointDetailPanel() {
    Column() {
      this.sectionCard('Endpoint matrix', '展示当前选中 Provider 的 endpoint 角色分层与 mock 状态。')
      Column() {
        ForEach(this.apiEndpoints, (endpoint: ApiEndpointMockItem) => {
          Row() {
            Column() {
              Text(endpoint.label)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#0F172A')
              Text(endpoint.value)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(11)
                .fontColor('#64748B')
                .margin({ top: 6 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            this.pill(endpoint.status, this.statusChipBackground(endpoint.status), this.statusChipColor(endpoint.status))
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E2EAF3' })
          .borderRadius(18)
          .margin({ top: 10 })
        }, (endpoint: ApiEndpointMockItem) => `${endpoint.label}-${endpoint.value}`)
      }
      .width('100%')
      .margin({ top: 12 })

      Column() {
        Text('接入说明')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Text('当前页只演示 provider cards、编辑草稿区和 CTA 反馈；真实验证、测速与导入导出逻辑留待后端接入。')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor('#64748B')
          .lineHeight(18)
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(18)
      .backgroundColor('#F8FBFF')
      .border({ width: 1, color: '#DCE8F4' })
      .borderRadius(22)
      .margin({ top: 14 })
    }
    .width('100%')
    .margin({ top: 14 })
  }

  @Builder
  private apiPresetCard(preset: ApiPresetMockItem) {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(38)
            .height(38)
            .backgroundColor('#F8FAFC')
            .border({ width: 1, color: '#E2E8F0' })
            .borderRadius(19)

          Text(preset.name.substring(0, 1).toUpperCase())
            .copyOption(CopyOptions.None)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(preset.accent)
        }
        .margin({ right: 12 })

        Column() {
          Text(preset.name)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
          Text(preset.baseUrl)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#2563EB')
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(preset.description)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8 })

          Row() {
            this.pill(this.apiCategoryLabel(preset.category), '#F4F8FF', '#3563C8')
            this.pill(this.apiWireApiLabel(preset.wireApi), '#F8FAFC', '#64748B')
          }
          .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Button('使用此预设')
          .height(30)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14 })
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .scale({ x: this.pressScale(`api-preset-${preset.id}`), y: this.pressScale(`api-preset-${preset.id}`) })
          .animation({ duration: 120, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => { this.updatePressed(`api-preset-${preset.id}`, event); })
          .onClick(() => { this.applyApiPreset(preset.id); })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(20)
    .margin({ top: 12 })
  }

  @Builder
  private apiPresetsPanel() {
    Column() {
      this.sectionCard('Provider 预设库', '选一个预设作为起点，再回到 Providers 视图补齐前端草稿。')
      Row() {
        this.apiFilterChip('全部', 'all')
        this.apiFilterChip('官方', 'official')
        this.apiFilterChip('第三方', 'third_party')
        this.apiFilterChip('云服务商', 'cloud_provider')
        this.apiFilterChip('聚合', 'aggregator')
      }
      .width('100%')
      .margin({ top: 12 })

      Column() {
        ForEach(this.filteredApiPresets(), (preset: ApiPresetMockItem) => {
          this.apiPresetCard(preset)
        }, (preset: ApiPresetMockItem) => preset.id)
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
  }

  @Builder
  private apiPanel() {
    Column() {
      Column() {
        Row() {
          Column() {
            Text('Provider Workspace')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A')
            Text(apiManagementVM.state.errorText.trim().length > 0
              ? apiManagementVM.state.errorText
              : '统一卡片列表、顶部切换和添加入口，让 Settings 与独立页保持同一视觉语言。')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(11)
              .fontColor(apiManagementVM.state.errorText.trim().length > 0 ? '#B91C1C' : '#64748B')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
            .layoutWeight(1)

          Row() {
            this.apiSubTabChip('Providers', 'providers')
            this.apiSubTabChip('Presets', 'presets')
          }

          Button('+')
            .width(42)
            .height(42)
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF8A1F')
            .borderRadius(16)
            .margin({ left: 12 })
            .scale({ x: this.pressScale('api-add-provider'), y: this.pressScale('api-add-provider') })
            .animation({ duration: 120, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => { this.updatePressed('api-add-provider', event); })
            .onClick(() => { router.pushUrl({ url: 'pages/AddProviderPage' }); })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.apiActiveSubTab === 'presets') {
          this.apiPresetsPanel()
        } else {
          this.apiProvidersPanel()
          this.apiSpeedResultsPanel()
        }
      }
      .width('100%')
      .margin({ top: 18 })
      .padding(20)
      .backgroundColor('#FBFDFF')
      .border({ width: 1, color: '#DCE7F3' })
      .borderRadius(24)
    }
    .width('100%')
  }

  @Builder
  private toastHost() {
    Column() {
      ForEach(this.toasts, (toast: UiToastItem) => {
        Row() {
          Column()
            .width(8)
            .height(8)
            .backgroundColor(this.toneColor(toast.tone))
            .borderRadius(8)

          Text(toast.message)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#0F172A')
            .margin({ left: 10 })
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(360)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(this.toneBackground(toast.tone))
        .border({ width: 1, color: '#FFFFFF' })
        .borderRadius(18)
        .margin({ top: 10 })
      }, (toast: UiToastItem) => `${toast.id}`)
    }
    .alignItems(HorizontalAlign.End)
    .position({ x: 700, y: 28 })
  }

  @Builder
  private skillDeleteDialog() {
    if (this.showSkillDeleteDialog) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#0F172A')
          .opacity(0.18)
          .onClick(() => { this.cancelUninstallSkill(); })

        Column() {
          Text('确认删除 Skill')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text(`删除后将从当前前端列表中移除 “${this.pendingDeleteSkillName}”。`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#64748B')
            .lineHeight(20)
            .margin({ top: 10 })

          Text('当前仍为前端模拟，但危险操作需要确认。')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#B45309')
            .margin({ top: 8 })

          Row() {
            Button('取消')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#475569')
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
              .border({ width: 1, color: '#D5E0ED' })
              .scale({ x: this.pressScale('skill-delete-cancel'), y: this.pressScale('skill-delete-cancel') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('skill-delete-cancel', event); })
              .onClick(() => { this.cancelUninstallSkill(); })

            Button('确认删除')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#F97373')
              .borderRadius(14)
              .margin({ left: 12 })
              .scale({ x: this.pressScale('skill-delete-confirm'), y: this.pressScale('skill-delete-confirm') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('skill-delete-confirm', event); })
              .onClick(() => { this.confirmUninstallSkill(); })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width(420)
        .padding(22)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2EAF3' })
        .borderRadius(24)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private mcpAddDialog() {
    if (this.showMcpAddDialog) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#0F172A')
          .opacity(0.18)
          .onClick(() => { this.cancelMcpAdd(); })

        Column() {
          Text('新增 MCP Server')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text('输入 server 名称，创建后可在编辑器中配置详细参数。')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#64748B')
            .lineHeight(20)
            .margin({ top: 10 })

          TextInput({ text: this.mcpNewServerName, placeholder: '例如 my-mcp-server' })
            .width('100%')
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(14)
            .padding({ left: 12, right: 12 })
            .margin({ top: 14 })
            .onChange((value: string) => { this.mcpNewServerName = value; })

          Row() {
            Button('取消')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#475569')
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
              .border({ width: 1, color: '#D5E0ED' })
              .scale({ x: this.pressScale('mcp-add-cancel'), y: this.pressScale('mcp-add-cancel') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('mcp-add-cancel', event); })
              .onClick(() => { this.cancelMcpAdd(); })

            Button('创建')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#0A84FF')
              .borderRadius(14)
              .margin({ left: 12 })
              .scale({ x: this.pressScale('mcp-add-confirm'), y: this.pressScale('mcp-add-confirm') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('mcp-add-confirm', event); })
              .onClick(() => { this.confirmMcpAdd(); })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width(420)
        .padding(22)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2EAF3' })
        .borderRadius(24)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private mcpDeleteDialog() {
    if (this.showMcpDeleteDialog) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#0F172A')
          .opacity(0.18)
          .onClick(() => { this.cancelMcpDelete(); })

        Column() {
          Text('确认删除 MCP Server')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text(`将从配置中移除 "${this.pendingDeleteMcpName}"，此操作不可撤销。`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#64748B')
            .lineHeight(20)
            .margin({ top: 10 })

          Row() {
            Button('取消')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#475569')
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
              .border({ width: 1, color: '#D5E0ED' })
              .scale({ x: this.pressScale('mcp-delete-cancel'), y: this.pressScale('mcp-delete-cancel') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('mcp-delete-cancel', event); })
              .onClick(() => { this.cancelMcpDelete(); })

            Button('确认删除')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#F97373')
              .borderRadius(14)
              .margin({ left: 12 })
              .scale({ x: this.pressScale('mcp-delete-confirm'), y: this.pressScale('mcp-delete-confirm') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('mcp-delete-confirm', event); })
              .onClick(() => { this.confirmMcpDelete(); })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width(420)
        .padding(22)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2EAF3' })
        .borderRadius(24)
      }
      .width('100%')
      .height('100%')
    }
  }

  private skillDetailSourceLabel(): string {
    if (this.selectedSkillDetail === null) {
      return '';
    }
    const src: string = this.selectedSkillDetail.source;
    if (src === 'github') {
      return 'GitHub';
    }
    if (src === 'zip') {
      return 'ZIP 导入';
    }
    return '本地';
  }

  private skillDetailInstalledDate(): string {
    if (this.selectedSkillDetail === null || this.selectedSkillDetail.installedAt <= 0) {
      return '未知';
    }
    return new Date(this.selectedSkillDetail.installedAt).toISOString().replace('T', ' ').substring(0, 19);
  }

  private skillDetailUpdatedDate(): string {
    if (this.selectedSkillDetail === null || this.selectedSkillDetail.updatedAt <= 0) {
      return '从未更新';
    }
    return new Date(this.selectedSkillDetail.updatedAt).toISOString().replace('T', ' ').substring(0, 19);
  }

  @Builder
  private skillDetailDialog() {
    if (this.showSkillDetailDialog && this.selectedSkillDetail !== null) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#0F172A')
          .opacity(0.18)
          .onClick(() => { this.closeSkillDetail(); })

        Column() {
          Row() {
            Text(this.selectedSkillDetail.name)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F172A')
              .layoutWeight(1)

            Text(this.selectedSkillDetail.enabled ? '启用' : '禁用')
              .copyOption(CopyOptions.None)
              .fontSize(11)
              .fontColor(this.selectedSkillDetail.enabled ? '#16A34A' : '#94A3B8')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.selectedSkillDetail.enabled ? '#DCFCE7' : '#F5F7FA')
              .borderRadius(8)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.selectedSkillDetail.description)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor('#64748B')
            .lineHeight(20)
            .margin({ top: 10 })
            .width('100%')

          Column() {
            this.skillDetailRow('来源', this.skillDetailSourceLabel())
            this.skillDetailRow('目录', this.selectedSkillDetail.directory)
            this.skillDetailRow('ID', this.selectedSkillDetail.id)
            if (this.selectedSkillDetail.source === 'github') {
              this.skillDetailRow('仓库', this.selectedSkillDetail.repoOwner + '/' + this.selectedSkillDetail.repoName)
              this.skillDetailRow('分支', this.selectedSkillDetail.repoBranch)
            }
            if (this.selectedSkillDetail.readmeUrl.length > 0) {
              this.skillDetailRow('README', this.selectedSkillDetail.readmeUrl)
            }
            this.skillDetailRow('安装时间', this.skillDetailInstalledDate())
            this.skillDetailRow('更新时间', this.skillDetailUpdatedDate())
            if (this.selectedSkillDetail.contentHash.length > 0) {
              this.skillDetailRow('内容哈希', this.selectedSkillDetail.contentHash.substring(0, 16) + '...')
            }
          }
          .width('100%')
          .margin({ top: 16 })
          .padding({ top: 14, bottom: 14, left: 14, right: 14 })
          .backgroundColor('#F8FAFC')
          .borderRadius(12)

          Row() {
            Button('关闭')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#475569')
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
              .border({ width: 1, color: '#D5E0ED' })
              .scale({ x: this.pressScale('skill-detail-close'), y: this.pressScale('skill-detail-close') })
              .animation({ duration: 120, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { this.updatePressed('skill-detail-close', event); })
              .onClick(() => { this.closeSkillDetail(); })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width(420)
        .padding(22)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E2EAF3' })
        .borderRadius(24)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private skillDetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#94A3B8')
        .width(70)

      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#334155')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 8 })
  }

  build() {
    Stack() {
      this.backdropLayer()

      Column() {
        this.topBar()

        Row() {
          this.sidebar()
          this.contentArea()
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 28, right: 28, bottom: 26 })
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')

      this.toastHost()
      this.skillDeleteDialog()
      this.skillDetailDialog()
      this.mcpAddDialog()
      this.mcpDeleteDialog()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E9EEF6')
  }
}
