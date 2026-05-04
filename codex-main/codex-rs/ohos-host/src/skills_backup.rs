use std::path::Path;
use std::path::PathBuf;

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
    let dir_name = skill_dir
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");
    let backup_id = format!("{}_{}", timestamp, dir_name);
    let backup_path = backup_root.join(&backup_id);

    // 复制 Skill 文件
    let skill_dest = backup_path.join("skill");
    copy_dir_recursive(skill_dir, &skill_dest)?;

    // 写入元数据
    let skill_value: serde_json::Value =
        serde_json::from_str(skill_json).unwrap_or_default();
    let meta = serde_json::json!({
        "skill": skill_value,
        "backupCreatedAt": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0),
        "sourcePath": skill_dir.to_string_lossy(),
    });
    let meta_json =
        serde_json::to_string_pretty(&meta).map_err(|e| format!("serialize meta: {}", e))?;
    std::fs::write(backup_path.join("meta.json"), meta_json)
        .map_err(|e| format!("write meta: {}", e))?;

    // 清理旧备份
    cleanup_old_backups(&backup_root, 20);

    Ok(backup_path)
}

/// 枚举备份目录，返回备份条目列表
pub fn list_backups(codex_home: &Path) -> Vec<serde_json::Value> {
    let backup_root = codex_home.join("skill-backups");
    let mut backups = Vec::new();

    let entries = match std::fs::read_dir(&backup_root) {
        Ok(entries) => entries,
        Err(_) => return backups,
    };

    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let backup_id = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();

        let meta_path = path.join("meta.json");
        let meta: serde_json::Value = std::fs::read_to_string(&meta_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();

        let created_at = meta
            .get("backupCreatedAt")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);

        backups.push(serde_json::json!({
            "backupId": backup_id,
            "backupPath": path.to_string_lossy(),
            "createdAt": created_at,
            "skill": meta.get("skill").cloned().unwrap_or(serde_json::Value::Null),
        }));
    }

    // 按创建时间降序
    backups.sort_by(|a, b| {
        let ta = a.get("createdAt").and_then(|v| v.as_i64()).unwrap_or(0);
        let tb = b.get("createdAt").and_then(|v| v.as_i64()).unwrap_or(0);
        tb.cmp(&ta)
    });

    backups
}

pub fn copy_dir_recursive(src: &Path, dest: &Path) -> Result<(), String> {
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
            std::fs::copy(&src_path, &dest_path).map_err(|e| {
                format!(
                    "copy {} -> {}: {}",
                    src_path.display(),
                    dest_path.display(),
                    e
                )
            })?;
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

    for entry in backups.iter().take(backups.len().saturating_sub(max_keep)) {
        let _ = std::fs::remove_dir_all(entry.path());
    }
}
