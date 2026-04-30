use sha2::Digest;
use sha2::Sha256;
use std::path::Path;

/// 计算目录内容 SHA-256 哈希
///
/// 策略：
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
            let relative = path
                .strip_prefix(base)
                .map_err(|e| format!("strip_prefix: {}", e))?;
            result.push(relative.to_string_lossy().into_owned());
        }
    }
    Ok(())
}
