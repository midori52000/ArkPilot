use std::path::Path;
use std::path::PathBuf;

use serde::Deserialize;
use serde::Serialize;

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
    pub source: String,
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
        std::fs::create_dir_all(codex_home).map_err(|e| e.to_string())?;
        let path = codex_home.join("skills-registry.json");
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(&path, json).map_err(|e| e.to_string())
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
        if let Some(pos) = self.skills.iter().position(|s| s.id == id) {
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
        std::fs::create_dir_all(codex_home).map_err(|e| e.to_string())?;
        let path = codex_home.join("skills-repos.json");
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(&path, json).map_err(|e| e.to_string())
    }

    fn with_defaults() -> Self {
        Self {
            version: 1,
            repos: vec![
                SkillRepoEntry {
                    owner: "anthropics".into(),
                    name: "skills".into(),
                    branch: "main".into(),
                    enabled: true,
                },
                SkillRepoEntry {
                    owner: "ComposioHQ".into(),
                    name: "awesome-claude-skills".into(),
                    branch: "master".into(),
                    enabled: true,
                },
                SkillRepoEntry {
                    owner: "cexll".into(),
                    name: "myclaude".into(),
                    branch: "master".into(),
                    enabled: true,
                },
                SkillRepoEntry {
                    owner: "JimLiu".into(),
                    name: "baoyu-skills".into(),
                    branch: "main".into(),
                    enabled: true,
                },
            ],
        }
    }
}

pub fn current_timestamp_string() -> String {
    format!(
        "{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_secs())
            .unwrap_or(0)
    )
}

/// 获取 SSOT 目录路径
///
/// SSOT 位于 `{codex_home}/../.agents/skills`
pub fn ssot_dir(codex_home: &Path) -> PathBuf {
    codex_home
        .parent()
        .unwrap_or(codex_home)
        .join(".agents")
        .join("skills")
}

/// 从 SKILL.md frontmatter 解析 name 和 description
fn parse_skill_metadata(skill_md_path: &Path) -> (String, String) {
    let content = match std::fs::read_to_string(skill_md_path) {
        Ok(c) => c,
        Err(_) => return (String::new(), String::new()),
    };

    // 去除 BOM
    let content = content.trim_start_matches('\u{feff}');

    let parts: Vec<&str> = content.splitn(3, "---").collect();
    if parts.len() < 3 {
        return (String::new(), String::new());
    }

    let frontmatter = parts[1].trim();
    let mut name = String::new();
    let mut description = String::new();

    for line in frontmatter.lines() {
        if let Some(colon_pos) = line.find(':') {
            let key = line[..colon_pos].trim();
            let value = line[colon_pos + 1..]
                .trim()
                .trim_matches(|c| c == '\'' || c == '"')
                .to_string();
            match key {
                "name" => name = value,
                "description" => description = value,
                _ => {}
            }
        }
    }

    (name, description)
}

/// 一致性检查结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReconcileResult {
    pub removed: Vec<String>,
    pub registered: Vec<String>,
}

/// 从源目录安装 Skill 到 SSOT
///
/// 操作流程：
/// 1. 解析 skill_json 获取目录名
/// 2. 复制 source_dir 到 SSOT
/// 3. 解析 SKILL.md 获取元数据
/// 4. 计算内容哈希
/// 5. 创建 registry 条目并 upsert
pub fn install_skill_from_dir(
    codex_home: &Path,
    source_dir: &Path,
    skill_json: &str,
) -> Result<InstalledSkillEntry, String> {
    let skill_value: serde_json::Value =
        serde_json::from_str(skill_json).map_err(|e| format!("parse skill_json: {}", e))?;

    let directory = skill_value
        .get("directory")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if directory.is_empty() {
        return Err("skill_json missing 'directory' field".into());
    }

    let ssot = ssot_dir(codex_home);
    std::fs::create_dir_all(&ssot).map_err(|e| format!("create ssot dir: {}", e))?;

    let dest = ssot.join(&directory);

    // 冲突检测：如果已存在同名目录且来自不同源，报错
    if dest.exists() {
        let registry = SkillsRegistry::load_or_default(codex_home);
        if let Some(existing) = registry.skills.iter().find(|s| s.directory == directory) {
            let new_id = skill_value
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if existing.id != new_id {
                return Err(format!(
                    "directory conflict: '{}' already owned by '{}'",
                    directory, existing.id
                ));
            }
        }
    }

    // 复制文件
    super::skills_backup::copy_dir_recursive(source_dir, &dest)
        .map_err(|e| format!("copy to ssot: {}", e))?;

    // 解析 SKILL.md
    let skill_md_path = dest.join("SKILL.md");
    let (parsed_name, parsed_description) = parse_skill_metadata(&skill_md_path);

    // 计算哈希
    let content_hash = super::skills_hash::compute_dir_hash(&dest).unwrap_or_default();

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);

    let entry = InstalledSkillEntry {
        id: skill_value
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or(&format!("local:{}", directory))
            .to_string(),
        name: if parsed_name.is_empty() {
            directory.clone()
        } else {
            parsed_name
        },
        description: parsed_description,
        directory: directory.clone(),
        source: skill_value
            .get("source")
            .and_then(|v| v.as_str())
            .unwrap_or("local")
            .to_string(),
        repo_owner: skill_value
            .get("repoOwner")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        repo_name: skill_value
            .get("repoName")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        repo_branch: skill_value
            .get("repoBranch")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        readme_url: skill_value
            .get("readmeUrl")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        enabled: skill_value
            .get("enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(true),
        installed_at: skill_value
            .get("installedAt")
            .and_then(|v| v.as_i64())
            .unwrap_or(now_ms),
        content_hash,
        updated_at: 0,
    };

    let mut registry = SkillsRegistry::load_or_default(codex_home);
    registry.upsert(entry.clone());
    registry.save(codex_home)?;

    Ok(entry)
}

/// 卸载 Skill
///
/// 操作流程：
/// 1. 从 registry 查找
/// 2. 创建备份
/// 3. 删除 SSOT 目录
/// 4. 从 registry 移除
pub fn uninstall_skill(
    codex_home: &Path,
    id: &str,
) -> Result<String, String> {
    let mut registry = SkillsRegistry::load_or_default(codex_home);
    let skill = registry
        .skills
        .iter()
        .find(|s| s.id == id)
        .cloned()
        .ok_or_else(|| format!("skill not found: {}", id))?;

    // 创建备份
    let ssot = ssot_dir(codex_home);
    let skill_dir = ssot.join(&skill.directory);
    let skill_json = serde_json::to_string(&skill).unwrap_or_default();
    let backup_path = if skill_dir.exists() {
        super::skills_backup::create_uninstall_backup(codex_home, &skill_dir, &skill_json)
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    } else {
        String::new()
    };

    // 删除 SSOT 目录
    if skill_dir.exists() {
        std::fs::remove_dir_all(&skill_dir)
            .map_err(|e| format!("remove skill dir: {}", e))?;
    }

    // 从 registry 移除
    registry.remove(id);
    registry.save(codex_home)?;

    Ok(backup_path)
}

/// 切换 Skill 启用/禁用状态
pub fn set_skill_enabled(
    codex_home: &Path,
    id: &str,
    enabled: bool,
) -> Result<InstalledSkillEntry, String> {
    let mut registry = SkillsRegistry::load_or_default(codex_home);
    let skill = registry
        .skills
        .iter_mut()
        .find(|s| s.id == id)
        .ok_or_else(|| format!("skill not found: {}", id))?;

    skill.enabled = enabled;
    let result = skill.clone();
    registry.save(codex_home)?;

    Ok(result)
}

/// 一致性检查：修复 registry 与 SSOT 目录的不一致
///
/// 1. registry 有条目但 SSOT 目录缺失 → 从 registry 移除
/// 2. SSOT 有目录但 registry 无条目 → 注册为 local skill
pub fn reconcile_skills(codex_home: &Path) -> ReconcileResult {
    let mut removed = Vec::new();
    let mut registered = Vec::new();

    let ssot = ssot_dir(codex_home);
    if !ssot.exists() {
        return ReconcileResult { removed, registered };
    }

    let mut registry = SkillsRegistry::load_or_default(codex_home);

    // 检查 1: registry 有但 SSOT 无
    let mut valid_entries = Vec::new();
    for skill in &registry.skills {
        let skill_dir = ssot.join(&skill.directory);
        if skill_dir.exists() && skill_dir.is_dir() {
            valid_entries.push(skill.clone());
        } else {
            removed.push(skill.id.clone());
        }
    }

    if removed.len() != registry.skills.len() || !removed.is_empty() {
        registry.skills = valid_entries.clone();
        let _ = registry.save(codex_home);
    }

    // 检查 2: SSOT 有但 registry 无
    let registered_dirs: std::collections::HashSet<String> = valid_entries
        .iter()
        .map(|s| s.directory.clone())
        .collect();

    let entries = match std::fs::read_dir(&ssot) {
        Ok(e) => e,
        Err(_) => return ReconcileResult { removed, registered },
    };

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);

    let mut new_skills = Vec::new();
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let dir_name = entry
            .file_name()
            .to_string_lossy()
            .to_string();

        if registered_dirs.contains(&dir_name) {
            continue;
        }

        let skill_md = path.join("SKILL.md");
        if !skill_md.exists() {
            continue;
        }

        let (name, description) = parse_skill_metadata(&skill_md);
        let content_hash = super::skills_hash::compute_dir_hash(&path).unwrap_or_default();

        let new_entry = InstalledSkillEntry {
            id: format!("local:{}", dir_name),
            name: if name.is_empty() { dir_name.clone() } else { name },
            description,
            directory: dir_name,
            source: "local".into(),
            repo_owner: String::new(),
            repo_name: String::new(),
            repo_branch: String::new(),
            readme_url: String::new(),
            enabled: true,
            installed_at: now_ms,
            content_hash,
            updated_at: 0,
        };

        registered.push(new_entry.id.clone());
        new_skills.push(new_entry);
    }

    if !new_skills.is_empty() {
        registry.skills.extend(new_skills);
        let _ = registry.save(codex_home);
    }

    ReconcileResult { removed, registered }
}
