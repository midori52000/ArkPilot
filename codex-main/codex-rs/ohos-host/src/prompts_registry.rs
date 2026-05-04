use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptsRegistry {
    pub version: u32,
    pub prompts: Vec<PromptEntry>,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptEntry {
    pub id: String,
    pub name: String,
    pub content: String,
    pub description: String,
    pub enabled: bool,
    #[serde(rename = "createdAt")]
    pub created_at: i64,
    #[serde(rename = "updatedAt")]
    pub updated_at: i64,
}

pub fn agents_md_path(codex_home: &Path) -> PathBuf {
    codex_home.join("AGENTS.md")
}

impl PromptsRegistry {
    pub fn load_or_default(codex_home: &Path) -> Self {
        let path = codex_home.join("prompts-registry.json");
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
        let path = codex_home.join("prompts-registry.json");
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(&path, json).map_err(|e| e.to_string())
    }

    pub fn find_enabled(&self) -> Option<&PromptEntry> {
        self.prompts.iter().find(|p| p.enabled)
    }

    pub fn find_by_id(&self, id: &str) -> Option<&PromptEntry> {
        self.prompts.iter().find(|p| p.id == id)
    }

    pub fn enable(&mut self, id: &str) -> Result<&PromptEntry, String> {
        let mut found = false;
        for prompt in &mut self.prompts {
            if prompt.id == id {
                prompt.enabled = true;
                found = true;
            } else {
                prompt.enabled = false;
            }
        }
        if !found {
            return Err(format!("prompt not found: {}", id));
        }
        self.updated_at = current_timestamp_string();
        Ok(self.prompts.iter().find(|p| p.id == id).unwrap())
    }

    pub fn disable_all(&mut self) {
        for prompt in &mut self.prompts {
            prompt.enabled = false;
        }
        self.updated_at = current_timestamp_string();
    }

    pub fn upsert(&mut self, prompt: PromptEntry) {
        if let Some(pos) = self.prompts.iter().position(|p| p.id == prompt.id) {
            self.prompts[pos] = prompt;
        } else {
            self.prompts.push(prompt);
        }
        self.updated_at = current_timestamp_string();
    }

    pub fn remove(&mut self, id: &str) -> Option<PromptEntry> {
        if let Some(pos) = self.prompts.iter().position(|p| p.id == id) {
            let removed = self.prompts.remove(pos);
            self.updated_at = current_timestamp_string();
            Some(removed)
        } else {
            None
        }
    }
}

/// 启用指定 Prompt 并同步 AGENTS.md（原子操作）
///
/// 流程：
/// 1. 读取当前 AGENTS.md 内容
/// 2. 将内容回写到当前已启用的 prompt（如有变更）
/// 3. 如果没有已启用 prompt 但 AGENTS.md 有内容，创建自动备份
/// 4. 启用目标 prompt（互斥）
/// 5. 将目标 prompt 的 content 写入 AGENTS.md
/// 6. 保存 registry
pub fn enable_prompt_with_agents_md(
    codex_home: &Path,
    id: &str,
) -> Result<PromptEntry, String> {
    let mut registry = PromptsRegistry::load_or_default(codex_home);

    // 已经是启用状态则直接返回
    if let Some(target) = registry.find_by_id(id) {
        if target.enabled {
            return Ok(target.clone());
        }
    }

    let live_content = std::fs::read_to_string(agents_md_path(codex_home)).unwrap_or_default();

    // 保存当前 AGENTS.md 内容到旧 prompt
    if let Some(old_enabled) = registry.find_enabled() {
        let old_id = old_enabled.id.clone();
        if !live_content.is_empty() && live_content != old_enabled.content {
            if let Some(pos) = registry.prompts.iter().position(|p| p.id == old_id) {
                registry.prompts[pos].content = live_content.clone();
                registry.prompts[pos].updated_at = now_millis();
            }
        }
    } else if !live_content.is_empty() {
        // 无已启用 prompt，但 AGENTS.md 有内容 → 创建自动备份
        let backup_id = format!("auto-backup-{}", now_millis());
        registry.prompts.push(PromptEntry {
            id: backup_id,
            name: "Auto Backup".into(),
            content: live_content.clone(),
            description: "AGENTS.md 自动备份".into(),
            enabled: false,
            created_at: now_millis(),
            updated_at: 0,
        });
    }

    // 启用目标
    let enabled_entry = registry.enable(id)?.clone();

    // 写入 AGENTS.md
    let agents_path = agents_md_path(codex_home);
    let tmp_path = agents_path.with_extension("md.tmp");
    std::fs::write(&tmp_path, &enabled_entry.content)
        .map_err(|e| format!("write AGENTS.md tmp: {}", e))?;
    std::fs::rename(&tmp_path, &agents_path)
        .map_err(|e| format!("rename AGENTS.md: {}", e))?;

    registry.save(codex_home)?;
    Ok(enabled_entry)
}

/// 禁用所有 Prompt 并清空 AGENTS.md（原子操作）
///
/// 流程：
/// 1. 读取当前 AGENTS.md 内容
/// 2. 将内容回写到当前已启用的 prompt（如有变更）
/// 3. 禁用全部 prompt
/// 4. 清空 AGENTS.md
/// 5. 保存 registry
pub fn disable_all_with_agents_md(codex_home: &Path) -> Result<(), String> {
    let mut registry = PromptsRegistry::load_or_default(codex_home);

    let live_content = std::fs::read_to_string(agents_md_path(codex_home)).unwrap_or_default();

    // 保存当前 AGENTS.md 内容到旧 prompt
    if let Some(old_enabled) = registry.find_enabled() {
        let old_id = old_enabled.id.clone();
        if !live_content.is_empty() && live_content != old_enabled.content {
            if let Some(pos) = registry.prompts.iter().position(|p| p.id == old_id) {
                registry.prompts[pos].content = live_content;
                registry.prompts[pos].updated_at = now_millis();
            }
        }
    }

    registry.disable_all();

    // 清空 AGENTS.md
    let agents_path = agents_md_path(codex_home);
    let tmp_path = agents_path.with_extension("md.tmp");
    std::fs::write(&tmp_path, "").map_err(|e| format!("write AGENTS.md tmp: {}", e))?;
    std::fs::rename(&tmp_path, &agents_path).map_err(|e| format!("rename AGENTS.md: {}", e))?;

    registry.save(codex_home)?;
    Ok(())
}

fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

impl Default for PromptsRegistry {
    fn default() -> Self {
        Self {
            version: 1,
            prompts: Vec::new(),
            updated_at: current_timestamp_string(),
        }
    }
}

fn current_timestamp_string() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|_| "0".into())
}
