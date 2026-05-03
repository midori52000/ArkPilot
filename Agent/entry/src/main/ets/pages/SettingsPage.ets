import router from '@ohos.router';
import { McpServerRecord, SettingsTab, ProviderRecord, ProviderCategory, ApiWireFormat } from '../backend/ConsoleModels';
import { codexBackend } from '../backend/CodexBackend';
import { BUILTIN_PROVIDER_PRESETS } from '../apim/ApiTypes';
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
    new SettingsNavItem('mcp', 'MCP', '桥接与工具通道', '#0A84FF'),
    new SettingsNavItem('skills', 'Skills', '能力包与仓库源', '#14B8A6'),
    new SettingsNavItem('prompts', 'Prompts', '预设指令与工作约束', '#F59E0B'),
    new SettingsNavItem('api', 'API', 'Provider 与模型接入', '#8B5CF6')
  ];

  @State private activeTab: SettingsTab = 'mcp';
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
        return '#B91C1C';
      default:
        return '#0C4A6E';
    }
  }

  private apiHealthBg(status: string): string {
    switch (status) {
      case 'healthy':
        return '#DCFCE7';
      case 'degraded':
        return '#FFF7ED';
      case 'unhealthy':
        return '#FEE2E2';
      default:
        return '#E0F2FE';
    }
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
      this.apiAuthState = provider.apiKey;
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
    apiManagementVM.activateProvider(providerId);
    this.syncApiStateFromViewModel();
    if (apiManagementVM.state.errorText.trim().length > 0) {
      this.triggerFeedback(apiManagementVM.state.errorText, 'warning');
      return;
    }
    this.triggerFeedback(apiManagementVM.state.statusText, 'success');
  }

  private removeApiProvider(providerId: string): void {
    apiManagementVM.deleteProvider(providerId);
    this.syncApiStateFromViewModel();
    this.apiEditorExpanded = false;
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
        .copyOption(CopyOptions.LocalDevice)
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
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0A84FF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#EAF3FF')
          .borderRadius(10)

        Text('MOCK')
          .copyOption(CopyOptions.LocalDevice)
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
            .copyOption(CopyOptions.LocalDevice)
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

        Blank()
          .layoutWeight(1)

        this.heroSummaryCard()
      }

      Row() {
        this.summaryCard('Visual parity', '1:1 贴近设计稿', '#0A84FF', '#EAF3FF')
        this.summaryCard('Action feedback', '按压缩放 + 轻粒子', '#14B8A6', '#ECFDF5')
        this.summaryCard('Backend mode', '统一 mock façade', '#F59E0B', '#FFFBEB')
      }
      .width('100%')
      .margin({ top: 16 })
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
          .copyOption(CopyOptions.LocalDevice)
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
      .copyOption(CopyOptions.LocalDevice)
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
      .copyOption(CopyOptions.LocalDevice)
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
      .copyOption(CopyOptions.LocalDevice)
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
          Column() {
            ForEach(this.mcpServers, (server: McpServerRecord) => {
              this.mcpServerCard(server)
            }, (server: McpServerRecord) => server.id)
          }
          .width('100%')
          .margin({ top: 12 })
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

        this.formLabel('URL')
        TextInput({ text: this.mcpUrlDraft, placeholder: 'https://example.com/mcp' })
          .width('100%')
          .height(40)
          .backgroundColor('#F8FAFC')
          .borderRadius(14)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6 })
          .onChange((value: string) => { this.mcpUrlDraft = value; })

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
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(accent ? '#94A3B8' : '#A3AFBF')
      .margin({ left: 6 })
  }

  @Builder
  private skillIconAction(symbol: string, key: string, active: boolean, danger: boolean, onClick: () => void) {
    Button(symbol)
      .width(28)
      .height(28)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(danger ? '#F97373' : (active ? '#2F7D6B' : '#9AA6B6'))
      .backgroundColor(danger ? '#FEE2E2' : (active ? '#DDF5EE' : '#FFFFFF'))
      .borderRadius(14)
      .border({ width: 1, color: danger ? '#FECACA' : (active ? '#BFE8DB' : '#E5EAF1') })
      .margin({ left: 10 })
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
              this.skillInlineTag(this.skillSourceText(skill), true)
            }
            .width('100%')

            Text(skill.description)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(11)
              .fontColor('#667085')
              .lineHeight(17)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })

            Row() {
              this.skillInlineTag(this.skillMetaText(skill))
              this.skillInlineTag(this.skillUpdatedText(skill))
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .padding({ right: 16 })

          Row() {
            this.skillIconAction('✺', `skill-toggle-${skill.id}`, skill.enabled, false, () => { this.toggleSkillEnabled(skill.id); })
            this.skillIconAction(skill.source === 'github' ? 'G' : 'L', `skill-source-${skill.id}`, skill.source === 'local', false, () => { this.notePending('Skill 来源详情'); })
            this.skillIconAction('✦', `skill-sync-${skill.id}`, false, false, () => { this.notePending('Skill 同步'); })
            this.skillIconAction('◫', `skill-directory-${skill.id}`, false, false, () => { this.notePending('Skill 目录查看'); })
            this.skillIconAction('◌', `skill-backup-${skill.id}`, false, false, () => { this.notePending('Skill 备份'); })
            this.skillIconAction('⌫', `skill-remove-${skill.id}`, false, true, () => { this.requestUninstallSkill(skill.id); })
          }
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: skill.enabled ? '#D8EEE7' : '#E7ECF3' })
        .borderRadius(0)
        .margin({ top: 0 })
      }, (skill: InstalledSkill) => skill.id)
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
          this.sectionCard('Prompt list', '通过卡片显式展示启用状态、更新时间与说明。')
          Column() {
            ForEach(this.prompts, (prompt: PromptRecord) => {
              this.promptCard(prompt)
            }, (prompt: PromptRecord) => prompt.id)
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

        Text(`updated ${this.formatTimestamp(prompt.updatedAt > 0 ? prompt.updatedAt : prompt.createdAt)}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#64748B')
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
      .copyOption(CopyOptions.LocalDevice)
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
      .copyOption(CopyOptions.LocalDevice)
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
  private apiProviderCard(provider: ProviderRecord) {
    Row() {
      Row() {
        Text('⋮⋮')
          .copyOption(CopyOptions.LocalDevice)
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
          .copyOption(CopyOptions.LocalDevice)
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
              .copyOption(CopyOptions.LocalDevice)
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
          this.pill(provider.healthStatus, this.apiHealthBg(provider.healthStatus), this.apiHealthColor(provider.healthStatus))
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
          this.apiProviderActionButton('复制', `api-copy-${provider.id}`, false, () => { this.notePending('复制 Provider'); })
          this.apiProviderActionButton('验证', `api-validate-${provider.id}`, false, () => {
            this.syncApiDraftFromProvider(provider.id);
            this.validateApiDraft();
          })
          this.apiProviderActionButton('测速', `api-speed-${provider.id}`, false, () => { this.notePending('Provider 测速'); })
          this.apiProviderActionButton('删除', `api-delete-${provider.id}`, true, () => { this.removeApiProvider(provider.id); })
        }
        .margin({ left: 12 })
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ left: 14, right: 14, top: 16, bottom: 16 })
    .backgroundColor(this.apiProviderCardBackground(provider))
    .border({ width: this.apiProviderEmphasized(provider) ? 2 : 1, color: this.apiProviderCardBorder(provider) })
    .borderRadius(20)
    .margin({ bottom: 12 })
    .scale({ x: this.pressScale(`api-card-${provider.id}`), y: this.pressScale(`api-card-${provider.id}`) })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => { this.updatePressed(`api-card-${provider.id}`, event); })
    .onClick(() => { this.selectApiProvider(provider.id); })
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
          Text('保持默认信息简洁，把高频操作收敛到激活态卡片右侧。')
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

      Column() {
        ForEach(this.apiProviders, (provider: ProviderRecord) => {
          this.apiProviderCard(provider)
        }, (provider: ProviderRecord) => provider.id)
      }
      .width('100%')
      .margin({ top: 14 })

      if (this.apiEditorExpanded && this.selectedApiProvider() !== null) {
        this.apiEditorPanel()
      } else {
        Column() {
          Text('编辑器处于折叠状态')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
          Text('点卡片右侧“编辑”，在当前面板下方展开前端草稿编辑区。')
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
        this.sectionCard('Connection profile', '当前编辑区只写前端草稿；后续接后端时优先替换 action/facade。')
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
            this.actionButton('Validate', 'api-validate', false, () => { this.validateApiDraft(); })
            Column() {
              this.actionButton('Save Draft', 'api-save', true, () => { this.saveApiDraft(); })
            }
            .margin({ left: 10 })
            Column() {
              this.actionButton('Collapse', 'api-collapse', false, () => { this.apiEditorExpanded = false; })
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
            .copyOption(CopyOptions.LocalDevice)
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
      Row() {
        this.summaryCard('Provider', this.apiProviderName.length > 0 ? this.apiProviderName : '未选择', '#8B5CF6', '#F5F3FF')
        this.summaryCard('Model', this.apiModel.length > 0 ? this.apiModel : '未设置', '#0A84FF', '#EAF3FF')
        this.summaryCard('Wire API', this.apiWireApiLabel(this.apiWireApi), '#14B8A6', '#ECFDF5')
      }
      .width('100%')

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
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E9EEF6')
  }
}
