use std::path::Path;

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
