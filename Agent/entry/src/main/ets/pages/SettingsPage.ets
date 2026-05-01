import router from '@ohos.router';
import { codexBackend } from '../backend/CodexBackend';
import { getSkillsRegistry, saveSkillsRegistry, getSkillsRepos, saveSkillsRepos, getSkillsBackups, deleteSkillBackup } from '../backend/CodexHostNative';
import { McpServerRecord, SettingsTab } from '../backend/ConsoleModels';
import { InstalledSkill, SkillRepo, SkillBackupEntry, SkillsRegistryJson, SkillEntryJson, SkillsRepoListJson, SkillRepoEntryJson, SkillBackupJson } from '../skills/SkillTypes';
import { PromptsPage } from './PromptsPage';
import { ApiManagementPage } from './ApiManagementPage';

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

  // Skills state
  @State private installedSkills: InstalledSkill[] = [];
  @State private skillRepos: SkillRepo[] = [];
  @State private skillBackups: SkillBackupEntry[] = [];
  @State private installedSkillsLoading: boolean = false;
  @State private skillsStatusText: string = '';
  @State private skillsErrorText: string = '';
  @State private newRepoOwner: string = '';
  @State private newRepoName: string = '';
  @State private newRepoBranch: string = 'main';
  @State private skillsActiveSubTab: string = 'installed'; // 'installed' | 'repos' | 'backups'

  aboutToAppear(): void {
    void this.refreshMcpPanel();
    this.loadInstalledSkills();
    this.loadSkillRepos();
    this.loadSkillBackups();
  }

  // ── Helpers ──

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
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

  // ── Skills methods ──

  private loadInstalledSkills(): void {
    this.installedSkillsLoading = true;
    try {
      const json = getSkillsRegistry('');
      const parsed: SkillsRegistryJson = JSON.parse(json) as SkillsRegistryJson;
      const skills: SkillEntryJson[] = parsed.skills ?? [];
      this.installedSkills = skills.map((s: SkillEntryJson) => InstalledSkill.fromJSON(s));
      this.skillsStatusText = `已加载 ${this.installedSkills.length} 个 Skill`;
      this.skillsErrorText = '';
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
      this.installedSkills = [];
    } finally {
      this.installedSkillsLoading = false;
    }
  }

  private toggleSkillEnabled(skillId: string, enabled: boolean): void {
    try {
      const registry: SkillsRegistryJson = JSON.parse(getSkillsRegistry('')) as SkillsRegistryJson;
      const skills: SkillEntryJson[] = registry.skills;
      for (let i = 0; i < skills.length; i++) {
        if (skills[i].id === skillId) {
          skills[i].enabled = enabled;
          break;
        }
      }
      registry.skills = skills;
      registry.updatedAt = String(Math.floor(Date.now() / 1000));
      saveSkillsRegistry('', JSON.stringify(registry));
      this.loadInstalledSkills();
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private uninstallSkill(skillId: string): void {
    try {
      const registry: SkillsRegistryJson = JSON.parse(getSkillsRegistry('')) as SkillsRegistryJson;
      const skills: SkillEntryJson[] = registry.skills.filter(
        (s: SkillEntryJson) => s.id !== skillId
      );
      registry.skills = skills;
      registry.updatedAt = String(Math.floor(Date.now() / 1000));
      saveSkillsRegistry('', JSON.stringify(registry));
      this.loadInstalledSkills();
      this.skillsStatusText = 'Skill 已卸载';
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private loadSkillRepos(): void {
    try {
      const json = getSkillsRepos('');
      const parsed: SkillsRepoListJson = JSON.parse(json) as SkillsRepoListJson;
      const repos: SkillRepoEntryJson[] = parsed.repos ?? [];
      this.skillRepos = repos.map((r: SkillRepoEntryJson) => SkillRepo.fromJSON(r));
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private addSkillRepo(): void {
    const owner = this.newRepoOwner.trim();
    const name = this.newRepoName.trim();
    const branch = this.newRepoBranch.trim() || 'main';
    if (owner.length === 0 || name.length === 0) {
      this.skillsErrorText = 'Owner 和 Name 不能为空';
      return;
    }
    try {
      const repoList: SkillsRepoListJson = JSON.parse(getSkillsRepos('')) as SkillsRepoListJson;
      const repos: SkillRepoEntryJson[] = repoList.repos;
      if (!repos.some((r: SkillRepoEntryJson) =>
        r.owner === owner && r.name === name)) {
        const newEntry: SkillRepoEntryJson = { owner: owner, name: name, branch: branch, enabled: true };
        repos.push(newEntry);
      }
      repoList.repos = repos;
      saveSkillsRepos('', JSON.stringify(repoList));
      this.newRepoOwner = '';
      this.newRepoName = '';
      this.newRepoBranch = 'main';
      this.loadSkillRepos();
      this.skillsStatusText = `仓库 ${owner}/${name} 已添加`;
      this.skillsErrorText = '';
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private removeSkillRepo(owner: string, name: string): void {
    try {
      const repoList: SkillsRepoListJson = JSON.parse(getSkillsRepos('')) as SkillsRepoListJson;
      const repos: SkillRepoEntryJson[] = repoList.repos.filter(
        (r: SkillRepoEntryJson) => !(r.owner === owner && r.name === name)
      );
      repoList.repos = repos;
      saveSkillsRepos('', JSON.stringify(repoList));
      this.loadSkillRepos();
      this.skillsStatusText = `仓库 ${owner}/${name} 已移除`;
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private toggleRepoEnabled(owner: string, name: string, enabled: boolean): void {
    try {
      const repoList: SkillsRepoListJson = JSON.parse(getSkillsRepos('')) as SkillsRepoListJson;
      const repos: SkillRepoEntryJson[] = repoList.repos;
      for (let i = 0; i < repos.length; i++) {
        if (repos[i].owner === owner && repos[i].name === name) {
          repos[i].enabled = enabled;
          break;
        }
      }
      repoList.repos = repos;
      saveSkillsRepos('', JSON.stringify(repoList));
      this.loadSkillRepos();
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private loadSkillBackups(): void {
    try {
      const json = getSkillsBackups('');
      const parsed: SkillBackupJson[] = JSON.parse(json) as SkillBackupJson[];
      this.skillBackups = parsed.map((b: SkillBackupJson) => SkillBackupEntry.fromBackupJson(b));
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private removeSkillBackup(backupId: string): void {
    try {
      deleteSkillBackup('', backupId);
      this.loadSkillBackups();
      this.skillsStatusText = '备份已删除';
    } catch (err) {
      this.skillsErrorText = this.describeError(err);
    }
  }

  private formatTimestamp(ts: number): string {
    if (ts <= 0) {
      return '-';
    }
    return new Date(ts).toISOString().replace('T', ' ').substring(0, 19);
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

  @Builder
  private apiTab() {
    ApiManagementPage()
  }

  // ── Skills tab ──

  @Builder
  private skillsTab() {
    Column() {
      Row() {
        this.panelTitle('Skills', '管理已安装的 Skills、仓库来源和备份')

        Blank()
          .layoutWeight(1)

        Button('刷新')
          .height(34)
          .fontSize(12)
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(16)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            this.loadInstalledSkills();
            this.loadSkillRepos();
            this.loadSkillBackups();
          })
      }
      .width('100%')

      if (this.skillsStatusText.trim().length > 0) {
        Text(this.skillsStatusText)
          .fontSize(12)
          .fontColor('#334155')
          .lineHeight(20)
          .margin({ top: 8 })
      }

      if (this.skillsErrorText.trim().length > 0) {
        Text(this.skillsErrorText)
          .fontSize(11)
          .fontColor('#B91C1C')
          .lineHeight(18)
          .margin({ top: 6 })
      }

      // Sub-tab bar
      Row() {
        this.skillsSubTabChip('已安装', 'installed')
        this.skillsSubTabChip('仓库', 'repos')
        this.skillsSubTabChip('备份', 'backups')
      }
      .width('100%')
      .margin({ top: 10 })

      // Content area
      if (this.skillsActiveSubTab === 'installed') {
        this.installedSkillsPanel()
      } else if (this.skillsActiveSubTab === 'repos') {
        this.skillReposPanel()
      } else {
        this.skillBackupsPanel()
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder
  private skillsSubTabChip(label: string, tab: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.skillsActiveSubTab === tab ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.skillsActiveSubTab === tab ? '#1D4ED8' : '#64748B')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.skillsActiveSubTab === tab ? '#EEF4FF' : '#F8FAFC')
      .border({ width: 1, color: this.skillsActiveSubTab === tab ? '#BFDBFE' : '#E5E7EB' })
      .borderRadius(12)
      .margin({ right: 8 })
      .onClick(() => {
        this.skillsActiveSubTab = tab;
      })
  }

  // ── Installed Skills panel ──

  @Builder
  private installedSkillsPanel() {
    Column() {
      if (this.installedSkillsLoading) {
        Text('加载中...')
          .fontSize(12)
          .fontColor('#64748B')
          .margin({ top: 20 })
      } else if (this.installedSkills.length === 0) {
        Column() {
          Text('暂无已安装的 Skill')
            .fontSize(13)
            .fontColor('#334155')
            .fontWeight(FontWeight.Medium)

          Text('在"仓库"标签页中启用 GitHub 仓库后，即可发现和安装 Skills。')
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .margin({ top: 8 })

          Text('也可以将 Skill 目录手动放入 .agents/skills/ 下。')
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
        .margin({ top: 12 })
        .backgroundColor('#F8FAFC')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(16)
      } else {
        List({ space: 0 }) {
          ForEach(this.installedSkills, (skill: InstalledSkill) => {
            ListItem() {
              this.installedSkillRow(skill)
            }
          }, (skill: InstalledSkill) => skill.id)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 8 })
        .scrollBar(BarState.Off)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .margin({ top: 8 })
    .padding(14)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(18)
  }

  @Builder
  private installedSkillRow(skill: InstalledSkill) {
    Column() {
      Row() {
        Column() {
          Text(skill.name)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (skill.description.trim().length > 0) {
            Text(skill.description)
              .fontSize(10)
              .fontColor('#64748B')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }

          Row() {
            this.chip(skill.source, '#EEF4FF', '#1D4ED8')
            this.chip(skill.directory, '#F8FAFC', '#64748B')
            if (skill.repoOwner.trim().length > 0) {
              this.chip(`${skill.repoOwner}/${skill.repoName}`, '#FFF7ED', '#C2410C')
            }
            this.chip(skill.enabled ? 'enabled' : 'disabled',
              skill.enabled ? '#DCFCE7' : '#F8FAFC',
              skill.enabled ? '#166534' : '#64748B')
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Button(skill.enabled ? '禁用' : '启用')
          .height(30)
          .fontSize(11)
          .backgroundColor(skill.enabled ? '#FFFFFF' : '#111827')
          .fontColor(skill.enabled ? '#334155' : '#FFFFFF')
          .borderRadius(14)
          .border({ width: 1, color: skill.enabled ? '#CBD5E1' : '#111827' })
          .onClick(() => {
            this.toggleSkillEnabled(skill.id, !skill.enabled);
          })

        Button('卸载')
          .height(30)
          .margin({ left: 8 })
          .fontSize(11)
          .backgroundColor('#FFFFFF')
          .fontColor('#B91C1C')
          .borderRadius(14)
          .border({ width: 1, color: '#FECACA' })
          .onClick(() => {
            this.uninstallSkill(skill.id);
          })
      }
      .width('100%')
      .margin({ top: 8 })

      Row() {
        Text(`安装时间: ${this.formatTimestamp(skill.installedAt)}`)
          .fontSize(10)
          .fontColor('#94A3B8')
        if (skill.updatedAt > 0) {
          Text(` · 更新: ${this.formatTimestamp(skill.updatedAt)}`)
            .fontSize(10)
            .fontColor('#94A3B8')
        }
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(16)
    .margin({ bottom: 8 })
  }

  // ── Skill Repos panel ──

  @Builder
  private skillReposPanel() {
    Column() {
      // Add repo form
      Column() {
        Text('添加 GitHub 仓库')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')

        Row() {
          TextInput({ text: this.newRepoOwner, placeholder: 'owner (如 anthropics)' })
            .layoutWeight(1)
            .height(36)
            .fontSize(11)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 10, right: 10 })
            .border({ width: 1, color: '#E2E8F0' })
            .onChange((value: string) => { this.newRepoOwner = value; })

          TextInput({ text: this.newRepoName, placeholder: 'name (如 skills)' })
            .layoutWeight(1)
            .height(36)
            .fontSize(11)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 10, right: 10 })
            .border({ width: 1, color: '#E2E8F0' })
            .margin({ left: 6 })
            .onChange((value: string) => { this.newRepoName = value; })

          TextInput({ text: this.newRepoBranch, placeholder: 'branch' })
            .width(80)
            .height(36)
            .fontSize(11)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 10, right: 10 })
            .border({ width: 1, color: '#E2E8F0' })
            .margin({ left: 6 })
            .onChange((value: string) => { this.newRepoBranch = value; })

          Button('添加')
            .height(36)
            .fontSize(11)
            .backgroundColor('#111827')
            .fontColor('#FFFFFF')
            .borderRadius(14)
            .margin({ left: 8 })
            .onClick(() => { this.addSkillRepo(); })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor('#F8FAFC')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(14)
      .margin({ top: 8 })

      // Repo list
      if (this.skillRepos.length === 0) {
        Column() {
          Text('暂无仓库')
            .fontSize(12)
            .fontColor('#94A3B8')
            .margin({ top: 16 })
        }
        .width('100%')
      } else {
        List({ space: 0 }) {
          ForEach(this.skillRepos, (repo: SkillRepo) => {
            ListItem() {
              this.skillRepoRow(repo)
            }
          }, (repo: SkillRepo) => `${repo.owner}/${repo.name}`)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 8 })
        .scrollBar(BarState.Off)
      }

      Text('启用的仓库将在"发现"功能中扫描可安装的 Skills。')
        .fontSize(10)
        .fontColor('#94A3B8')
        .lineHeight(16)
        .margin({ top: 10 })
    }
    .layoutWeight(1)
    .width('100%')
    .margin({ top: 8 })
    .padding(14)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(18)
  }

  @Builder
  private skillRepoRow(repo: SkillRepo) {
    Row() {
      Column() {
        Text(`${repo.owner}/${repo.name}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')

        Text(`branch: ${repo.branch}`)
          .fontSize(10)
          .fontColor('#64748B')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.chip(repo.enabled ? 'enabled' : 'disabled',
        repo.enabled ? '#DCFCE7' : '#F8FAFC',
        repo.enabled ? '#166534' : '#64748B')

      Button(repo.enabled ? '禁用' : '启用')
        .height(28)
        .fontSize(10)
        .backgroundColor('#FFFFFF')
        .fontColor('#334155')
        .borderRadius(12)
        .border({ width: 1, color: '#CBD5E1' })
        .margin({ left: 8 })
        .onClick(() => { this.toggleRepoEnabled(repo.owner, repo.name, !repo.enabled); })

      Button('删除')
        .height(28)
        .fontSize(10)
        .backgroundColor('#FFFFFF')
        .fontColor('#B91C1C')
        .borderRadius(12)
        .border({ width: 1, color: '#FECACA' })
        .margin({ left: 6 })
        .onClick(() => { this.removeSkillRepo(repo.owner, repo.name); })
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(14)
    .margin({ bottom: 6 })
  }

  // ── Skill Backups panel ──

  @Builder
  private skillBackupsPanel() {
    Column() {
      if (this.skillBackups.length === 0) {
        Column() {
          Text('暂无备份')
            .fontSize(13)
            .fontColor('#334155')
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20 })

          Text('卸载 Skill 时会自动创建备份。')
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        List({ space: 0 }) {
          ForEach(this.skillBackups, (backup: SkillBackupEntry) => {
            ListItem() {
              this.skillBackupRow(backup)
            }
          }, (backup: SkillBackupEntry) => backup.backupId)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 8 })
        .scrollBar(BarState.Off)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .margin({ top: 8 })
    .padding(14)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(18)
  }

  @Builder
  private skillBackupRow(backup: SkillBackupEntry) {
    Column() {
      Row() {
        Column() {
          Text(backup.skill.name)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`目录: ${backup.skill.directory}  ·  来源: ${backup.skill.source}`)
            .fontSize(10)
            .fontColor('#64748B')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })

          Text(`备份时间: ${this.formatTimestamp(backup.createdAt)}`)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Button('删除备份')
          .height(28)
          .fontSize(10)
          .backgroundColor('#FFFFFF')
          .fontColor('#B91C1C')
          .borderRadius(12)
          .border({ width: 1, color: '#FECACA' })
          .margin({ top: 8 })
          .onClick(() => { this.removeSkillBackup(backup.backupId); })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(16)
    .margin({ bottom: 8 })
  }

  @Builder
  private promptsTab() {
    PromptsPage({ codexHome: '' })
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
