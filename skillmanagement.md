# ArkPilot Skills 管理方案

> 基于 cc-switch v3.14.1 Skills 管理体系的深度分析，完整适配 ArkPilot 单 Agent 架构的 Skills 全生命周期管理方案。
> 本文档可直接作为 AI 编码提示词使用，所有接口、数据结构、流程均已明确到可实现级别。

---

## 一、现状分析与目标

### 1.1 ArkPilot 已有能力（codex-rs 原版）

ArkPilot 的 Rust 后端（codex-rs）已经实现了一套完整的 Skills **运行时引擎**：

| 模块 | 位置 | 功能 |
|------|------|------|
| `core-skills::loader` | `codex-rs/core-skills/src/loader.rs` | 从多个根目录扫描 SKILL.md，解析 YAML frontmatter + `agents/openai.yaml` |
| `core-skills::manager` | `codex-rs/core-skills/src/manager.rs` | SkillsManager：缓存、按 cwd/config 加载、product 过滤 |
| `core-skills::injection` | `codex-rs/core-skills/src/injection.rs` | 按需读取 SKILL.md 全文注入模型上下文 |
| `core-skills::render` | `codex-rs/core-skills/src/render.rs` | 渲染 "## Skills" 系统提示段 |
| `core-skills::config_rules` | `codex-rs/core-skills/src/config_rules.rs` | 按名称/路径启用/禁用 Skill（写入 User 配置层） |
| `skills` | `codex-rs/skills/src/lib.rs` | 嵌入式系统 Skill 安装/卸载（`include_dir!`） |
| `core-skills::remote` | `codex-rs/core-skills/src/remote.rs` | ChatGPT API 远程 Skill 下载（**未接入产品表面**） |

Skill 加载的根目录体系（由 `loader::skill_roots()` 解析）：
- **User scope**：`$HOME/.agents/skills/`（用户安装的 Skill）
- **User scope (legacy)**：`{CODEX_HOME}/skills/`（已废弃但兼容）
- **System scope**：`{CODEX_HOME}/skills/.system/`（嵌入式系统 Skill 缓存）
- **Repo scope**：`{cwd → project_root}/.agents/skills/`（项目级 Skill）
- **Admin scope**：`/etc/codex/skills/`（管理员部署）

### 1.2 缺失的管理能力

codex-rs 的 Skill 系统是一个**消费引擎**，缺少完整的**管理平台**：

| 缺失能力 | cc-switch 对应实现 | 说明 |
|----------|-------------------|------|
| **从 GitHub 安装** | `install_skill_unified` | 输入 owner/repo/directory，下载 ZIP → 解压 → 复制到 SSOT → 注册 |
| **卸载 Skill** | `uninstall_skill_unified` | 备份 → 删除文件 → 移除注册 |
| **更新检测** | `check_skill_updates` | SHA-256 哈希对比，按仓库分组批量检测 |
| **应用更新** | `update_skill` | 备份旧版 → 下载新版 → 替换 → 同步 |
| **GitHub 仓库发现** | `discover_available_skills` | 扫描启用的 GitHub 仓库，找到所有含 SKILL.md 的目录 |
| **ZIP 导入/导出** | `install_skills_from_zip` | 从本地 ZIP 文件批量安装 Skill |
| **备份管理** | `get_skill_backups` / `restore_skill_backup` | 卸载前自动备份，支持查看和恢复 |
| **未管理扫描** | `scan_unmanaged_skills` | 在各应用目录中发现未被管理的 Skill |
| **skills.sh 搜索** | `search_skills_sh` | 搜索公共 Skill 目录 |
| **存储迁移** | `migrate_skill_storage` | 在 CC Switch 和统一目录间迁移 |
| **仓库管理** | `get_skill_repos` / `add_skill_repo` / `remove_skill_repo` | 管理 GitHub Skill 仓库列表 |

### 1.3 核心设计原则

| 原则 | 说明 |
|------|------|
| **SSOT 单一事实源** | `$HOME/.agents/skills/` 作为唯一权威存储目录 |
| **JSON 注册表** | `{CODEX_HOME}/skills-registry.json` 持久化已安装 Skill 的元数据 |
| **轻量集成** | 不修改 codex-rs 核心引擎，管理层的安装结果直接对接现有加载器 |
| **单 Agent** | 只有一个 Codex Agent，Skill 启用/禁用是简单布尔值，无多租户复杂 |
| **SHA-256 更新检测** | 复用 cc-switch 的哈希计算策略（排序文件路径 + 内容拼接后哈希） |
| **分支回退链** | GitHub 下载：指定分支 → main → master（与 cc-switch 一致） |
| **卸载即备份** | 卸载前自动备份到 `{CODEX_HOME}/skill-backups/`，保留最近 20 个 |

---

## 二、架构设计

```
┌──────────────────────────────────────────────────────────────┐
│                  ArkPilot Frontend (ArkTS)                    │
│                                                              │
│  ┌────────────────────┐  ┌──────────────────────────────┐   │
│  │ SkillsPage.ets     │  │ SkillsViewModel              │   │
│  │ (installed /       │  │ @State installed: Installed[] │   │
│  │  discover / search │  │ @State discoverable: Discov[] │   │
│  │  / backups panels) │  │ @State updates: UpdateInfo[]  │   │
│  └────────┬───────────┘  └─────────────┬────────────────┘   │
│           │                             │                     │
│  ┌────────┴─────────────────────────────┴────────────────┐  │
│  │              SkillsBackendService                      │  │
│  │  install() / uninstall() / update() / discover()       │  │
│  │  scanUnmanaged() / importFromLocal() / searchSh()      │  │
│  │  getBackups() / restoreBackup() / manageRepos()        │  │
│  └────────┬──────────────────────────┬───────────────────┘  │
│           │                          │                       │
│     HTTP 下载 / ZIP 解压        文件读写 / 哈希              │
│     (@kit.NetworkKit)           (@kit.CoreFileKit)           │
│           │                          │                       │
├───────────┼──────────────────────────┼───────────────────────┤
│           │    NAPI Bridge            │                       │
│           │    (libcodexhost.so)      │                       │
│           │                          │                       │
│  ┌────────┴──────────────────────────┴───────────────────┐  │
│  │          Rust ohos-host (新增 skills 模块)              │  │
│  │                                                        │  │
│  │  codex_ohos_host_skills_registry_json()                 │  │
│  │  codex_ohos_host_skills_save_registry()                 │  │
│  │  codex_ohos_host_skills_backups_json()                  │  │
│  │  codex_ohos_host_skills_delete_backup()                 │  │
│  │  codex_ohos_host_skills_repos_json()                    │  │
│  │  codex_ohos_host_skills_save_repo()                    │  │
│  │  codex_ohos_host_skills_delete_repo()                  │  │
│  │  codex_ohos_host_compute_dir_hash()                    │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  管理操作的持久化层（JSON 文件）：                              │
│  {CODEX_HOME}/skills-registry.json   (已安装 Skill 注册表)     │
│  {CODEX_HOME}/skills-repos.json      (GitHub 仓库列表)         │
│  {CODEX_HOME}/skill-backups/         (卸载备份目录)            │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│              已存在的 Runtime 引擎（不改动）                    │
│                                                              │
│  SkillsManager → 加载 $HOME/.agents/skills/                  │
│  → skills/list JSON-RPC → 前端获取运行时 Skill 列表             │
│  → skills/configWrite JSON-RPC → 前端切换启用/禁用              │
└──────────────────────────────────────────────────────────────┘
```

**分层职责**：
- **ArkTS**：HTTP 下载、ZIP 解压、文件复制、UI 交互、调用 NAPI 做哈希/读注册表
- **Rust/NAPI**：JSON 注册表读写、SHA-256 哈希计算、备份管理（薄层，托管 JSON 文件）
- **codex-rs app-server**：Skill 加载/渲染/注入，`skills/list` 和 `skills/configWrite`（不改动）

---

## 三、数据模型（ArkTS）

```typescript
// Agent/entry/src/main/ets/skills/SkillTypes.ets

/**
 * Skill 来源类型
 */
export type SkillSource = 'github' | 'local' | 'zip';

/**
 * 已安装 Skill 的注册记录（持久化到 skills-registry.json）
 */
export class InstalledSkill {
  id: string;            // "owner/repo:directory" 或 "local:directory"
  name: string;          // 显示名称（来自 SKILL.md frontmatter）
  description: string;   // 描述
  directory: string;     // SSOT 中的目录名（即 installName）
  source: SkillSource;

  // GitHub 来源专用
  repoOwner: string;
  repoName: string;
  repoBranch: string;

  // 本地/导入
  readmeUrl: string;
  enabled: boolean;        // 单 Agent，只有 enabled/disabled
  installedAt: number;     // 毫秒时间戳
  contentHash: string;     // SHA-256（用于更新检测）
  updatedAt: number;       // 毫秒时间戳，0 表示从未更新

  constructor(
    id: string, name: string, description: string, directory: string,
    source: SkillSource, repoOwner: string, repoName: string,
    repoBranch: string, readmeUrl: string, enabled: boolean,
    installedAt: number, contentHash: string, updatedAt: number
  ) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.directory = directory;
    this.source = source;
    this.repoOwner = repoOwner;
    this.repoName = repoName;
    this.repoBranch = repoBranch;
    this.readmeUrl = readmeUrl;
    this.enabled = enabled;
    this.installedAt = installedAt;
    this.contentHash = contentHash;
    this.updatedAt = updatedAt;
  }

  static fromJSON(json: Record<string, Object>): InstalledSkill {
    return new InstalledSkill(
      (json.id as string) ?? '',
      (json.name as string) ?? '',
      (json.description as string) ?? '',
      (json.directory as string) ?? '',
      (json.source as SkillSource) ?? 'local',
      (json.repoOwner as string) ?? '',
      (json.repoName as string) ?? '',
      (json.repoBranch as string) ?? '',
      (json.readmeUrl as string) ?? '',
      (json.enabled as boolean) ?? true,
      (json.installedAt as number) ?? Date.now(),
      (json.contentHash as string) ?? '',
      (json.updatedAt as number) ?? 0
    );
  }
}

/**
 * 可发现 Skill（来自 GitHub 仓库扫描的结果）
 */
export class DiscoverableSkill {
  key: string;           // "owner/repo:directory"
  name: string;
  description: string;
  directory: string;      // ZIP 内的相对路径
  readmeUrl: string;
  repoOwner: string;
  repoName: string;
  repoBranch: string;

  constructor(
    key: string, name: string, description: string, directory: string,
    readmeUrl: string, repoOwner: string, repoName: string, repoBranch: string
  ) {
    this.key = key;
    this.name = name;
    this.description = description;
    this.directory = directory;
    this.readmeUrl = readmeUrl;
    this.repoOwner = repoOwner;
    this.repoName = repoName;
    this.repoBranch = repoBranch;
  }
}

/**
 * 未管理 Skill（在 Agent skills 目录中发现但未注册）
 */
export class UnmanagedSkill {
  directory: string;
  name: string;
  description: string;
  foundIn: string[];     // 发现的目录路径列表
  path: string;          // 文件系统绝对路径

  constructor(
    directory: string, name: string, description: string,
    foundIn: string[], path: string
  ) {
    this.directory = directory;
    this.name = name;
    this.description = description;
    this.foundIn = foundIn;
    this.path = path;
  }
}

/**
 * GitHub Skill 仓库配置
 */
export class SkillRepo {
  owner: string;
  name: string;
  branch: string;
  enabled: boolean;

  constructor(owner: string, name: string, branch: string, enabled: boolean) {
    this.owner = owner;
    this.name = name;
    this.branch = branch;
    this.enabled = enabled;
  }

  static fromJSON(json: Record<string, Object>): SkillRepo {
    return new SkillRepo(
      (json.owner as string) ?? '',
      (json.name as string) ?? '',
      (json.branch as string) ?? 'main',
      (json.enabled as boolean) ?? true
    );
  }
}

/**
 * Skill 更新信息
 */
export class SkillUpdateInfo {
  id: string;
  name: string;
  currentHash: string;
  remoteHash: string;

  constructor(id: string, name: string, currentHash: string, remoteHash: string) {
    this.id = id;
    this.name = name;
    this.currentHash = currentHash;
    this.remoteHash = remoteHash;
  }
}

/**
 * Skill 备份条目
 */
export class SkillBackupEntry {
  backupId: string;
  backupPath: string;
  createdAt: number;
  skill: InstalledSkill;

  constructor(
    backupId: string, backupPath: string,
    createdAt: number, skill: InstalledSkill
  ) {
    this.backupId = backupId;
    this.backupPath = backupPath;
    this.createdAt = createdAt;
    this.skill = skill;
  }
}

/**
 * skills.sh 搜索结果
 */
export class SkillsShSearchResult {
  skills: SkillsShItem[];
  totalCount: number;
  query: string;

  constructor(skills: SkillsShItem[], totalCount: number, query: string) {
    this.skills = skills;
    this.totalCount = totalCount;
    this.query = query;
  }
}

export class SkillsShItem {
  key: string;
  name: string;
  directory: string;
  repoOwner: string;
  repoName: string;
  repoBranch: string;
  installs: number;
  readmeUrl: string;

  constructor(
    key: string, name: string, directory: string,
    repoOwner: string, repoName: string, repoBranch: string,
    installs: number, readmeUrl: string
  ) {
    this.key = key;
    this.name = name;
    this.directory = directory;
    this.repoOwner = repoOwner;
    this.repoName = repoName;
    this.repoBranch = repoBranch;
    this.installs = installs;
    this.readmeUrl = readmeUrl;
  }
}

/** 默认 GitHub 仓库列表（cc-switch 同款） */
export const DEFAULT_SKILL_REPOS: SkillRepo[] = [
  new SkillRepo('anthropics', 'skills', 'main', true),
  new SkillRepo('ComposioHQ', 'awesome-claude-skills', 'master', true),
  new SkillRepo('cexll', 'myclaude', 'master', true),
  new SkillRepo('JimLiu', 'baoyu-skills', 'main', true),
];
```

---

## 四、存储设计

### 4.1 文件布局

```
{CODEX_HOME}/
  config.toml                        ← app-server 配置（已有，不改动）
  harmony-provider.json              ← Provider 配置（已有）
  harmony-provider-catalog.json      ← Provider 目录（已有）
  skills-registry.json               ← [新增] 已安装 Skill 注册表
  skills-repos.json                  ← [新增] GitHub Skill 仓库列表
  skill-backups/                     ← [新增] 卸载前备份目录
    2026-04-30T12-34-56_some-skill/
      skill/                         ← Skill 文件副本
      meta.json                      ← 备份元数据 { skill, backupCreatedAt, sourcePath }

$HOME/.agents/skills/               ← SSOT（User scope 根目录，已有）
  some-skill/                        ← Skill 安装目录
    SKILL.md                         ← Skill 定义文件
    agents/openai.yaml               ← 可选元数据
    scripts/                         ← 可选脚本
    references/                      ← 可选参考文档
```

### 4.2 skills-registry.json 结构

```json
{
  "version": 1,
  "skills": [
    {
      "id": "anthropics/skills:skill-creator",
      "name": "skill-creator",
      "description": "Guide for creating effective skills",
      "directory": "skill-creator",
      "source": "github",
      "repoOwner": "anthropics",
      "repoName": "skills",
      "repoBranch": "main",
      "readmeUrl": "https://github.com/anthropics/skills/blob/main/skill-creator/SKILL.md",
      "enabled": true,
      "installedAt": 1714400000000,
      "contentHash": "a1b2c3d4e5f6...",
      "updatedAt": 0
    }
  ],
  "updatedAt": "1714400000"
}
```

### 4.3 skills-repos.json 结构

```json
{
  "version": 1,
  "repos": [
    { "owner": "anthropics", "name": "skills", "branch": "main", "enabled": true },
    { "owner": "ComposioHQ", "name": "awesome-claude-skills", "branch": "master", "enabled": true },
    { "owner": "cexll", "name": "myclaude", "branch": "master", "enabled": true },
    { "owner": "JimLiu", "name": "baoyu-skills", "branch": "main", "enabled": true }
  ]
}
```

### 4.4 为什么用 JSON 而不是 RDB

ArkPilot 现有数据持久化采用 JSON 文件模式（`harmony-provider.json`、`harmony-provider-catalog.json`），Skills 管理层遵循同一模式：
- 数据量小（通常 < 100 条记录）
- 便于调试和手动修复
- 无需引入 SQLite 依赖（ArkPilot ohos-host 目前不链接 rusqlite）
- 与现有 NAPI FFI 模式一致

---

## 五、Rust 后端（ohos-host 新增 NAPI）

### 5.1 模块设计

在 `ohos-host/src/` 下新增文件，暴露以下 NAPI 函数：

```
ohos-host/src/
  lib.rs                  ← 已有，新增 skills 模块注册
  skills_registry.rs      ← [新增] Skills 注册表管理
  skills_backup.rs        ← [新增] 备份管理
  skills_hash.rs          ← [新增] SHA-256 哈希工具
```

### 5.2 skills_registry.rs

```rust
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

/// Skills 注册表（持久化到 skills-registry.json）
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillsRegistry {
    pub version: u32,
    pub skills: Vec<InstalledSkillEntry>,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstalledSkillEntry {
    pub id: String,
    pub name: String,
    pub description: String,
    pub directory: String,
    pub source: String,           // "github" | "local" | "zip"
    pub repo_owner: String,
    pub repo_name: String,
    pub repo_branch: String,
    pub readme_url: String,
    pub enabled: bool,
    pub installed_at: i64,
    pub content_hash: String,
    pub updated_at: i64,
}

/// Skills 仓库列表（持久化到 skills-repos.json）
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillsRepoList {
    pub version: u32,
    pub repos: Vec<SkillRepoEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillRepoEntry {
    pub owner: String,
    pub name: String,
    pub branch: String,
    pub enabled: bool,
}

impl SkillsRegistry {
    pub fn load_or_default(codex_home: &Path) -> Self {
        let path = codex_home.join("skills-registry.json");
        if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default()
        } else {
            Self::default()
        }
    }

    pub fn save(&self, codex_home: &Path) -> Result<(), String> {
        let path = codex_home.join("skills-registry.json");
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(&path, json).map_err(|e| e.to_string())
    }

    pub fn find_by_id(&self, id: &str) -> Option<&InstalledSkillEntry> {
        self.skills.iter().find(|s| s.id == id)
    }

    pub fn find_by_directory(&self, directory: &str) -> Option<&InstalledSkillEntry> {
        self.skills.iter().find(|s| s.directory.eq_ignore_ascii_case(directory))
    }

    pub fn upsert(&mut self, skill: InstalledSkillEntry) {
        if let Some(pos) = self.skills.iter().position(|s| s.id == skill.id) {
            self.skills[pos] = skill;
        } else {
            self.skills.push(skill);
        }
        self.updated_at = current_timestamp_string();
    }

    pub fn remove(&mut self, id: &str) -> Option<InstalledSkillEntry> {
        if let Some(pos) = self.skills.iter().position(|s| s.id == skill.id) {
            let removed = self.skills.remove(pos);
            self.updated_at = current_timestamp_string();
            Some(removed)
        } else {
            None
        }
    }
}

impl Default for SkillsRegistry {
    fn default() -> Self {
        Self {
            version: 1,
            skills: Vec::new(),
            updated_at: current_timestamp_string(),
        }
    }
}

impl SkillsRepoList {
    pub fn load_or_default(codex_home: &Path) -> Self {
        let path = codex_home.join("skills-repos.json");
        if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| Self::with_defaults())
        } else {
            let default = Self::with_defaults();
            let _ = default.save(codex_home);
            default
        }
    }

    pub fn save(&self, codex_home: &Path) -> Result<(), String> {
        let path = codex_home.join("skills-repos.json");
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(&path, json).map_err(|e| e.to_string())
    }

    fn with_defaults() -> Self {
        Self {
            version: 1,
            repos: vec![
                SkillRepoEntry { owner: "anthropics".into(), name: "skills".into(), branch: "main".into(), enabled: true },
                SkillRepoEntry { owner: "ComposioHQ".into(), name: "awesome-claude-skills".into(), branch: "master".into(), enabled: true },
                SkillRepoEntry { owner: "cexll".into(), name: "myclaude".into(), branch: "master".into(), enabled: true },
                SkillRepoEntry { owner: "JimLiu".into(), name: "baoyu-skills".into(), branch: "main".into(), enabled: true },
            ],
        }
    }
}

fn current_timestamp_string() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|_| "0".into())
}
```

### 5.3 skills_hash.rs

```rust
use sha2::{Digest, Sha256};
use std::path::Path;

/// 计算目录内容 SHA-256 哈希
///
/// 与 cc-switch SkillService::compute_dir_hash 策略一致：
/// 1. 递归收集所有非隐藏文件
/// 2. 按文件路径排序（确保确定性）
/// 3. 对每个文件：写入相对路径 + \0 + 文件内容 + \0
/// 4. 返回 hex 编码的 SHA-256
pub fn compute_dir_hash(dir_path: &Path) -> Result<String, String> {
    let mut files = Vec::new();
    collect_files(dir_path, dir_path, &mut files)?;
    files.sort();

    let mut hasher = Sha256::new();
    for relative_path in &files {
        let full_path = dir_path.join(relative_path);
        let content = std::fs::read(&full_path)
            .map_err(|e| format!("read {}: {}", full_path.display(), e))?;

        hasher.update(relative_path.as_bytes());
        hasher.update(&[0u8]);
        hasher.update(&content);
        hasher.update(&[0u8]);
    }

    let result = hasher.finalize();
    Ok(hex::encode(result))
}

fn collect_files(base: &Path, current: &Path, result: &mut Vec<String>) -> Result<(), String> {
    let entries = std::fs::read_dir(current)
        .map_err(|e| format!("read_dir {}: {}", current.display(), e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("entry err: {}", e))?;
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy();

        // 跳过隐藏文件和目录
        if name.starts_with('.') {
            continue;
        }

        let path = entry.path();
        if path.is_dir() {
            collect_files(base, &path, result)?;
        } else {
            let relative = path.strip_prefix(base)
                .map_err(|e| format!("strip_prefix: {}", e))?;
            result.push(relative.to_string_lossy().into_owned());
        }
    }
    Ok(())
}
```

### 5.4 skills_backup.rs

```rust
use std::path::{Path, PathBuf};

/// 创建卸载前备份
///
/// 操作流程：
/// 1. 在 {codex_home}/skill-backups/ 下创建时间戳子目录
/// 2. 复制 Skill 文件到 backup/skill/
/// 3. 写入 meta.json（含 skill 元数据和创建时间）
/// 4. 清理旧备份（保留最近 20 个）
pub fn create_uninstall_backup(
    codex_home: &Path,
    skill_dir: &Path,
    skill_json: &str,
) -> Result<PathBuf, String> {
    let backup_root = codex_home.join("skill-backups");
    std::fs::create_dir_all(&backup_root)
        .map_err(|e| format!("create backup dir: {}", e))?;

    let timestamp = chrono::Utc::now().format("%Y-%m-%dT%H-%M-%S").to_string();
    let dir_name = skill_dir.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");
    let backup_id = format!("{}_{}", timestamp, dir_name);
    let backup_path = backup_root.join(&backup_id);

    // 复制 Skill 文件
    let skill_dest = backup_path.join("skill");
    copy_dir_recursive(skill_dir, &skill_dest)?;

    // 写入元数据
    let meta = serde_json::json!({
        "skill": serde_json::from_str::<serde_json::Value>(skill_json).unwrap_or_default(),
        "backupCreatedAt": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0),
        "sourcePath": skill_dir.to_string_lossy(),
    });
    let meta_json = serde_json::to_string_pretty(&meta)
        .map_err(|e| format!("serialize meta: {}", e))?;
    std::fs::write(backup_path.join("meta.json"), meta_json)
        .map_err(|e| format!("write meta: {}", e))?;

    // 清理旧备份
    cleanup_old_backups(&backup_root, 20);

    Ok(backup_path)
}

fn copy_dir_recursive(src: &Path, dest: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dest)
        .map_err(|e| format!("mkdir {}: {}", dest.display(), e))?;

    let entries = std::fs::read_dir(src)
        .map_err(|e| format!("read_dir {}: {}", src.display(), e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("entry: {}", e))?;
        let src_path = entry.path();
        let dest_path = dest.join(entry.file_name());

        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dest_path)?;
        } else {
            std::fs::copy(&src_path, &dest_path)
                .map_err(|e| format!("copy {} -> {}: {}", src_path.display(), dest_path.display(), e))?;
        }
    }
    Ok(())
}

fn cleanup_old_backups(backup_root: &Path, max_keep: usize) {
    let mut backups: Vec<_> = match std::fs::read_dir(backup_root) {
        Ok(entries) => entries
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_dir())
            .collect(),
        Err(_) => return,
    };

    if backups.len() <= max_keep {
        return;
    }

    // 按修改时间排序，删除最旧的
    backups.sort_by_key(|e| {
        e.metadata()
            .and_then(|m| m.modified())
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH)
    });

    for entry in backups.iter().take(backups.len() - max_keep) {
        let _ = std::fs::remove_dir_all(entry.path());
    }
}
```

### 5.5 NAPI 导出（lib.rs 新增）

```rust
// 在 ohos-host/src/lib.rs 中新增以下 NAPI 导出函数：

// ========== Skills Registry ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_skills_registry_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let registry = SkillsRegistry::load_or_default(&codex_home);
    let json = serde_json::to_string(&registry).unwrap_or_else(|_| "{}".into());
    write_cstring(&LAST_SKILLS_REGISTRY_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_skills_registry(
    codex_home: *const c_char,
    registry_json: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(json_str) = ffi_string(registry_json) else { return 1; };
    let registry: SkillsRegistry = match serde_json::from_str(&json_str) {
        Ok(r) => r,
        Err(_) => return 1,
    };
    match registry.save(&codex_home) {
        Ok(()) => 0,
        Err(_) => 1,
    }
}

// ========== Skills Repos ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_skills_repos_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let repos = SkillsRepoList::load_or_default(&codex_home);
    let json = serde_json::to_string(&repos).unwrap_or_else(|_| "{}".into());
    write_cstring(&LAST_SKILLS_REPOS_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_skills_repos(
    codex_home: *const c_char,
    repos_json: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(json_str) = ffi_string(repos_json) else { return 1; };
    let repos: SkillsRepoList = match serde_json::from_str(&json_str) {
        Ok(r) => r,
        Err(_) => return 1,
    };
    match repos.save(&codex_home) {
        Ok(()) => 0,
        Err(_) => 1,
    }
}

// ========== Skills Hash ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_compute_dir_hash(dir_path: *const c_char) -> *const c_char {
    let Some(path_str) = ffi_string(dir_path) else {
        return write_cstring(&LAST_HASH_RESULT, "");
    };
    let hash = skills_hash::compute_dir_hash(Path::new(&path_str))
        .unwrap_or_default();
    write_cstring(&LAST_HASH_RESULT, &hash)
}

// ========== Skills Backups ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_skills_backups_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let backups = list_backups(&codex_home);
    let json = serde_json::to_string(&backups).unwrap_or_else(|_| "[]".into());
    write_cstring(&LAST_BACKUPS_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_create_skill_backup(
    codex_home: *const c_char,
    skill_dir: *const c_char,
    skill_json: *const c_char,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let skill_dir = PathBuf::from(ffi_string(skill_dir).unwrap_or_default());
    let skill_json = ffi_string(skill_json).unwrap_or_default();

    match skills_backup::create_uninstall_backup(&codex_home, &skill_dir, &skill_json) {
        Ok(path) => write_cstring(&LAST_BACKUP_PATH, &path.to_string_lossy()),
        Err(e) => write_cstring(&LAST_BACKUP_PATH, &format!("error:{}", e)),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_delete_skill_backup(
    codex_home: *const c_char,
    backup_id: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(backup_id) = ffi_string(backup_id) else { return 1; };

    // 安全检查：防止路径穿越
    if backup_id.contains("..") || backup_id.contains('/') || backup_id.contains('\\') {
        return 1;
    }

    let backup_path = codex_home.join("skill-backups").join(&backup_id);
    match std::fs::remove_dir_all(&backup_path) {
        Ok(()) => 0,
        Err(_) => 1,
    }
}
```

### 5.6 编译配置更新

`CMakeLists.txt` 需新增 Rust crate 依赖（如果 `skills_hash.rs` 使用 `sha2` 和 `hex` crate）：

```toml
# codex-rs/ohos-host/Cargo.toml 新增依赖
[dependencies]
sha2 = "0.10"
hex = "0.4"
chrono = "0.4"
serde_json = "1"   # 已有
```

---

## 六、ArkTS 前端实现

### 6.1 SkillsBackendService（核心管理逻辑）

```typescript
// Agent/entry/src/main/ets/skills/SkillsBackendService.ets

import { codexHost } from '../backend/CodexHostNative';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import {
  InstalledSkill, DiscoverableSkill, UnmanagedSkill, SkillRepo,
  SkillUpdateInfo, SkillBackupEntry, SkillsShSearchResult, SkillsShItem,
  DEFAULT_SKILL_REPOS, SkillSource
} from './SkillTypes';

const GITHUB_API_BASE = 'https://github.com';
const SKILLS_SH_API = 'https://skills.sh/api/search';
const DOWNLOAD_TIMEOUT_MS = 60000;
const MAX_SCAN_DEPTH = 6;

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
 *
 * 持久化：通过 NAPI 调用 Rust 层读写 JSON 注册表文件
 */
export class SkillsBackendService {
  private codexHome: string;
  private napi: CodexHostNative;

  constructor(codexHome: string, napi: CodexHostNative) {
    this.codexHome = codexHome;
    this.napi = napi;
  }

  /** SSOT 目录（User scope skills root） */
  getSsotDir(): string {
    // $HOME/.agents/skills/ — 已存在的 SkillsManager 会扫描此目录
    return `${this.codexHome}/../.agents/skills`;
  }

  /** 备份目录 */
  getBackupDir(): string {
    return `${this.codexHome}/skill-backups`;
  }

  // ================================================================
  // 路径安全校验（防御路径穿越）
  // ================================================================

  private sanitizeSourcePath(raw: string): string | null {
    const trimmed = raw.trim();
    if (trimmed.length === 0) return null;

    const parts = trimmed.split('/').filter(p => p.length > 0);
    if (parts.length === 0) return null;

    for (const part of parts) {
      if (part === '.' || part === '..' || part.trim().length === 0) {
        return null;
      }
    }
    return parts.join('/');
  }

  private sanitizeInstallName(raw: string): string | null {
    const trimmed = raw.trim();
    if (trimmed.length === 0 || trimmed.startsWith('.')) return null;
    if (trimmed === '.' || trimmed === '..') return null;
    if (trimmed.includes('/') || trimmed.includes('\\')) return null;
    if (!/^[a-zA-Z0-9\-_]+$/.test(trimmed)) return null;
    return trimmed;
  }

  // ================================================================
  // 已安装 Skill 管理
  // ================================================================

  /** 获取所有已安装 Skill 列表 */
  async getInstalled(): Promise<InstalledSkill[]> {
    const json = await this.napi.getSkillsRegistry();
    const parsed = JSON.parse(json);
    const skills = (parsed.skills ?? []) as Record<string, Object>[];
    return skills.map(s => InstalledSkill.fromJSON(s));
  }

  /** 保存 Skill 到注册表 */
  private async saveInstalled(skills: InstalledSkill[]): Promise<void> {
    const registry = {
      version: 1,
      skills: skills,
      updatedAt: String(Math.floor(Date.now() / 1000))
    };
    await this.napi.saveSkillsRegistry(JSON.stringify(registry));
  }

  /**
   * 安装 Skill（完整 7 步流程）
   *
   * Step 1: 校验路径安全
   * Step 2: 冲突检测（检查同名目录和 ID）
   * Step 3: 下载 GitHub 仓库 ZIP（分支回退：指定 → main → master）
   * Step 4: 解压并定位 Skill 源目录（三级回退）
   * Step 5: 复制到 SSOT
   * Step 6: 解析 SKILL.md 元数据（name、description）
   * Step 7: 保存注册表 → 计算哈希
   */
  async installFromGithub(skill: DiscoverableSkill): Promise<InstalledSkill> {
    // Step 1: 校验
    const sourceRel = this.sanitizeSourcePath(skill.directory);
    if (!sourceRel) {
      throw new SkillError('INVALID_SKILL_DIRECTORY',
        { directory: skill.directory }, '目录路径不合法，请检查是否包含非法字符');
    }

    const segments = sourceRel.split('/');
    const installName = this.sanitizeInstallName(segments[segments.length - 1]);
    if (!installName) {
      throw new SkillError('INVALID_SKILL_DIRECTORY',
        { directory: skill.directory }, '安装目录名不合法');
    }

    // Step 2: 冲突检测
    const installed = await this.getInstalled();
    for (const existing of installed) {
      if (existing.directory.toLowerCase() === installName.toLowerCase()) {
        const sameRepo = existing.repoOwner === skill.repoOwner
          && existing.repoName === skill.repoName;
        if (sameRepo) {
          // 同一仓库同名 Skill：已安装，直接返回
          if (!existing.enabled) {
            existing.enabled = true;
            await this.saveInstalled(installed);
          }
          return existing;
        } else {
          throw new SkillError('SKILL_DIRECTORY_CONFLICT',
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

    // 定位 Skill 源目录
    const sourceDir = this.resolveSourceDir(tempDir, skill.directory);
    if (!sourceDir) {
      await this.removeDir(tempDir);
      throw new SkillError('SKILL_DIR_NOT_FOUND',
        { directory: skill.directory, repo: `${skill.repoOwner}/${skill.repoName}` },
        `在 ${skill.repoOwner}/${skill.repoName} 中未找到目录 ${skill.directory}`);
    }

    // 复制到 SSOT
    const ssotDir = this.getSsotDir();
    const dest = `${ssotDir}/${installName}`;
    await fileIo.mkdir(ssotDir, true);
    await this.copyDirRecursive(sourceDir, dest);

    // 清理临时目录
    await this.removeDir(tempDir);

    // Step 6: 解析 SKILL.md
    const { name, description } = await this.parseSkillMetadata(`${dest}/SKILL.md`, installName);

    // 构建 readmeUrl
    const readmeUrl = `https://github.com/${skill.repoOwner}/${skill.repoName}/blob/${usedBranch}/${skill.directory}/SKILL.md`;

    // Step 7: 计算哈希并保存
    const contentHash = await this.napi.computeDirHash(dest);

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
   *
   * 流程：
   * 1. 创建备份（copy Skill 到 backup 目录 + 写 meta.json）
   * 2. 从 SSOT 删除文件
   * 3. 从注册表移除
   */
  async uninstall(id: string): Promise<string | null> {
    const installed = await this.getInstalled();
    const index = installed.findIndex(s => s.id === id);
    if (index === -1) {
      throw new SkillError('SKILL_NOT_FOUND', { id }, '未找到指定的 Skill，可能已被卸载');
    }

    const skill = installed[index];

    // 备份
    let backupPath: string | null = null;
    try {
      const skillDir = `${this.getSsotDir()}/${skill.directory}`;
      backupPath = await this.napi.createSkillBackup(skillDir, JSON.stringify(skill));
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
   *
   * 流程：
   * 1. 备份旧文件
   * 2. 重新下载仓库
   * 3. 替换 SSOT 中的文件
   * 4. 重新计算哈希、更新注册表
   */
  async update(id: string): Promise<InstalledSkill> {
    const installed = await this.getInstalled();
    const index = installed.findIndex(s => s.id === id);
    if (index === -1) {
      throw new SkillError('SKILL_NOT_FOUND', { id }, '');
    }

    const skill = installed[index];
    if (skill.source !== 'github' || !skill.repoOwner || !skill.repoName) {
      throw new SkillError('UPDATE_NOT_SUPPORTED', { id, source: skill.source },
        '仅支持更新来自 GitHub 的 Skill');
    }

    const repo: SkillRepo = {
      owner: skill.repoOwner,
      name: skill.repoName,
      branch: skill.repoBranch || 'main',
      enabled: true
    };

    // 下载
    const { tempDir, usedBranch } = await this.downloadAndExtractRepo(repo);

    // 定位源目录
    const sourceDir = this.resolveSourceDir(tempDir, skill.directory);
    if (!sourceDir) {
      await this.removeDir(tempDir);
      throw new SkillError('SKILL_DIR_NOT_FOUND', { directory: skill.directory }, '');
    }

    // 备份旧文件（best-effort）
    try {
      await this.napi.createSkillBackup(
        `${this.getSsotDir()}/${skill.directory}`,
        JSON.stringify(skill)
      );
    } catch (_) { /* 备份失败不中断更新 */ }

    // 替换文件
    const dest = `${this.getSsotDir()}/${skill.directory}`;
    await this.removeDir(dest);
    await this.copyDirRecursive(sourceDir, dest);
    await this.removeDir(tempDir);

    // 重新计算
    const contentHash = await this.napi.computeDirHash(dest);
    const { name, description } = await this.parseSkillMetadata(`${dest}/SKILL.md`, skill.directory);

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

  /**
   * 从启用的 GitHub 仓库发现可安装 Skills
   *
   * 并发获取所有启用仓库的 ZIP，扫描其中包含 SKILL.md 的目录。
   * 去重策略：基于 key (owner/name:directory) 去重。
   */
  async discoverFromRepos(): Promise<DiscoverableSkill[]> {
    const reposJson = await this.napi.getSkillsRepos();
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
      if (seen.has(lower)) return false;
      seen.add(lower);
      return true;
    });

    unique.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
    return unique;
  }

  /** 从单个仓库获取 Skills 列表 */
  private async fetchRepoSkills(repo: SkillRepo): Promise<DiscoverableSkill[]> {
    const { tempDir, usedBranch } = await this.downloadAndExtractRepo(repo);
    const skills = await this.scanDirRecursive(tempDir, tempDir, repo, usedBranch);
    await this.removeDir(tempDir);
    return skills;
  }

  /** 递归扫描目录查找 SKILL.md */
  private async scanDirRecursive(
    currentDir: string, baseDir: string,
    repo: SkillRepo, usedBranch: string
  ): Promise<DiscoverableSkill[]> {
    const results: DiscoverableSkill[] = [];

    // 检查当前目录是否包含 SKILL.md
    const skillMdPath = `${currentDir}/SKILL.md`;
    try {
      await fileIo.stat(skillMdPath);

      const directory = currentDir === baseDir
        ? repo.name
        : currentDir.substring(baseDir.length + 1);

      const { name, description } = await this.parseSkillMetadata(skillMdPath, directory);

      results.push(new DiscoverableSkill(
        `${repo.owner}/${repo.name}:${directory}`,
        name, description, directory,
        `https://github.com/${repo.owner}/${repo.name}/blob/${usedBranch}/${directory}/SKILL.md`,
        repo.owner, repo.name, usedBranch
      ));

      return results; // 找到 SKILL.md 后不递归子目录
    } catch (_) { /* 当前目录无 SKILL.md，继续子目录 */ }

    // 递归子目录
    try {
      const entries = await fileIo.listFile(currentDir);
      for (const entry of entries) {
        if (entry.startsWith('.')) continue;
        const fullPath = `${currentDir}/${entry}`;
        try {
          const stat = await fileIo.stat(fullPath);
          if (stat.isDirectory()) {
            results.push(...await this.scanDirRecursive(fullPath, baseDir, repo, usedBranch));
          }
        } catch (_) { /* skip */ }
      }
    } catch (_) { /* skip */ }

    return results;
  }

  /**
   * 扫描未管理的 Skills
   *
   * 扫描 SSOT 目录中未被注册表管理的 Skill 目录（含 SKILL.md 但无注册项）
   */
  async scanUnmanaged(): Promise<UnmanagedSkill[]> {
    const installed = await this.getInstalled();
    const managedDirs = new Set(installed.map(s => s.directory.toLowerCase()));

    const ssotDir = this.getSsotDir();
    const unmanaged: UnmanagedSkill[] = [];

    let entries: string[];
    try {
      entries = await fileIo.listFile(ssotDir);
    } catch (_) { return unmanaged; }

    for (const entry of entries) {
      if (entry.startsWith('.') || managedDirs.has(entry.toLowerCase())) continue;

      const skillMdPath = `${ssotDir}/${entry}/SKILL.md`;
      try {
        await fileIo.stat(skillMdPath);
      } catch (_) { continue; }

      const { name, description } = await this.parseSkillMetadata(skillMdPath, entry);
      unmanaged.push(new UnmanagedSkill(
        entry, name, description, [ssotDir], `${ssotDir}/${entry}`
      ));
    }

    return unmanaged;
  }

  /**
   * 从本地目录导入 Skill
   *
   * 将未管理的 Skill 目录复制到 SSOT 并注册。
   */
  async importFromLocal(directories: string[]): Promise<InstalledSkill[]> {
    const installed = await this.getInstalled();
    const imported: InstalledSkill[] = [];
    const ssotDir = this.getSsotDir();

    for (const sourcePath of directories) {
      const dirName = sourcePath.split('/').pop()!;
      const installName = this.sanitizeInstallName(dirName);
      if (!installName) continue;

      // 检查冲突
      if (installed.some(s => s.directory.toLowerCase() === installName.toLowerCase())) {
        continue;
      }

      // 复制到 SSOT
      const dest = `${ssotDir}/${installName}`;
      await this.copyDirRecursive(sourcePath, dest);

      // 解析元数据
      const { name, description } = await this.parseSkillMetadata(`${dest}/SKILL.md`, installName);
      const contentHash = await this.napi.computeDirHash(dest);

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

  /**
   * 检查所有 GitHub 来源 Skill 的更新
   *
   * 策略（与 cc-switch 一致）：
   * - 按 (owner, name, branch) 分组
   * - 每组只下载一次 ZIP
   * - 用 SHA-256 哈希比对每个 Skill 是否有变化
   */
  async checkUpdates(): Promise<SkillUpdateInfo[]> {
    const installed = (await this.getInstalled())
      .filter(s => s.source === 'github' && s.repoOwner && s.repoName);

    const updates: SkillUpdateInfo[] = [];

    // 按仓库分组
    const groups = new Map<string, InstalledSkill[]>();
    for (const skill of installed) {
      const branch = skill.repoBranch || 'main';
      const key = `${skill.repoOwner}/${skill.repoName}/${branch}`;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key)!.push(skill);
    }

    for (const [key, groupSkills] of groups) {
      const [owner, name, branch] = key.split('/');
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
        if (!remoteDir) continue;

        const remoteHash = await this.napi.computeDirHash(remoteDir);

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
        const [owner, repo] = (s.source as string).split('/');
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
    const json = await this.napi.getSkillsBackups();
    return JSON.parse(json) as SkillBackupEntry[];
  }

  async deleteBackup(backupId: string): Promise<void> {
    await this.napi.deleteSkillBackup(backupId);
  }

  async restoreBackup(backupId: string): Promise<InstalledSkill> {
    const backups = await this.getBackups();
    const backup = backups.find(b => b.backupId === backupId);
    if (!backup) {
      throw new SkillError('BACKUP_NOT_FOUND', { backupId }, '备份文件不存在或被清理');
    }

    // 检查是否已存在
    const installed = await this.getInstalled();
    if (installed.some(s => s.id === backup.skill.id)) {
      throw new SkillError('SKILL_DIRECTORY_CONFLICT',
        { directory: backup.skill.directory }, '同名 Skill 已存在，请先卸载');
    }

    // 恢复到 SSOT
    const dest = `${this.getSsotDir()}/${backup.skill.directory}`;
    const backupSkillDir = `${backup.backupPath}/skill`;
    await this.copyDirRecursive(backupSkillDir, dest);

    // 更新注册表
    const restored = InstalledSkill.fromJSON(backup.skill as Object as Record<string, Object>);
    restored.installedAt = Date.now();
    restored.updatedAt = 0;
    restored.enabled = true;

    try {
      restored.contentHash = await this.napi.computeDirHash(dest);
    } catch (_) { /* 哈希计算不应中断恢复 */ }

    installed.push(restored);
    await this.saveInstalled(installed);

    return restored;
  }

  // ================================================================
  // 仓库管理
  // ================================================================

  async getRepos(): Promise<SkillRepo[]> {
    const json = await this.napi.getSkillsRepos();
    const parsed = JSON.parse(json);
    return (parsed.repos ?? []).map((r: Record<string, Object>) => SkillRepo.fromJSON(r));
  }

  async saveRepos(repos: SkillRepo[]): Promise<void> {
    const repoList = { version: 1, repos: repos };
    await this.napi.saveSkillsRepos(JSON.stringify(repoList));
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

  /**
   * 下载 GitHub 仓库 ZIP 并解压到临时目录
   *
   * 分支回退链：指定分支 → main → master
   * 超时：60 秒
   */
  private async downloadAndExtractRepo(
    repo: SkillRepo
  ): Promise<{ tempDir: string; usedBranch: string }> {
    const branches = [repo.branch];
    if (repo.branch !== 'main') branches.push('main');
    if (repo.branch !== 'master') branches.push('master');

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
        await fileIo.mkdir(tempDir, true);

        // 解压 ZIP
        const zipData = response.result as ArrayBuffer;
        await this.extractZip(zipData, tempDir);

        return { tempDir, usedBranch: branch };
      } catch (e) {
        lastError = e as Error;
        continue;
      }
    }

    throw lastError || new Error(`All branches failed for ${repo.owner}/${repo.name}`);
  }

  /**
   * 解压 ZIP 文件
   *
   * GitHub ZIP 文件结构：所有内容在一个根目录下（{repoName}-{branch}/），
   * 解压时需要去掉这一层前缀（strip prefix）。
   */
  private async extractZip(zipData: ArrayBuffer, destDir: string): Promise<void> {
    // 使用 @ohos.zlib 进行 ZIP 解压
    // 如果鸿蒙 zlib API 不支持完整 ZIP 解析，可引入 zip.js 等纯 JS 库
    const options: zlib.Options = {
      level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
    };

    try {
      const decompressed = await zlib.decompress(zipData, undefined, options);
      // 解析 ZIP 内部结构并写入文件
      // 具体实现取决于鸿蒙 zlib 对 ZIP 格式的支持程度
      // 如不支持完整 ZIP，备选方案：
      //   1. 引入 zip.js (https://github.com/gildas-lormeau/zip.js)
      //   2. 通过 NAPI 调用 Rust zip crate
      await this.writeZipEntries(decompressed, destDir);
    } catch (e) {
      throw new Error(`ZIP extraction failed: ${e}`);
    }
  }

  private async writeZipEntries(data: ArrayBuffer, destDir: string): Promise<void> {
    // ZIP 文件解析的完整实现
    // 遍历 ZIP entries，去掉第一层目录前缀，写入 destDir
    // 对于 symlink（GitHub ZIP 保留 symlink 元数据），复制目标文件内容
  }

  // ================================================================
  // 文件操作
  // ================================================================

  /** 递归复制目录 */
  private async copyDirRecursive(src: string, dest: string): Promise<void> {
    await fileIo.mkdir(dest, true);

    const files = await fileIo.listFile(src);
    for (const file of files) {
      const srcPath = `${src}/${file}`;
      const destPath = `${dest}/${file}`;

      try {
        const stat = await fileIo.stat(srcPath);
        if (stat.isDirectory()) {
          await this.copyDirRecursive(srcPath, destPath);
        } else {
          await fileIo.copyFile(srcPath, destPath);
        }
      } catch (e) {
        // 跳过无法访问的文件
        console.warn(`copy failed: ${srcPath} -> ${destPath}: ${e}`);
      }
    }
  }

  /** 递归删除目录 */
  private async removeDir(path: string): Promise<void> {
    try {
      await fileIo.rmdir(path);
    } catch (_) { /* ignore */ }
  }

  // ================================================================
  // SKILL.md 解析
  // ================================================================

  /**
   * 解析 SKILL.md 的 YAML front matter
   *
   * 格式：
   * ---
   * name: My Skill
   * description: Does something
   * ---
   * # Content...
   */
  private async parseSkillMetadata(
    skillMdPath: string,
    fallbackName: string
  ): Promise<{ name: string; description: string }> {
    try {
      const content = await fileIo.readText(skillMdPath);
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
        if (colonIdx === -1) continue;

        const key = line.substring(0, colonIdx).trim();
        const value = line.substring(colonIdx + 1).trim().replace(/^['"]|['"]$/g, '');

        if (key === 'name') name = value;
        if (key === 'description') description = value;
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
   * 三级回退策略（与 cc-switch resolve_skill_source_dir 一致）：
   * 1. 直接匹配相对路径
   * 2. 按名称递归查找（深度 ≤ 3）
   * 3. 根目录有 SKILL.md 则使用根目录
   */
  private resolveSourceDir(root: string, rawDirectory: string): string | null {
    // 1. 直接匹配
    const direct = `${root}/${rawDirectory}`;
    try {
      const stat = fileIo.statSync(direct);
      if (stat.isDirectory()) return direct;
    } catch (_) { /* not found */ }

    // 2. 递归查找同名目录
    const targetName = rawDirectory.split('/').pop()!;
    const found = this.findDirByName(root, targetName, 0);
    if (found) return found;

    // 3. 根目录有 SKILL.md
    try {
      fileIo.statSync(`${root}/SKILL.md`);
      return root;
    } catch (_) { /* no SKILL.md at root */ }

    return null;
  }

  private findDirByName(dir: string, target: string, depth: number): string | null {
    if (depth > 3) return null;

    let entries: string[];
    try {
      entries = fileIo.listFileSync(dir);
    } catch (_) { return null; }

    for (const entry of entries) {
      if (entry.startsWith('.')) continue;
      const fullPath = `${dir}/${entry}`;

      try {
        const stat = fileIo.statSync(fullPath);
        if (!stat.isDirectory()) continue;

        if (entry.toLowerCase() === target.toLowerCase()) {
          try {
            fileIo.statSync(`${fullPath}/SKILL.md`);
            return fullPath;
          } catch (_) { /* 同名目录无 SKILL.md */ }
        }

        const found = this.findDirByName(fullPath, target, depth + 1);
        if (found) return found;
      } catch (_) { continue; }
    }
    return null;
  }
}

// ================================================================
// 错误类型
// ================================================================

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

// 用户友好错误消息
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
```

### 6.2 SkillsViewModel（状态管理）

```typescript
// Agent/entry/src/main/ets/skills/SkillsViewModel.ets

import { SkillsBackendService, SkillError } from './SkillsBackendService';
import {
  InstalledSkill, DiscoverableSkill, UnmanagedSkill,
  SkillRepo, SkillUpdateInfo, SkillBackupEntry, SkillsShSearchResult
} from './SkillTypes';

/**
 * Skills ViewModel — ArkPilot 上的状态管理
 *
 * 使用 @State 装饰器实现响应式 UI 绑定。
 * 对标 cc-switch 的 React Query hooks：
 * - staleTime 机制：首次加载后短期缓存，手动刷新才重新获取
 * - 乐观更新：install/uninstall 直接操作本地列表
 */
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
  private readonly STALE_TIME_MS = 5 * 60 * 1000; // 5 分钟

  constructor(service: SkillsBackendService) {
    this.service = service;
  }

  // ========== 已安装 Skills ==========

  async loadInstalled(forceRefresh: boolean = false): Promise<void> {
    if (!forceRefresh && Date.now() - this.lastInstalledFetch < this.STALE_TIME_MS) {
      return; // 缓存命中
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
    // 乐观更新
    this.state.installed = [...this.state.installed, installed];
  }

  async uninstall(id: string): Promise<void> {
    const backupPath = await this.service.uninstall(id);
    // 乐观更新
    this.state.installed = this.state.installed.filter(s => s.id !== id);
  }

  async toggleEnabled(id: string, enabled: boolean): Promise<void> {
    const installed = await this.service.getInstalled();
    const skill = installed.find(s => s.id === id);
    if (!skill) return;

    skill.enabled = enabled;
    // 如果有 JSON-RPC skills/configWrite 接口，在这里调用
    // await codexBackend.setSkillEnabled(id, enabled);

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
    await this.service.deleteBackup(backupId);
    this.state.backups = this.state.backups.filter(b => b.backupId !== backupId);
  }

  async restoreBackup(backupId: string): Promise<void> {
    const restored = await this.service.restoreBackup(backupId);
    this.state.installed = [...this.state.installed, restored];
    // 重新加载备份列表（恢复后备份依然保留）
  }

  // ========== 仓库管理 ==========

  async loadRepos(): Promise<void> {
    this.state.repos = await this.service.getRepos();
  }

  async addRepo(repo: SkillRepo): Promise<void> {
    await this.service.addRepo(repo);
    await this.loadRepos();
    // 新仓库可能需要重新发现 Skills
    await this.loadDiscoverable(true);
  }

  async removeRepo(owner: string, name: string): Promise<void> {
    await this.service.removeRepo(owner, name);
    await this.loadRepos();
    await this.loadDiscoverable(true);
  }

  // ========== skills.sh 搜索 ==========

  async searchSkillsSh(query: string, limit: number = 20, offset: number = 0): Promise<SkillsShSearchResult> {
    return this.service.searchSkillsSh(query, limit, offset);
  }

  // ========== ZIP 导入 ==========

  async importFromZip(zipPath: string): Promise<void> {
    // 解压 ZIP → 扫描 SKILL.md → 安装
    // 具体实现：先解压到临时目录，然后对每个包含 SKILL.md 的目录调用 installFromGithub 的本地安装变体
  }
}
```

### 6.3 CodexHostNative 扩展（NAPI 类型声明）

在 `Agent/entry/src/main/types/libcodexhost/index.d.ts` 中新增：

```typescript
// 已有的函数...
// 新增 Skills 管理 NAPI 声明：

export const getSkillsRegistry: () => string;       // 返回 skills-registry.json 内容
export const saveSkillsRegistry: (json: string) => number; // 保存，返回 0=成功
export const getSkillsRepos: () => string;           // 返回 skills-repos.json 内容
export const saveSkillsRepos: (json: string) => number;
export const computeDirHash: (dirPath: string) => string;  // 返回 SHA-256 hex
export const getSkillsBackups: () => string;         // 返回备份列表 JSON
export const createSkillBackup: (skillDir: string, skillJson: string) => string; // 返回备份路径
export const deleteSkillBackup: (backupId: string) => number; // 0=成功
```

### 6.4 NAPI 初始化注册

在 `libcodexhost-builder/native/bridge/napi_init.cpp` 中新增导出：

```cpp
// napi_init.cpp 新增 NAPI 导出

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        // 已有的导出...
        { "getSkillsRegistry",      nullptr, GetSkillsRegistry,      nullptr, nullptr, nullptr, napi_default, nullptr },
        { "saveSkillsRegistry",     nullptr, SaveSkillsRegistry,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getSkillsRepos",         nullptr, GetSkillsRepos,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "saveSkillsRepos",        nullptr, SaveSkillsRepos,        nullptr, nullptr, nullptr, napi_default, nullptr },
        { "computeDirHash",         nullptr, ComputeDirHash,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getSkillsBackups",       nullptr, GetSkillsBackups,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createSkillBackup",      nullptr, CreateSkillBackup,      nullptr, nullptr, nullptr, napi_default, nullptr },
        { "deleteSkillBackup",      nullptr, DeleteSkillBackup,      nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END
```

每个 NAPI 函数实现为简单的 FFI 转发：

```cpp
static napi_value GetSkillsRegistry(napi_env env, napi_callback_info info) {
    // 获取 codex_home 参数
    // 调用 codex_ohos_host_skills_registry_json(codex_home)
    // 将 C 字符串转为 napi_value 返回
}

// ... 其余类似
```

---

## 七、安装流程时序图

```
User          SkillsPage          SkillsViewModel    SkillsBackendService    FileSystem       GitHub
 │                │                     │                    │                   │               │
 │ 点击安装        │                     │                    │                   │               │
 │───────────────>│  installFromGithub  │                    │                   │               │
 │                │────────────────────>│                    │                   │               │
 │                │                     │  installFromGithub │                   │               │
 │                │                     │───────────────────>│                   │               │
 │                │                     │                    │ sanitizeSourcePath│               │
 │                │                     │                    │────┐              │               │
 │                │                     │                    │<───┘              │               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ getInstalled()    │               │
 │                │                     │                    │────┐ (读 JSON)    │               │
 │                │                     │                    │<───┘              │               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ downloadAndExtract│               │
 │                │                     │                    │──────────────────>│               │
 │                │                     │                    │                   │ GET ...zip    │
 │                │                     │                    │                   │──────────────>│
 │                │                     │                    │                   │<─ 200 OK ─────│
 │                │                     │                    │ extract to tmp    │               │
 │                │                     │                    │<── tempDir ───────│               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ resolveSourceDir  │               │
 │                │                     │                    │────┐              │               │
 │                │                     │                    │<───┘              │               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ copyDirRecursive  │               │
 │                │                     │                    │──────────────────>│               │
 │                │                     │                    │<── ok ────────────│               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ removeDir(temp)   │               │
 │                │                     │                    │────┐              │               │
 │                │                     │                    │<───┘              │               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ parseSkillMetadata│               │
 │                │                     │                    │────┐              │               │
 │                │                     │                    │<──┘ (name, desc)  │               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ NAPI computeDirHash │             │
 │                │                     │                    │────┐              │               │
 │                │                     │                    │<──┘ SHA-256      │               │
 │                │                     │                    │                   │               │
 │                │                     │                    │ saveInstalled()   │               │
 │                │                     │                    │────┐ (写 JSON)    │               │
 │                │                     │                    │<───┘              │               │
 │                │                     │                    │                   │               │
 │                │                     │<── InstalledSkill ─│                   │               │
 │                │<── 乐观更新 UI ─────│                    │                   │               │
 │                │                     │                    │                   │               │
 │  UI 刷新        │                     │                    │                   │               │
 │<───────────────│                     │                    │                   │               │
```

---

## 八、与现有系统的集成点

### 8.1 与 SkillsManager 的关系

本管理层**不改动** `codex-rs/core-skills` 的任何代码。安装结果直接对接到现有加载器：

```
安装 Skill 到 $HOME/.agents/skills/some-skill/
    ↓
SkillsManager::skill_roots() 自动发现此目录（User scope root）
    ↓
SkillsManager::skills_for_cwd() 加载并渲染到系统提示
    ↓
用户可以在对话中使用 /skills 命令调用
```

### 8.2 与 JSON-RPC 的关系

现有的 `skills/list` 和 `skills/configWrite` JSON-RPC 方法继续工作：
- `skills/list` — 返回当前 cwd 下可用 Skill 列表（由 SkillsManager 提供）
- `skills/configWrite` — 启用/禁用 Skill（写入 User 配置层）

管理层新增的启用/禁用逻辑需要同步调用 `skills/configWrite`：

```typescript
// 在 SkillsViewModel.toggleEnabled 中
async toggleEnabled(id: string, enabled: boolean): Promise<void> {
  // 1. 更新管理层注册表
  const skill = installed.find(s => s.id === id);
  skill.enabled = enabled;
  await this.saveInstalled(installed);

  // 2. 同步到 app-server（调用已有 JSON-RPC）
  if (enabled) {
    await codexBackend.sendRpcRequest(
      new RpcRequestEnvelope(nextId, 'skills/configWrite', {
        name: skill.name,
        enabled: true
      })
    );
  } else {
    // 禁用同理
  }
}
```

### 8.3 页面接入点

在 `Index.ets` 中，当前 `SidebarView = 'skills'` 时显示的是 `comingSoonPanel`。接入后：

```typescript
// Index.ets 修改
if (this.activeSidebarView === 'skills') {
  // 替换原来的 comingSoonPanel
  SkillsPage({ viewModel: this.skillsViewModel })
}
```

### 8.4 启动时初始化

在 `EntryAbility.onCreate()` 或 `Index.aboutToAppear()` 中初始化：

```typescript
// 初始化 Skills 管理服务
const codexHome = this.context.filesDir + '/codex-home';
const skillsService = new SkillsBackendService(codexHome, codexHost);
const skillsViewModel = new SkillsViewModel(skillsService);

// 保证默认仓库存在
skillsViewModel.loadRepos();

// 预加载已安装列表（首次使用缓存）
skillsViewModel.loadInstalled();
```

---

## 九、关键设计决策

### 9.1 单 Agent 模型简化

cc-switch 需要管理 6 个 AI Agent CLI 的 Skill 启用状态（SkillApps 六维布尔值），ArkPilot 只有一个 Codex Agent，因此：
- 启用/禁用是单一布尔值 `enabled: boolean`
- 无需 AppType 枚举和 SkillApps 多维状态
- 无需 syncToAppDir（同步到不同应用目录）

### 9.2 SSOT 选择：$HOME/.agents/skills/

选择此目录的原因：
1. **已有标准**：codex-rs 的 `SkillsManager::skill_roots()` 已将 `$HOME/.agents/skills/` 作为 User scope 的推荐目录
2. **与 codex-rs 兼容**：安装在此目录的 Skill 会被 SkillsManager 自动发现和加载
3. **用户可管理**：用户也可以手动放置 Skill 到此目录

### 9.3 JSON 注册表 vs SQLite

ArkPilot 的 ohos-host 不使用 SQLite（不链接 rusqlite），现有持久化采用 JSON 文件。Skills 管理层跟随此模式：
- 数据量小（< 100 条记录），JSON 完全够用
- 方便调试和手动修复
- 无需引入新依赖

### 9.4 ArkTS 主责 HTTP/文件操作

考虑到以下因素，将 HTTP 下载和文件操作放在 ArkTS（而非 Rust）：
1. ArkTS 已有 `@kit.NetworkKit`（HTTP）和 `@kit.CoreFileKit`（文件）API
2. 现有代码中 ArkTS 已经在操作文件系统（CodexHostNative 读取/写入 JSON）
3. 鸿蒙 ZIP 解压 API（`@ohos.zlib`）在 ArkTS 侧更方便调试

SHA-256 计算放在 Rust/NAPI 侧（`@ohos.security.cryptoFramework` 对增量哈希的流式支持可能不完善，且 Rust `sha2` crate 更成熟）。

### 9.5 分支回退链

GitHub 仓库下载时，尝试顺序（与 cc-switch 完全一致）：
1. 指定分支
2. main
3. master

全部失败才报错。

### 9.6 ZIP Symlink 处理

GitHub ZIP archive 保留 symlink 元数据。解压时需要检测 symlink 条目，将其解析为目标文件内容的复制（不创建真实 symlink）。这与 cc-switch 的 `write_zip_entry` 实现一致。

---

## 附录 A：技术对照表

| 层级 | cc-switch 原版 | ArkPilot 等效方案 |
|------|---------------|------------------|
| **桌面框架** | Tauri v2 (Rust + WebView) | ArkUI + NAPI (libcodexhost.so) |
| **前端渲染** | React 18 + Vite 7 | ArkUI 声明式 UI |
| **状态管理** | React Query v5 (TanStack) | @State / @Observed + 手写 staleTime |
| **后端语言** | Rust (Tauri commands) | Rust (NAPI FFI) + ArkTS |
| **IPC 通信** | `tauri::invoke` | NAPI 同步调用 / WebSocket JSON-RPC |
| **数据持久化** | SQLite (rusqlite) | JSON 文件 (serde_json) |
| **HTTP 客户端** | reqwest (Rust) | @kit.NetworkKit (ArkTS) |
| **ZIP 处理** | zip crate (Rust) | @ohos.zlib / zip.js |
| **哈希计算** | sha2 crate (Rust) | sha2 crate (Rust/NAPI) |
| **文件操作** | std::fs (Rust) | @kit.CoreFileKit (ArkTS) + std::fs (Rust/NAPI) |
| **错误处理** | format_skill_error (Rust) | SkillError class (ArkTS) |
| **Agent 数量** | 6 (Claude/Codex/Gemini/OpenCode/OpenClaw/Hermes) | 1 (Codex only) |
| **SSOT 目录** | `~/.cc-switch/skills/` | `$HOME/.agents/skills/` |
| **Skill 发现** | 多 Agent 目录 + SSOT 扫描 | SkillsManager 多 Scope 自动扫描 |

## 附录 B：完整功能清单

| 功能 | cc-switch 原版命令 | ArkPilot 实现位置 |
|------|-------------------|------------------|
| 获取已安装 Skill 列表 | `get_installed_skills` | `SkillsBackendService.getInstalled()` |
| 安装 Skill（GitHub） | `install_skill_unified` | `SkillsBackendService.installFromGithub()` |
| 卸载 Skill | `uninstall_skill_unified` | `SkillsBackendService.uninstall()` |
| 切换启用状态 | `toggle_skill_app` | `SkillsViewModel.toggleEnabled()` + JSON-RPC |
| 发现可安装 Skill | `discover_available_skills` | `SkillsBackendService.discoverFromRepos()` |
| 扫描未管理 Skill | `scan_unmanaged_skills` | `SkillsBackendService.scanUnmanaged()` |
| 导入 Skill | `import_skills_from_apps` | `SkillsBackendService.importFromLocal()` |
| 检查更新 | `check_skill_updates` | `SkillsBackendService.checkUpdates()` |
| 更新 Skill | `update_skill` | `SkillsBackendService.update()` |
| 获取备份列表 | `get_skill_backups` | `SkillsBackendService.getBackups()` |
| 删除备份 | `delete_skill_backup` | `SkillsBackendService.deleteBackup()` |
| 恢复备份 | `restore_skill_backup` | `SkillsBackendService.restoreBackup()` |
| 搜索 skills.sh | `search_skills_sh` | `SkillsBackendService.searchSkillsSh()` |
| 获取仓库列表 | `get_skill_repos` | `SkillsBackendService.getRepos()` |
| 添加仓库 | `add_skill_repo` | `SkillsBackendService.addRepo()` |
| 删除仓库 | `remove_skill_repo` | `SkillsBackendService.removeRepo()` |
| ZIP 安装 | `install_skills_from_zip` | `SkillsViewModel.importFromZip()` |
| 存储迁移 | `migrate_skill_storage` | 不需要（单存储位置） |

## 附录 C：待实现清单（优先级排序）

| 优先级 | 模块 | 工作内容 |
|--------|------|---------|
| P0 | Rust NAPI 导出 | `skills_registry.rs`、`skills_hash.rs`、`skills_backup.rs` |
| P0 | Cargo.toml | 添加 `sha2`、`hex`、`chrono` 依赖 |
| P0 | CMakeLists.txt | 重建 Rust staticlib |
| P0 | NAPI 桥接 | `napi_init.cpp` 新增 8 个导出 + `index.d.ts` 类型声明 |
| P1 | SkillsBackendService | 完整实现，包括 ZIP 解压适配 |
| P1 | SkillsViewModel | 完整状态管理 |
| P1 | SkillsPage | ArkUI 页面：已安装/发现/搜索/备份面板 |
| P2 | Index.ets | 接入 Skills 页面，替换 comingSoonPanel |
| P2 | JSON-RPC 同步 | `toggleEnabled` 调用已有 `skills/configWrite` |
| P3 | EntryAbility | 启动时初始化 Skill 服务和默认仓库 |

---

> **文档版本**: 2.0
> **基于**: cc-switch v3.14.1 Skills 管理体系 + ArkPilot codex-rs Skills 引擎
> **适用范围**: ArkPilot (HarmonyOS) Skills 管理子系统
> **可直接作为 AI 编码提示词使用**
