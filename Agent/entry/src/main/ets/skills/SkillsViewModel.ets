import { SkillsBackendService, SkillError } from './SkillsBackendService';
import {
  InstalledSkill, DiscoverableSkill, UnmanagedSkill,
  SkillRepo, SkillUpdateInfo, SkillBackupEntry, SkillsShSearchResult
} from './SkillTypes';

@Observed
export class SkillsState {
  installed: InstalledSkill[] = [];
  discoverable: DiscoverableSkill[] = [];
  unmanaged: UnmanagedSkill[] = [];
  updates: SkillUpdateInfo[] = [];
  repos: SkillRepo[] = [];
  backups: SkillBackupEntry[] = [];
  installedLoading: boolean = false;
  discoverableLoading: boolean = false;
  updatesLoading: boolean = false;
  backupsLoading: boolean = false;
}

export class SkillsViewModel {
  private service: SkillsBackendService;
  state: SkillsState = new SkillsState();

  // 缓存控制（对标 React Query staleTime: Infinity）
  private lastInstalledFetch: number = 0;
  private lastDiscoverableFetch: number = 0;
  private readonly STALE_TIME_MS: number = 5 * 60 * 1000;

  constructor(service: SkillsBackendService) {
    this.service = service;
  }

  // ========== 已安装 Skills ==========

  async loadInstalled(forceRefresh: boolean = false): Promise<void> {
    if (!forceRefresh && Date.now() - this.lastInstalledFetch < this.STALE_TIME_MS) {
      return;
    }

    this.state.installedLoading = true;
    try {
      this.state.installed = await this.service.getInstalled();
      this.lastInstalledFetch = Date.now();
    } finally {
      this.state.installedLoading = false;
    }
  }

  async installFromGithub(skill: DiscoverableSkill): Promise<void> {
    const installed = await this.service.installFromGithub(skill);
    this.state.installed = [...this.state.installed, installed];
  }

  async uninstall(id: string): Promise<void> {
    await this.service.uninstall(id);
    this.state.installed = this.state.installed.filter(s => s.id !== id);
  }

  async toggleEnabled(id: string, enabled: boolean): Promise<void> {
    const installed = await this.service.getInstalled();
    const skill = installed.find(s => s.id === id);
    if (!skill) {
      return;
    }

    skill.enabled = enabled;
    await this.service.saveInstalled(installed);

    this.state.installed = this.state.installed.map(s =>
      s.id === id ? skill : s
    );
  }

  // ========== 发现 Skills ==========

  async loadDiscoverable(forceRefresh: boolean = false): Promise<void> {
    if (!forceRefresh && Date.now() - this.lastDiscoverableFetch < this.STALE_TIME_MS) {
      return;
    }

    this.state.discoverableLoading = true;
    try {
      this.state.discoverable = await this.service.discoverFromRepos();
      this.lastDiscoverableFetch = Date.now();
    } finally {
      this.state.discoverableLoading = false;
    }
  }

  // ========== 未管理 Skills ==========

  async scanUnmanaged(): Promise<void> {
    this.state.unmanaged = await this.service.scanUnmanaged();
  }

  async importFromLocal(directories: string[]): Promise<void> {
    const imported = await this.service.importFromLocal(directories);
    this.state.installed = [...this.state.installed, ...imported];

    const importedDirs = new Set(imported.map(s => s.directory));
    this.state.unmanaged = this.state.unmanaged.filter(
      u => !importedDirs.has(u.directory)
    );
  }

  // ========== 更新检测 ==========

  async checkUpdates(): Promise<void> {
    this.state.updatesLoading = true;
    try {
      this.state.updates = await this.service.checkUpdates();
    } finally {
      this.state.updatesLoading = false;
    }
  }

  async updateSkill(id: string): Promise<void> {
    const updated = await this.service.update(id);
    this.state.installed = this.state.installed.map(s =>
      s.id === id ? updated : s
    );
    this.state.updates = this.state.updates.filter(u => u.id !== id);
  }

  // ========== 备份管理 ==========

  async loadBackups(): Promise<void> {
    this.state.backupsLoading = true;
    try {
      this.state.backups = await this.service.getBackups();
    } finally {
      this.state.backupsLoading = false;
    }
  }

  async deleteBackup(backupId: string): Promise<void> {
    await this.service.removeBackup(backupId);
    this.state.backups = this.state.backups.filter(b => b.backupId !== backupId);
  }

  async restoreBackup(backupId: string): Promise<void> {
    const restored = await this.service.restoreBackup(backupId);
    this.state.installed = [...this.state.installed, restored];
  }

  // ========== 仓库管理 ==========

  async loadRepos(): Promise<void> {
    this.state.repos = await this.service.getRepos();
  }

  async addRepo(repo: SkillRepo): Promise<void> {
    await this.service.addRepo(repo);
    await this.loadRepos();
    await this.loadDiscoverable(true);
  }

  async removeRepo(owner: string, name: string): Promise<void> {
    await this.service.removeRepo(owner, name);
    await this.loadRepos();
    await this.loadDiscoverable(true);
  }

  // ========== skills.sh 搜索 ==========

  async searchSkillsSh(
    query: string, limit: number = 20, offset: number = 0
  ): Promise<SkillsShSearchResult> {
    return this.service.searchSkillsSh(query, limit, offset);
  }

  // ========== ZIP 导入 ==========

  async importFromZip(zipPath: string): Promise<void> {
    // 解压 ZIP → 扫描 SKILL.md → 安装
    // 需要完整的 ZIP 解析支持（zip.js 或 NAPI zip crate）
    throw new Error('ZIP import requires full ZIP parsing support');
  }
}
