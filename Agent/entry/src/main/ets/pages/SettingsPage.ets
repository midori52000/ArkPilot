import router from '@ohos.router';
import { McpServerRecord, SettingsTab } from '../backend/ConsoleModels';
import { InstalledSkill, SkillRepo, SkillBackupEntry } from '../skills/SkillTypes';

type ToastTone = 'info' | 'success' | 'warning' | 'error';
type SkillsSubTab = 'installed' | 'repos' | 'backups';

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

class PromptMockItem {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  updatedAt: string;

  constructor(id: string, name: string, description: string, enabled: boolean, updatedAt: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.enabled = enabled;
    this.updatedAt = updatedAt;
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
  @State private mcpStatusText: string = 'Mock façade 已就绪，可先完成界面配置。';

  @State private installedSkills: InstalledSkill[] = [];
  @State private skillRepos: SkillRepo[] = [];
  @State private skillBackups: SkillBackupEntry[] = [];
  @State private skillsActiveSubTab: SkillsSubTab = 'installed';
  @State private newRepoOwner: string = 'anthropics';
  @State private newRepoName: string = 'skills';
  @State private newRepoBranch: string = 'main';
  @State private skillsStatusText: string = '当前列表为前端模拟数据。';

  @State private prompts: PromptMockItem[] = [];
  @State private selectedPromptId: string = '';
  @State private promptDraftName: string = 'Release Guard';
  @State private promptDraftSummary: string = '在危险操作前提醒二次确认，并保持回答简洁。';
  @State private promptDraftContent: string = 'Before destructive actions, summarize impact in one sentence and ask for confirmation. Keep answers terse and actionable.';

  @State private apiProviderName: string = 'OpenAI Gateway';
  @State private apiBaseUrl: string = 'https://api.openai.com/v1';
  @State private apiModel: string = 'gpt-5.1';
  @State private apiWireApi: string = 'responses';
  @State private apiAuthState: string = 'sk-live-************************';
  @State private apiEndpoints: ApiEndpointMockItem[] = [];

  aboutToAppear(): void {
    this.loadMockData();
  }

  private loadMockData(): void {
    this.mcpServers = [
      new McpServerRecord(
        'filesystem', 'Workspace Files', true, 'stdio', 'npx',
        '["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]', '',
        '{"READONLY":"false"}', 12, 4, 'ok', 'notRequired', '', 'synced', '2026-05-02 20:18:41'
      ),
      new McpServerRecord(
        'github', 'GitHub Review', false, 'http', '', '[]', 'https://mcp.example.com/github',
        '{"GITHUB_SCOPE":"repo"}', 8, 2, 'degraded', 'required', '等待 OAuth 完成', 'dirty', '2026-05-02 19:42:10'
      ),
      new McpServerRecord(
        'design-proxy', 'Design Proxy', true, 'http', '', '[]', 'https://design-proxy.local/mcp',
        '{}', 5, 1, 'unknown', 'pending', '', 'synced', '2026-05-02 18:11:03'
      )
    ];
    this.selectedMcpServerId = this.mcpServers[0].id;
    this.loadMcpDraft(this.selectedMcpServerId);

    this.installedSkills = [
      new InstalledSkill(
        'anthropics/release-guard:guard', 'Release Guard', '在危险操作前插入确认提醒与变更摘要。', 'guard',
        'github', 'anthropics', 'release-guard', 'main', '', true,
        Date.now() - 86400000 * 2, '9d4f1c', Date.now() - 3600000 * 8
      ),
      new InstalledSkill(
        'local:mobile-test', 'Mobile Smoke Test', '为移动端改动生成最小可执行验证清单。', 'mobile-test',
        'local', '', '', '', '', false,
        Date.now() - 86400000 * 5, 'e190ab', Date.now() - 3600000 * 18
      ),
      new InstalledSkill(
        'anthropics/ui-polish:ui-polish', 'UI Polish', '强调视觉一致性、细节反馈与界面密度控制。', 'ui-polish',
        'github', 'anthropics', 'ui-polish', 'main', '', true,
        Date.now() - 86400000 * 10, '60a1ff', Date.now() - 3600000 * 26
      )
    ];

    this.skillRepos = [
      new SkillRepo('anthropics', 'skills', 'main', true),
      new SkillRepo('team-design', 'studio-skills', 'preview', false)
    ];

    this.skillBackups = [
      new SkillBackupEntry(
        'backup-001',
        'codex-home/skills/.backup/release-guard-001',
        Date.now() - 86400000,
        new InstalledSkill(
          'anthropics/release-guard:guard', 'Release Guard', '已归档的历史版本备份。', 'guard',
          'github', 'anthropics', 'release-guard', 'main', '', true,
          Date.now() - 86400000 * 6, '7ac0d1', Date.now() - 86400000 * 2
        )
      )
    ];

    this.prompts = [
      new PromptMockItem('default', 'ArkPilot Default', '主会话默认提示词，强调控制台语义与操作准确性。', true, '2026-05-02 19:12'),
      new PromptMockItem('release', 'Release Guard', '发布前检查项：签名、MCP、技能来源与灰度策略。', true, '2026-05-02 18:40'),
      new PromptMockItem('ui', 'UI Review Lens', '用于审视布局密度、状态反馈与交互动效的辅助视角。', false, '2026-05-01 22:18')
    ];
    this.selectedPromptId = this.prompts[1].id;

    this.apiEndpoints = [
      new ApiEndpointMockItem('Primary', 'https://api.openai.com/v1', 'Healthy'),
      new ApiEndpointMockItem('Fallback', 'https://gateway.example.com/v1', 'Standby'),
      new ApiEndpointMockItem('Preview', 'https://preview.example.com/v1', 'Draft')
    ];
  }

  private loadMcpDraft(serverId: string): void {
    for (let index = 0; index < this.mcpServers.length; index += 1) {
      const server = this.mcpServers[index];
      if (server.id !== serverId) {
        continue;
      }
      this.selectedMcpServerId = server.id;
      this.mcpTransportTypeDraft = server.transportType;
      this.mcpCommandDraft = server.command;
      this.mcpArgsDraft = server.argsText;
      this.mcpUrlDraft = server.url;
      this.mcpEnvDraft = server.envText;
      this.mcpEnabledDraft = server.enabled;
      this.mcpStatusText = `${server.name} 已切换到前端模拟配置。`;
      return;
    }
  }

  private selectedMcpServer(): McpServerRecord | null {
    for (let index = 0; index < this.mcpServers.length; index += 1) {
      if (this.mcpServers[index].id === this.selectedMcpServerId) {
        return this.mcpServers[index];
      }
    }
    return null;
  }

  private selectedPrompt(): PromptMockItem | null {
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
    this.triggerFeedback(`${action}暂未接入后端，当前仅在前端模拟。`, 'warning');
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
    for (let index = 0; index < this.mcpServers.length; index += 1) {
      if (this.mcpServers[index].id !== this.selectedMcpServerId) {
        continue;
      }
      this.mcpServers[index].enabled = this.mcpEnabledDraft;
      this.mcpServers[index].transportType = this.mcpTransportTypeDraft;
      this.mcpServers[index].command = this.mcpCommandDraft;
      this.mcpServers[index].argsText = this.mcpArgsDraft;
      this.mcpServers[index].url = this.mcpUrlDraft;
      this.mcpServers[index].envText = this.mcpEnvDraft;
      this.mcpStatusText = `${this.mcpServers[index].name} 已保存到前端 mock。`;
      break;
    }
    this.mcpServers = [...this.mcpServers];
    this.triggerFeedback('MCP 配置已保存（前端模拟）。', 'success');
    this.notePending('MCP 保存');
  }

  private reloadMcpDraft(): void {
    const server = this.selectedMcpServer();
    if (server === null) {
      return;
    }
    this.loadMcpDraft(server.id);
    this.triggerFeedback(`${server.name} 已刷新 mock 状态。`, 'info');
  }

  private toggleSkillEnabled(skillId: string): void {
    for (let index = 0; index < this.installedSkills.length; index += 1) {
      if (this.installedSkills[index].id !== skillId) {
        continue;
      }
      this.installedSkills[index].enabled = !this.installedSkills[index].enabled;
      this.installedSkills = [...this.installedSkills];
      this.skillsStatusText = `${this.installedSkills[index].name} 已切换为 ${this.installedSkills[index].enabled ? '启用' : '停用'} 状态。`;
      this.triggerFeedback(`${this.installedSkills[index].name} 已在前端 mock 中更新。`, 'success');
      this.notePending('Skill 启停');
      return;
    }
  }

  private uninstallSkill(skillId: string): void {
    const before = this.installedSkills.length;
    this.installedSkills = this.installedSkills.filter((skill: InstalledSkill) => skill.id !== skillId);
    if (this.installedSkills.length !== before) {
      this.skillsStatusText = 'Skill 已从前端列表移除。';
      this.triggerFeedback('Skill 已卸载（前端模拟）。', 'warning');
      this.notePending('Skill 卸载');
    }
  }

  private addSkillRepo(): void {
    const owner = this.newRepoOwner.trim();
    const name = this.newRepoName.trim();
    const branch = this.newRepoBranch.trim().length > 0 ? this.newRepoBranch.trim() : 'main';
    if (owner.length === 0 || name.length === 0) {
      this.triggerFeedback('仓库 owner 与 name 不能为空。', 'error');
      return;
    }
    const exists = this.skillRepos.some((repo: SkillRepo) => repo.owner === owner && repo.name === name);
    if (exists) {
      this.triggerFeedback('仓库已存在，无需重复添加。', 'warning');
      return;
    }
    this.skillRepos = [...this.skillRepos, new SkillRepo(owner, name, branch, true)];
    this.skillsStatusText = `${owner}/${name} 已加入前端 mock 源列表。`;
    this.triggerFeedback('仓库已添加（前端模拟）。', 'success');
    this.notePending('Skill 仓库添加');
  }

  private toggleRepoEnabled(owner: string, name: string): void {
    for (let index = 0; index < this.skillRepos.length; index += 1) {
      if (this.skillRepos[index].owner !== owner || this.skillRepos[index].name !== name) {
        continue;
      }
      this.skillRepos[index].enabled = !this.skillRepos[index].enabled;
      this.skillRepos = [...this.skillRepos];
      this.skillsStatusText = `${owner}/${name} 已切换到 ${this.skillRepos[index].enabled ? '启用' : '停用'} 状态。`;
      this.triggerFeedback('仓库状态已更新（前端模拟）。', 'success');
      this.notePending('Skill 仓库切换');
      return;
    }
  }

  private removeSkillRepo(owner: string, name: string): void {
    this.skillRepos = this.skillRepos.filter((repo: SkillRepo) => !(repo.owner === owner && repo.name === name));
    this.skillsStatusText = `${owner}/${name} 已从前端 mock 列表中移除。`;
    this.triggerFeedback('仓库已移除（前端模拟）。', 'warning');
    this.notePending('Skill 仓库移除');
  }

  private removeSkillBackup(backupId: string): void {
    this.skillBackups = this.skillBackups.filter((backup: SkillBackupEntry) => backup.backupId !== backupId);
    this.skillsStatusText = '备份卡片已移除。';
    this.triggerFeedback('备份已删除（前端模拟）。', 'warning');
    this.notePending('Skill 备份删除');
  }

  private selectPrompt(promptId: string): void {
    this.selectedPromptId = promptId;
    const prompt = this.selectedPrompt();
    if (prompt !== null) {
      this.promptDraftName = prompt.name;
      this.promptDraftSummary = prompt.description;
      this.promptDraftContent = `# ${prompt.name}\n\n${prompt.description}\n\n- 强调操作确认\n- 保持输出简洁\n- 在需要时给出下一步验证`;
      this.triggerFeedback(`已载入 ${prompt.name} 的前端草稿。`, 'info');
    }
  }

  private togglePromptEnabled(promptId: string): void {
    for (let index = 0; index < this.prompts.length; index += 1) {
      if (this.prompts[index].id !== promptId) {
        continue;
      }
      this.prompts[index].enabled = !this.prompts[index].enabled;
      this.prompts = [...this.prompts];
      this.triggerFeedback(`${this.prompts[index].name} 已${this.prompts[index].enabled ? '启用' : '停用'}（前端模拟）。`, 'success');
      this.notePending('Prompt 启停');
      return;
    }
  }

  private savePromptDraft(): void {
    const prompt = this.selectedPrompt();
    if (prompt !== null) {
      prompt.name = this.promptDraftName;
      prompt.description = this.promptDraftSummary;
      prompt.updatedAt = '刚刚';
      this.prompts = [...this.prompts];
    }
    this.triggerFeedback('Prompt 草稿已保存（前端模拟）。', 'success');
    this.notePending('Prompt 保存');
  }

  private saveApiDraft(): void {
    this.triggerFeedback('API 配置已保存（前端模拟）。', 'success');
    this.notePending('API 保存');
  }

  private validateApiDraft(): void {
    this.triggerFeedback('已生成前端校验结果：连接链路未实际发起。', 'info');
    this.notePending('API 连通性校验');
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
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontColor('#0F172A')
          Text('Back')
            .copyOption(CopyOptions.LocalDevice)
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
          this.sectionCard('Servers', '左侧快速切换工具通道，右侧编辑 mock 配置草稿。')
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
      this.sectionCard('Editor', '保留字段结构与最终后端对齐，但当前只操作前端 façade。')

      Column() {
        Row() {
          this.pill(this.selectedMcpServer() !== null && this.selectedMcpServer()!.enabled ? 'Live Layout' : 'Draft Layout', '#EAF3FF', '#0A84FF')
          this.pill('No backend write', '#FFF7ED', '#C2410C')
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
          this.actionButton('Reload Mock', 'mcp-reload', false, () => { this.reloadMcpDraft(); })
          this.actionButton('Save Draft', 'mcp-save', true, () => { this.saveMcpDraft(); })
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
        .fontColor('#334155')
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

  @Builder
  private installedSkillsPanel() {
    Column() {
      ForEach(this.installedSkills, (skill: InstalledSkill) => {
        Column() {
          Row() {
            Column() {
              Text(skill.name)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#0F172A')
              Text(skill.description)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(11)
                .fontColor('#64748B')
                .lineHeight(18)
                .margin({ top: 6 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            this.pill(skill.enabled ? 'Enabled' : 'Disabled', skill.enabled ? '#DCFCE7' : '#F1F5F9', skill.enabled ? '#166534' : '#64748B')
          }
          .width('100%')

          Row() {
            this.pill(skill.source === 'github' ? 'GitHub' : 'Local', '#F8FAFC', '#475569')
            this.pill(skill.repoOwner.length > 0 ? `${skill.repoOwner}/${skill.repoName}` : skill.directory, '#EEF2FF', '#4338CA')
            this.pill(`updated ${this.formatTimestamp(skill.updatedAt)}`, '#F8FAFC', '#64748B')
          }
          .width('100%')
          .margin({ top: 12 })

          Row() {
            this.actionButton(skill.enabled ? 'Disable' : 'Enable', `skill-toggle-${skill.id}`, false, () => { this.toggleSkillEnabled(skill.id); })
            Column() {
              this.actionButton('Remove', `skill-remove-${skill.id}`, true, () => { this.uninstallSkill(skill.id); })
            }
            .margin({ left: 10 })
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
      }, (skill: InstalledSkill) => skill.id)
    }
    .width('100%')
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
            ForEach(this.prompts, (prompt: PromptMockItem) => {
              this.promptCard(prompt)
            }, (prompt: PromptMockItem) => prompt.id)
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
  private promptCard(prompt: PromptMockItem) {
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

        Text(`updated ${prompt.updatedAt}`)
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
      this.sectionCard('Prompt editor', '草稿区强调结构与说明文案，不在本轮真实写入 AGENTS.md。')

      Column() {
        Row() {
          if (this.selectedPrompt() !== null) {
            this.pill(this.selectedPrompt()!.enabled ? 'Session Ready' : 'Draft Only', this.selectedPrompt()!.enabled ? '#DCFCE7' : '#F1F5F9', this.selectedPrompt()!.enabled ? '#166534' : '#64748B')
          }
          this.pill('No AGENTS.md write', '#FEF3C7', '#92400E')
        }
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

        this.formLabel('Preview content')
        TextArea({ text: this.promptDraftContent, placeholder: 'Prompt content preview' })
          .width('100%')
          .height(220)
          .backgroundColor('#F8FAFC')
          .borderRadius(18)
          .padding(14)
          .margin({ top: 6 })
          .onChange((value: string) => { this.promptDraftContent = value; })

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
  private apiPanel() {
    Column() {
      Row() {
        this.summaryCard('Provider', this.apiProviderName, '#8B5CF6', '#F5F3FF')
        this.summaryCard('Model', this.apiModel, '#0A84FF', '#EAF3FF')
        this.summaryCard('Wire API', this.apiWireApi, '#14B8A6', '#ECFDF5')
      }
      .width('100%')

      Row() {
        Column() {
          this.sectionCard('Connection profile', '用接近最终配置页的密度组织字段，但提交仍只作用于 mock façade。')
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
        .layoutWeight(1)

        Column() {
          this.sectionCard('Endpoint matrix', '展示多 endpoint 的角色分层与状态标签。')
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
            }, (endpoint: ApiEndpointMockItem) => endpoint.label)
          }
          .width('100%')
          .margin({ top: 12 })

          Column() {
            Text('接入说明')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A')
            Text('当前页只演示 provider form、状态标签和 CTA 反馈；真实请求、测速和导入导出逻辑留待后端接入。')
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
        .width('36%')
        .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: 18 })
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E9EEF6')
  }
}
