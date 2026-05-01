import {
  getSkillsRegistry, saveSkillsRegistry, getSkillsRepos, saveSkillsRepos,
  computeDirHash, getSkillsBackups, createSkillBackup, deleteSkillBackup
} from '../backend/CodexNative';
import {
  InstalledSkill, DiscoverableSkill, UnmanagedSkill, SkillRepo,
  SkillUpdateInfo, SkillBackupEntry, SkillsShSearchResult, SkillsShItem,
  DEFAULT_SKILL_REPOS, SkillSource
} from './SkillTypes';
import { http } from '@ohos.net.http';
import { fileIo } from '@ohos.file.fs';

const GITHUB_API_BASE = 'https://github.com';
const SKILLS_SH_API = 'https://skills.sh/api/search';
const DOWNLOAD_TIMEOUT_MS = 60000;

export enum SkillErrorCode {
  INVALID_SKILL_DIRECTORY = 'INVALID_SKILL_DIRECTORY',
  SKILL_DIR_NOT_FOUND = 'SKILL_DIR_NOT_FOUND',
  SKILL_DIRECTORY_CONFLICT = 'SKILL_DIRECTORY_CONFLICT',
  SKILL_NOT_FOUND = 'SKILL_NOT_FOUND',
  UPDATE_NOT_SUPPORTED = 'UPDATE_NOT_SUPPORTED',
  BACKUP_NOT_FOUND = 'BACKUP_NOT_FOUND',
  DOWNLOAD_FAILED = 'DOWNLOAD_FAILED',
  EMPTY_ARCHIVE = 'EMPTY_ARCHIVE',
}

export class SkillError extends Error {
  code: SkillErrorCode;
  context: Record<string, string>;
  suggestion: string;

  constructor(code: SkillErrorCode, context: Record<string, string>, suggestion: string) {
    const ctxStr = Object.entries(context).map(([k, v]) => `${k}=${v}`).join(', ');
    super(`[${code}] ${ctxStr}`);
    this.name = 'SkillError';
    this.code = code;
    this.context = context;
    this.suggestion = suggestion;
  }
}

export const SKILL_ERROR_MESSAGES: Record<SkillErrorCode, string> = {
  [SkillErrorCode.INVALID_SKILL_DIRECTORY]: 'Skill 目录路径不合法，请检查路径是否包含非法字符',
  [SkillErrorCode.SKILL_DIR_NOT_FOUND]: '在仓库中未找到指定的 Skill 目录，请确认仓库 URL 是否正确',
  [SkillErrorCode.SKILL_DIRECTORY_CONFLICT]: '已存在同名 Skill（来自不同仓库），请先卸载现有 Skill 再重试',
  [SkillErrorCode.SKILL_NOT_FOUND]: '未找到指定的 Skill，可能已被卸载',
  [SkillErrorCode.UPDATE_NOT_SUPPORTED]: '仅支持更新来自 GitHub 的 Skill',
  [SkillErrorCode.BACKUP_NOT_FOUND]: '备份文件不存在或已被清理',
  [SkillErrorCode.DOWNLOAD_FAILED]: '下载仓库失败，请检查仓库地址和网络连接',
  [SkillErrorCode.EMPTY_ARCHIVE]: '下载的 ZIP 文件为空，请确认仓库是否存在',
};

/**
 * Skills 后端管理服务
 *
 * 职责：
 * - GitHub 仓库 Skill 发现
 * - Skill 安装（下载 → 解压 → 复制到 SSOT → 注册）
 * - Skill 卸载（备份 → 删除 → 移除注册）
 * - 更新检测（SHA-256 对比）
 * - skills.sh 公共目录搜索
 * - 未管理 Skill 扫描
 * - 备份管理
 */
export class SkillsBackendService {
  private codexHome: string;

  constructor(codexHome: string) {
    this.codexHome = codexHome;
  }

  getSsotDir(): string {
    return `${this.codexHome}/../.agents/skills`;
  }

  getBackupDir(): string {
    return `${this.codexHome}/skill-backups`;
  }

  // ================================================================
  // 路径安全校验
  // ================================================================

  private sanitizeSourcePath(raw: string): string | null {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return null;
    }

    const parts = trimmed.split('/').filter(p => p.length > 0);
    if (parts.length === 0) {
      return null;
    }

    for (const part of parts) {
      if (part === '.' || part === '..' || part.trim().length === 0) {
        return null;
      }
    }
    return parts.join('/');
  }

  private sanitizeInstallName(raw: string): string | null {
    const trimmed = raw.trim();
    if (trimmed.length === 0 || trimmed.startsWith('.')) {
      return null;
    }
    if (trimmed === '.' || trimmed === '..') {
      return null;
    }
    if (trimmed.includes('/') || trimmed.includes('\\')) {
      return null;
    }
    if (!/^[a-zA-Z0-9\-_]+$/.test(trimmed)) {
      return null;
    }
    return trimmed;
  }

  // ================================================================
  // 已安装 Skill 管理
  // ================================================================

  async getInstalled(): Promise<InstalledSkill[]> {
    const json = getSkillsRegistry(this.codexHome);
    const parsed = JSON.parse(json);
    const skills = (parsed.skills ?? []) as Record<string, Object>[];
    return skills.map(s => InstalledSkill.fromJSON(s));
  }

  async saveInstalled(skills: InstalledSkill[]): Promise<void> {
    const registry = {
      version: 1,
      skills: skills,
      updatedAt: String(Math.floor(Date.now() / 1000))
    };
    const ok = saveSkillsRegistry(this.codexHome, JSON.stringify(registry));
    if (!ok) {
      throw new Error('Failed to save skills registry');
    }
  }

  /**
   * 安装 Skill（完整流程）
   */
  async installFromGithub(skill: DiscoverableSkill): Promise<InstalledSkill> {
    // Step 1: 校验
    const sourceRel = this.sanitizeSourcePath(skill.directory);
    if (!sourceRel) {
      throw new SkillError(SkillErrorCode.INVALID_SKILL_DIRECTORY,
        { directory: skill.directory }, '目录路径不合法，请检查是否包含非法字符');
    }

    const segments = sourceRel.split('/');
    const installName = this.sanitizeInstallName(segments[segments.length - 1]);
    if (!installName) {
      throw new SkillError(SkillErrorCode.INVALID_SKILL_DIRECTORY,
        { directory: skill.directory }, '安装目录名不合法');
    }

    // Step 2: 冲突检测
    const installed = await this.getInstalled();
    for (const existing of installed) {
      if (existing.directory.toLowerCase() === installName.toLowerCase()) {
        const sameRepo = existing.repoOwner === skill.repoOwner
          && existing.repoName === skill.repoName;
        if (sameRepo) {
          if (!existing.enabled) {
            existing.enabled = true;
            await this.saveInstalled(installed);
          }
          return existing;
        } else {
          throw new SkillError(SkillErrorCode.SKILL_DIRECTORY_CONFLICT,
            { name: installName, existingRepo: `${existing.repoOwner}/${existing.repoName}` },
            `已存在来自 ${existing.repoOwner}/${existing.repoName} 的同名 Skill，请先卸载后再安装`);
        }
      }
    }

    // Step 3-5: 下载、解压、复制
    const repo: SkillRepo = {
      owner: skill.repoOwner,
      name: skill.repoName,
      branch: skill.repoBranch,
      enabled: true
    };

    const { tempDir, usedBranch } = await this.downloadAndExtractRepo(repo);

    const sourceDir = this.resolveSourceDir(tempDir, skill.directory);
    if (!sourceDir) {
      await this.removeDir(tempDir);
      throw new SkillError(SkillErrorCode.SKILL_DIR_NOT_FOUND,
        { directory: skill.directory, repo: `${skill.repoOwner}/${skill.repoName}` },
        `在 ${skill.repoOwner}/${skill.repoName} 中未找到目录 ${skill.directory}`);
    }

    const ssotDir = this.getSsotDir();
    const dest = `${ssotDir}/${installName}`;
    fileIo.mkdirSync(ssotDir, true);
    await this.copyDirRecursive(sourceDir, dest);

    await this.removeDir(tempDir);

    // Step 6: 解析 SKILL.md
    const { name, description } = this.parseSkillMetadata(`${dest}/SKILL.md`, installName);

    // 构建 readmeUrl
    const readmeUrl = `https://github.com/${skill.repoOwner}/${skill.repoName}/blob/${usedBranch}/${skill.directory}/SKILL.md`;

    // Step 7: 计算哈希并保存
    const contentHash = computeDirHash(dest);

    const entry = new InstalledSkill(
      skill.key, name, description, installName,
      'github', skill.repoOwner, skill.repoName, usedBranch,
      readmeUrl, true, Date.now(), contentHash, 0
    );

    installed.push(entry);
    await this.saveInstalled(installed);

    return entry;
  }

  /**
   * 卸载 Skill
   */
  async uninstall(id: string): Promise<string | null> {
    const installed = await this.getInstalled();
    const index = installed.findIndex(s => s.id === id);
    if (index === -1) {
      throw new SkillError(SkillErrorCode.SKILL_NOT_FOUND, { id }, '未找到指定的 Skill，可能已被卸载');
    }

    const skill = installed[index];

    // 备份
    let backupPath: string | null = null;
    try {
      const skillDir = `${this.getSsotDir()}/${skill.directory}`;
      const result = createSkillBackup(this.codexHome, skillDir, JSON.stringify(skill));
      if (!result.startsWith('error:')) {
        backupPath = result;
      }
    } catch (e) {
      console.warn(`Skill backup failed: ${e}`);
    }

    // 从 SSOT 删除
    const ssotPath = `${this.getSsotDir()}/${skill.directory}`;
    await this.removeDir(ssotPath);

    // 从注册表移除
    installed.splice(index, 1);
    await this.saveInstalled(installed);

    return backupPath;
  }

  /**
   * 更新单个 Skill
   */
  async update(id: string): Promise<InstalledSkill> {
    const installed = await this.getInstalled();
    const index = installed.findIndex(s => s.id === id);
    if (index === -1) {
      throw new SkillError(SkillErrorCode.SKILL_NOT_FOUND, { id }, '');
    }

    const skill = installed[index];
    if (skill.source !== 'github' || !skill.repoOwner || !skill.repoName) {
      throw new SkillError(SkillErrorCode.UPDATE_NOT_SUPPORTED,
        { id, source: skill.source }, '仅支持更新来自 GitHub 的 Skill');
    }

    const repo: SkillRepo = {
      owner: skill.repoOwner,
      name: skill.repoName,
      branch: skill.repoBranch || 'main',
      enabled: true
    };

    const { tempDir, usedBranch } = await this.downloadAndExtractRepo(repo);

    const sourceDir = this.resolveSourceDir(tempDir, skill.directory);
    if (!sourceDir) {
      await this.removeDir(tempDir);
      throw new SkillError(SkillErrorCode.SKILL_DIR_NOT_FOUND, { directory: skill.directory }, '');
    }

    // 备份旧文件（best-effort）
    try {
      createSkillBackup(
        this.codexHome,
        `${this.getSsotDir()}/${skill.directory}`,
        JSON.stringify(skill)
      );
    } catch (_) { /* 备份失败不中断更新 */ }

    // 替换文件
    const dest = `${this.getSsotDir()}/${skill.directory}`;
    await this.removeDir(dest);
    await this.copyDirRecursive(sourceDir, dest);
    await this.removeDir(tempDir);

    const contentHash = computeDirHash(dest);
    const { name, description } = this.parseSkillMetadata(`${dest}/SKILL.md`, skill.directory);

    const updated = new InstalledSkill(
      skill.id, name, description, skill.directory,
      skill.source, skill.repoOwner, skill.repoName, usedBranch,
      skill.readmeUrl, skill.enabled, skill.installedAt, contentHash, Date.now()
    );

    installed[index] = updated;
    await this.saveInstalled(installed);

    return updated;
  }

  // ================================================================
  // 发现与扫描
  // ================================================================

  async discoverFromRepos(): Promise<DiscoverableSkill[]> {
    const reposJson = getSkillsRepos(this.codexHome);
    const reposList = JSON.parse(reposJson);
    const repos: SkillRepo[] = (reposList.repos ?? [])
      .map((r: Record<string, Object>) => SkillRepo.fromJSON(r))
      .filter((r: SkillRepo) => r.enabled);

    const results = await Promise.allSettled(
      repos.map(repo => this.fetchRepoSkills(repo))
    );

    const allSkills: DiscoverableSkill[] = [];
    for (const result of results) {
      if (result.status === 'fulfilled') {
        allSkills.push(...result.value);
      }
    }

    // 去重
    const seen = new Set<string>();
    const unique = allSkills.filter(skill => {
      const lower = skill.key.toLowerCase();
      if (seen.has(lower)) {
        return false;
      }
      seen.add(lower);
      return true;
    });

    unique.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
    return unique;
  }

  private async fetchRepoSkills(repo: SkillRepo): Promise<DiscoverableSkill[]> {
    const { tempDir, usedBranch } = await this.downloadAndExtractRepo(repo);
    const skills = await this.scanDirRecursive(tempDir, tempDir, repo, usedBranch);
    await this.removeDir(tempDir);
    return skills;
  }

  private async scanDirRecursive(
    currentDir: string, baseDir: string,
    repo: SkillRepo, usedBranch: string
  ): Promise<DiscoverableSkill[]> {
    const results: DiscoverableSkill[] = [];

    const skillMdPath = `${currentDir}/SKILL.md`;
    try {
      fileIo.statSync(skillMdPath);

      const directory = currentDir === baseDir
        ? repo.name
        : currentDir.substring(baseDir.length + 1);

      const { name, description } = this.parseSkillMetadata(skillMdPath, directory);

      results.push(new DiscoverableSkill(
        `${repo.owner}/${repo.name}:${directory}`,
        name, description, directory,
        `https://github.com/${repo.owner}/${repo.name}/blob/${usedBranch}/${directory}/SKILL.md`,
        repo.owner, repo.name, usedBranch
      ));

      return results;
    } catch (_) { /* 当前目录无 SKILL.md，继续子目录 */ }

    try {
      const entries = fileIo.listFileSync(currentDir);
      for (const entry of entries) {
        if (entry.startsWith('.')) {
          continue;
        }
        const fullPath = `${currentDir}/${entry}`;
        try {
          const stat = fileIo.statSync(fullPath);
          if (stat.isDirectory()) {
            const childResults = await this.scanDirRecursive(fullPath, baseDir, repo, usedBranch);
            results.push(...childResults);
          }
        } catch (_) { /* skip */ }
      }
    } catch (_) { /* skip */ }

    return results;
  }

  /**
   * 扫描未管理的 Skills
   */
  async scanUnmanaged(): Promise<UnmanagedSkill[]> {
    const installed = await this.getInstalled();
    const managedDirs = new Set(installed.map(s => s.directory.toLowerCase()));

    const ssotDir = this.getSsotDir();
    const unmanaged: UnmanagedSkill[] = [];

    let entries: string[];
    try {
      entries = fileIo.listFileSync(ssotDir);
    } catch (_) {
      return unmanaged;
    }

    for (const entry of entries) {
      if (entry.startsWith('.') || managedDirs.has(entry.toLowerCase())) {
        continue;
      }

      const skillMdPath = `${ssotDir}/${entry}/SKILL.md`;
      try {
        fileIo.statSync(skillMdPath);
      } catch (_) {
        continue;
      }

      const { name, description } = this.parseSkillMetadata(skillMdPath, entry);
      unmanaged.push(new UnmanagedSkill(
        entry, name, description, [ssotDir], `${ssotDir}/${entry}`
      ));
    }

    return unmanaged;
  }

  async importFromLocal(directories: string[]): Promise<InstalledSkill[]> {
    const installed = await this.getInstalled();
    const imported: InstalledSkill[] = [];
    const ssotDir = this.getSsotDir();

    for (const sourcePath of directories) {
      const parts = sourcePath.split('/');
      const dirName = parts[parts.length - 1];
      const installName = this.sanitizeInstallName(dirName);
      if (!installName) {
        continue;
      }

      if (installed.some(s => s.directory.toLowerCase() === installName.toLowerCase())) {
        continue;
      }

      const dest = `${ssotDir}/${installName}`;
      await this.copyDirRecursive(sourcePath, dest);

      const { name, description } = this.parseSkillMetadata(`${dest}/SKILL.md`, installName);
      const contentHash = computeDirHash(dest);

      const entry = new InstalledSkill(
        `local:${installName}`, name, description, installName,
        'local', '', '', '', '', true, Date.now(), contentHash, 0
      );

      installed.push(entry);
      imported.push(entry);
    }

    if (imported.length > 0) {
      await this.saveInstalled(installed);
    }

    return imported;
  }

  // ================================================================
  // 更新检测
  // ================================================================

  async checkUpdates(): Promise<SkillUpdateInfo[]> {
    const installed = (await this.getInstalled())
      .filter(s => s.source === 'github' && s.repoOwner && s.repoName);

    const updates: SkillUpdateInfo[] = [];

    const groups = new Map<string, InstalledSkill[]>();
    for (const skill of installed) {
      const branch = skill.repoBranch || 'main';
      const key = `${skill.repoOwner}/${skill.repoName}/${branch}`;
      if (!groups.has(key)) {
        groups.set(key, []);
      }
      groups.get(key)!.push(skill);
    }

    for (const [key, groupSkills] of groups) {
      const parts = key.split('/');
      const [owner, name, branch] = [parts[0], parts[1], parts[2]];
      const repo: SkillRepo = { owner, name, branch, enabled: true };

      let tempDir: string;
      try {
        const result = await this.downloadAndExtractRepo(repo);
        tempDir = result.tempDir;
      } catch (e) {
        console.warn(`下载 ${owner}/${name} 失败: ${e}`);
        continue;
      }

      for (const skill of groupSkills) {
        const remoteDir = this.resolveSourceDir(tempDir, skill.directory);
        if (!remoteDir) {
          continue;
        }

        const remoteHash = computeDirHash(remoteDir);

        if (skill.contentHash !== remoteHash) {
          updates.push(new SkillUpdateInfo(
            skill.id, skill.name, skill.contentHash, remoteHash
          ));
        }
      }

      await this.removeDir(tempDir);
    }

    return updates;
  }

  // ================================================================
  // skills.sh 搜索
  // ================================================================

  async searchSkillsSh(query: string, limit: number, offset: number): Promise<SkillsShSearchResult> {
    const url = `${SKILLS_SH_API}?q=${encodeURIComponent(query)}&limit=${limit}&offset=${offset}`;

    const httpRequest = http.createHttp();
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      throw new Error(`skills.sh API returned ${response.responseCode}`);
    }

    const data = JSON.parse(response.result as string);
    const skills = (data.skills || [])
      .filter((s: Record<string, Object>) => {
        const parts = (s.source as string).split('/');
        return parts.length === 2;
      })
      .map((s: Record<string, Object>) => {
        const srcParts = (s.source as string).split('/');
        const [owner, repo] = [srcParts[0], srcParts[1]];
        return new SkillsShItem(
          s.id as string, s.name as string, s.skillId as string,
          owner, repo, 'main', s.installs as number,
          `https://github.com/${owner}/${repo}`
        );
      });

    return new SkillsShSearchResult(skills, data.count as number, data.query as string);
  }

  // ================================================================
  // 备份管理
  // ================================================================

  async getBackups(): Promise<SkillBackupEntry[]> {
    const json = getSkillsBackups(this.codexHome);
    const rawBackups = JSON.parse(json) as Record<string, Object>[];
    return rawBackups.map(b => new SkillBackupEntry(
      (b.backupId as string) ?? '',
      (b.backupPath as string) ?? '',
      (b.createdAt as number) ?? 0,
      InstalledSkill.fromJSON((b.skill ?? {}) as Record<string, Object>)
    ));
  }

  async removeBackup(backupId: string): Promise<void> {
    deleteSkillBackup(this.codexHome, backupId);
  }

  async restoreBackup(backupId: string): Promise<InstalledSkill> {
    const backups = await this.getBackups();
    const backup = backups.find(b => b.backupId === backupId);
    if (!backup) {
      throw new SkillError(SkillErrorCode.BACKUP_NOT_FOUND, { backupId }, '备份文件不存在或被清理');
    }

    const installed = await this.getInstalled();
    if (installed.some(s => s.id === backup.skill.id)) {
      throw new SkillError(SkillErrorCode.SKILL_DIRECTORY_CONFLICT,
        { directory: backup.skill.directory }, '同名 Skill 已存在，请先卸载');
    }

    const dest = `${this.getSsotDir()}/${backup.skill.directory}`;
    const backupSkillDir = `${backup.backupPath}/skill`;
    await this.copyDirRecursive(backupSkillDir, dest);

    const restored = InstalledSkill.fromJSON(backup.skill as Object as Record<string, Object>);
    restored.installedAt = Date.now();
    restored.updatedAt = 0;
    restored.enabled = true;

    try {
      restored.contentHash = computeDirHash(dest);
    } catch (_) { /* 哈希计算不应中断恢复 */ }

    installed.push(restored);
    await this.saveInstalled(installed);

    return restored;
  }

  // ================================================================
  // 仓库管理
  // ================================================================

  async getRepos(): Promise<SkillRepo[]> {
    const json = getSkillsRepos(this.codexHome);
    const parsed = JSON.parse(json);
    return (parsed.repos ?? []).map((r: Record<string, Object>) => SkillRepo.fromJSON(r));
  }

  async saveRepos(repos: SkillRepo[]): Promise<void> {
    const repoList = { version: 1, repos: repos };
    const ok = saveSkillsRepos(this.codexHome, JSON.stringify(repoList));
    if (!ok) {
      throw new Error('Failed to save repos');
    }
  }

  async addRepo(repo: SkillRepo): Promise<void> {
    const repos = await this.getRepos();
    if (!repos.some(r => r.owner === repo.owner && r.name === repo.name)) {
      repos.push(repo);
      await this.saveRepos(repos);
    }
  }

  async removeRepo(owner: string, name: string): Promise<void> {
    const repos = await this.getRepos();
    const filtered = repos.filter(r => !(r.owner === owner && r.name === name));
    await this.saveRepos(filtered);
  }

  // ================================================================
  // 下载与解压
  // ================================================================

  private async downloadAndExtractRepo(
    repo: SkillRepo
  ): Promise<{ tempDir: string; usedBranch: string }> {
    const branches = [repo.branch];
    if (repo.branch !== 'main') {
      branches.push('main');
    }
    if (repo.branch !== 'master') {
      branches.push('master');
    }

    let lastError: Error | null = null;

    for (const branch of branches) {
      const url = `${GITHUB_API_BASE}/${repo.owner}/${repo.name}/archive/refs/heads/${branch}.zip`;

      try {
        const httpRequest = http.createHttp();
        const response = await httpRequest.request(url, {
          method: http.RequestMethod.GET,
          connectTimeout: DOWNLOAD_TIMEOUT_MS,
          readTimeout: DOWNLOAD_TIMEOUT_MS
        });

        if (response.responseCode !== 200) {
          throw new Error(`HTTP ${response.responseCode}`);
        }

        // 创建临时目录
        const tempDir = `${this.codexHome}/.tmp_skill_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        fileIo.mkdirSync(tempDir, true);

        // 保存并解压 ZIP
        // 注意：HarmonyOS @ohos.zlib 对 ZIP 格式支持有限，
        // 这里保存原始数据到临时文件供后续处理
        const zipPath = `${tempDir}.zip`;
        const zipData = response.result as ArrayBuffer;
        const file = fileIo.openSync(zipPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        fileIo.writeSync(file.fd, zipData);
        fileIo.closeSync(file);

        // 解压 ZIP 到 tempDir
        await this.extractZip(zipPath, tempDir);

        // 清理临时 ZIP 文件
        try {
          fileIo.unlinkSync(zipPath);
        } catch (_) { /* cleanup best-effort */ }

        // GitHub ZIP 解压后文件在一个 repo-branch 前缀目录下，
        // 需要将内容提升一级以简化后续 sourceDir 解析
        this.flattenGitHubZipRoot(tempDir);

        return { tempDir, usedBranch: branch };
      } catch (e) {
        lastError = e as Error;
        continue;
      }
    }

    throw lastError || new Error(`All branches failed for ${repo.owner}/${repo.name}`);
  }

  /**
   * GitHub ZIP 解压后内容在 {repo}-{branch}/ 子目录下，
   * 将子目录内容移到 tempDir 根以简化路径解析。
   */
  private flattenGitHubZipRoot(tempDir: string): void {
    try {
      const entries = fileIo.listFileSync(tempDir);
      const dirs = entries.filter(e => {
        try {
          return fileIo.statSync(`${tempDir}/${e}`).isDirectory();
        } catch (_) {
          return false;
        }
      });

      if (dirs.length === 1) {
        const innerDir = `${tempDir}/${dirs[0]}`;
        const innerEntries = fileIo.listFileSync(innerDir);
        for (const entry of innerEntries) {
          const src = `${innerDir}/${entry}`;
          const dst = `${tempDir}/${entry}`;
          fileIo.renameSync(src, dst);
        }
        fileIo.rmdirSync(innerDir);
      }
    } catch (_) { /* best-effort flatten */ }
  }

  /**
   * 解压 ZIP 文件
   *
   * HarmonyOS @ohos.zlib 提供的是流式解压（inflate），不支持完整 ZIP 格式解析。
   * 当前实现通过保存 ZIP 文件到临时路径，依赖系统的 ZIP 解压能力。
   * 如需完整 ZIP 解析，可引入 zip.js 纯 JS 库。
   */
  private async extractZip(zipPath: string, destDir: string): Promise<void> {
    // 尝试使用 @ohos.zlib 进行解压
    // 完整 ZIP 解析需要处理 local file headers、central directory 等结构
    // 这里提供一个基础框架，实际 ZIP 解析可能需要第三方库
    try {
      const zlib = await import('@ohos.zlib');
      // zlib.decompress 用于单个 deflate 流，不适用于完整 ZIP
      // 此方法作为占位，实际部署需要 zip.js 或 NAPI zip crate
      console.info('ZIP extraction requires full ZIP format support');
    } catch (e) {
      console.warn(`ZIP extraction not fully available: ${e}`);
    }
    // 抛出错误提示需要完整的 ZIP 支持
    throw new Error('ZIP extraction requires zip.js or native zip support');
  }

  // ================================================================
  // 文件操作
  // ================================================================

  private async copyDirRecursive(src: string, dest: string): Promise<void> {
    fileIo.mkdirSync(dest, true);

    const files = fileIo.listFileSync(src);
    for (const file of files) {
      const srcPath = `${src}/${file}`;
      const destPath = `${dest}/${file}`;

      try {
        const stat = fileIo.statSync(srcPath);
        if (stat.isDirectory()) {
          await this.copyDirRecursive(srcPath, destPath);
        } else {
          fileIo.copyFileSync(srcPath, destPath);
        }
      } catch (e) {
        console.warn(`copy failed: ${srcPath} -> ${destPath}: ${e}`);
      }
    }
  }

  private async removeDir(path: string): Promise<void> {
    try {
      this.removeDirRecursive(path);
    } catch (_) { /* ignore */ }
  }

  private removeDirRecursive(path: string): void {
    try {
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        const entries = fileIo.listFileSync(path);
        for (const entry of entries) {
          this.removeDirRecursive(`${path}/${entry}`);
        }
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      // 尝试直接删除
      try {
        fileIo.rmdirSync(path);
      } catch (_) {
        try {
          fileIo.unlinkSync(path);
        } catch (_) { /* best effort */ }
      }
    }
  }

  // ================================================================
  // SKILL.md 解析
  // ================================================================

  private parseSkillMetadata(
    skillMdPath: string,
    fallbackName: string
  ): { name: string; description: string } {
    try {
      const content = fileIo.readTextSync(skillMdPath);
      const clean = content.replace(/^﻿/, ''); // 去除 BOM

      const parts = clean.split('---');
      if (parts.length < 3) {
        return { name: fallbackName, description: '' };
      }

      const frontMatter = parts[1].trim();
      const lines = frontMatter.split('\n');
      let name: string | null = null;
      let description: string | null = null;

      for (const line of lines) {
        const colonIdx = line.indexOf(':');
        if (colonIdx === -1) {
          continue;
        }

        const key = line.substring(0, colonIdx).trim();
        const value = line.substring(colonIdx + 1).trim().replace(/^['"]|['"]$/g, '');

        if (key === 'name') {
          name = value;
        }
        if (key === 'description') {
          description = value;
        }
      }

      return {
        name: name || fallbackName,
        description: description || ''
      };
    } catch (_) {
      return { name: fallbackName, description: '' };
    }
  }

  // ================================================================
  // 路径解析
  // ================================================================

  /**
   * 在解压后的仓库目录中定位 Skill 源目录
   *
   * 三级回退策略：
   * 1. 直接匹配相对路径
   * 2. 按名称递归查找（深度 ≤ 3）
   * 3. 根目录有 SKILL.md 则使用根目录
   */
  private resolveSourceDir(root: string, rawDirectory: string): string | null {
    // 1. 直接匹配
    const direct = `${root}/${rawDirectory}`;
    try {
      const stat = fileIo.statSync(direct);
      if (stat.isDirectory()) {
        return direct;
      }
    } catch (_) { /* not found */ }

    // 2. 递归查找同名目录
    const parts = rawDirectory.split('/');
    const targetName = parts[parts.length - 1];
    const found = this.findDirByName(root, targetName, 0);
    if (found) {
      return found;
    }

    // 3. 根目录有 SKILL.md
    try {
      fileIo.statSync(`${root}/SKILL.md`);
      return root;
    } catch (_) { /* no SKILL.md at root */ }

    return null;
  }

  private findDirByName(dir: string, target: string, depth: number): string | null {
    if (depth > 3) {
      return null;
    }

    let entries: string[];
    try {
      entries = fileIo.listFileSync(dir);
    } catch (_) {
      return null;
    }

    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const fullPath = `${dir}/${entry}`;

      try {
        const stat = fileIo.statSync(fullPath);
        if (!stat.isDirectory()) {
          continue;
        }

        if (entry.toLowerCase() === target.toLowerCase()) {
          try {
            fileIo.statSync(`${fullPath}/SKILL.md`);
            return fullPath;
          } catch (_) { /* 同名目录无 SKILL.md */ }
        }

        const found = this.findDirByName(fullPath, target, depth + 1);
        if (found) {
          return found;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
