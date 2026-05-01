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
