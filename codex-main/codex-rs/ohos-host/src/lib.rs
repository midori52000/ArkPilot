use std::ffi::CStr;
use std::ffi::CString;
use std::net::SocketAddr;
use std::net::TcpStream;
use std::os::raw::c_char;
use std::path::Path;
use std::path::PathBuf;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use std::time::Instant;

use anyhow::Context;
use anyhow::Result;
use codex_app_server::AppServerTransport;
use codex_app_server::AppServerWebsocketAuthSettings;
use codex_app_server::run_main_with_transport;
use codex_arg0::Arg0DispatchPaths;
use codex_core::config_loader::LoaderOverrides;
use codex_protocol::protocol::SessionSource;
use codex_utils_cli::CliConfigOverrides;
use once_cell::sync::Lazy;
use serde::Deserialize;
use serde::Serialize;

mod prompts_registry;
mod skills_backup;
mod skills_hash;
mod skills_registry;

const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:7456";
const DEFAULT_PROVIDER_BASE_URL: &str = "https://api.openai.com/v1";
const DEFAULT_APPROVAL_POLICY: &str = "on-request";
const DEFAULT_SANDBOX_MODE: &str = "workspace-write";
const CUSTOM_PROVIDER_ID: &str = "harmony-openai-compatible";
const READY_TIMEOUT: Duration = Duration::from_secs(20);
const READY_POLL_INTERVAL: Duration = Duration::from_millis(100);
const DEFAULT_PROVIDER_MODE: &str = "exclusive";
const DEFAULT_PROVIDER_SYNC_STATUS: &str = "synced";

#[derive(Default)]
struct HostState {
    running: bool,
    server_url: String,
    message: String,
    codex_home: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceAccessStatus {
    root_path: String,
    access_kind: String,
    permission_state: String,
    writable: bool,
    exists: bool,
    message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderSettings {
    base_url: String,
    api_key: String,
    model: String,
}

impl Default for ProviderSettings {
    fn default() -> Self {
        Self {
            base_url: DEFAULT_PROVIDER_BASE_URL.to_string(),
            api_key: String::new(),
            model: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderCatalogRecord {
    id: String,
    name: String,
    app_type: String,
    mode: String,
    base_url: String,
    api_key: String,
    model: String,
    is_active: bool,
    sync_status: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProviderCatalog {
    version: u32,
    active_provider_id: String,
    providers: Vec<ProviderCatalogRecord>,
    updated_at: String,
}

impl Default for ProviderCatalog {
    fn default() -> Self {
        Self {
            version: 1,
            active_provider_id: String::new(),
            providers: Vec::new(),
            updated_at: current_timestamp_string(),
        }
    }
}

static HOST_STATE: Lazy<Mutex<HostState>> = Lazy::new(|| Mutex::new(HostState::default()));
static LAST_MESSAGE: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("").expect("empty cstring")));
static LAST_SERVER_URL: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new(DEFAULT_LISTEN_URL).expect("default cstring")));
static LAST_PROVIDER_CONFIG_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    let json = serde_json::to_string(&ProviderSettings::default()).expect("default provider json");
    Mutex::new(CString::new(json).expect("provider config cstring"))
});
static LAST_PROVIDER_CATALOG_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    let json = serde_json::to_string(&ProviderCatalog::default()).expect("default provider catalog json");
    Mutex::new(CString::new(json).expect("provider catalog cstring"))
});
static LAST_SKILLS_REGISTRY_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_SKILLS_REPOS_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_HASH_RESULT: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("").expect("empty cstring"))
});
static LAST_BACKUPS_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("[]").expect("empty cstring"))
});
static LAST_BACKUP_PATH: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("").expect("empty cstring"))
});
static LAST_PROMPTS_REGISTRY_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_AGENTS_MD_CONTENT: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("").expect("empty cstring"))
});
static LAST_INIT_RESULT_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_THREAD_RESULT_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_TURN_RESULT_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_TURN_EVENTS_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("[]").expect("empty cstring"))
});
static LAST_TURN_POLL_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});
static LAST_APPROVAL_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("null").expect("empty cstring"))
});
static LAST_MCP_STATUS_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"data\":[],\"nextCursor\":null}").expect("empty cstring"))
});
static LAST_MCP_CONFIG_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"config\":{}}") .expect("empty cstring"))
});
static LAST_MCP_OAUTH_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"authorizationUrl\":\"\"}").expect("empty cstring"))
});
static LAST_ACCOUNT_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"account\":null,\"requiresOpenaiAuth\":false}").expect("empty cstring"))
});
static LAST_WORKSPACE_ACCESS_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{}").expect("empty cstring"))
});

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_start(
    codex_home: *const c_char,
    listen_url: *const c_char,
) -> i32 {
    let codex_home = ffi_string(codex_home).map(PathBuf::from);
    let listen_url = ffi_string(listen_url)
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_LISTEN_URL.to_string());

    match start_host(codex_home, listen_url) {
        Ok(()) => 0,
        Err(err) => {
            update_host_state(false, None, None, format!("embedded app-server start failed: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_is_running() -> i32 {
    if HOST_STATE.lock().expect("host state lock").running {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_last_message() -> *const c_char {
    let state = HOST_STATE.lock().expect("host state lock");
    write_cstring(&LAST_MESSAGE, &state.message)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_server_url() -> *const c_char {
    let state = HOST_STATE.lock().expect("host state lock");
    let value = if state.server_url.is_empty() {
        DEFAULT_LISTEN_URL
    } else {
        state.server_url.as_str()
    };
    write_cstring(&LAST_SERVER_URL, value)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_provider_config_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let settings = load_provider_settings(&codex_home).unwrap_or_default();
    let json = serde_json::to_string(&settings).unwrap_or_else(|_| "{}".to_string());
    write_cstring(&LAST_PROVIDER_CONFIG_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_provider_config(
    codex_home: *const c_char,
    base_url: *const c_char,
    api_key: *const c_char,
    model: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let settings = ProviderSettings {
        base_url: ffi_string(base_url)
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_PROVIDER_BASE_URL.to_string()),
        api_key: ffi_string(api_key).unwrap_or_default(),
        model: ffi_string(model).unwrap_or_default(),
    };

    match persist_provider_settings(&codex_home, &settings) {
        Ok(()) => {
            set_host_message(
                "provider config saved; restart the app to apply base URL or default model changes"
                    .to_string(),
            );
            0
        }
        Err(err) => {
            set_host_message(format!("failed to save provider config: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_provider_catalog_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let catalog = load_provider_catalog(&codex_home).unwrap_or_default();
    let json = serde_json::to_string(&catalog).unwrap_or_else(|_| "{}".to_string());
    write_cstring(&LAST_PROVIDER_CATALOG_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_provider_catalog(
    codex_home: *const c_char,
    catalog_json: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(raw_catalog) = ffi_string(catalog_json) else {
        set_host_message("failed to save provider catalog: empty catalog json".to_string());
        return 1;
    };

    let parsed = serde_json::from_str::<ProviderCatalog>(&raw_catalog);
    let catalog = match parsed {
        Ok(catalog) => normalize_catalog(catalog),
        Err(err) => {
            set_host_message(format!("failed to parse provider catalog: {err}"));
            return 1;
        }
    };

    match persist_provider_catalog(&codex_home, &catalog) {
        Ok(()) => {
            set_host_message("provider catalog saved".to_string());
            0
        }
        Err(err) => {
            set_host_message(format!("failed to save provider catalog: {err}"));
            1
        }
    }
}

// ========== Skills Registry ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_skills_registry_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let registry = skills_registry::SkillsRegistry::load_or_default(&codex_home);
    let json = serde_json::to_string(&registry).unwrap_or_else(|_| "{}".into());
    write_cstring(&LAST_SKILLS_REGISTRY_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_skills_registry(
    codex_home: *const c_char,
    registry_json: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(json_str) = ffi_string(registry_json) else {
        return 1;
    };
    let registry: skills_registry::SkillsRegistry = match serde_json::from_str(&json_str) {
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
    let repos = skills_registry::SkillsRepoList::load_or_default(&codex_home);
    let json = serde_json::to_string(&repos).unwrap_or_else(|_| "{}".into());
    write_cstring(&LAST_SKILLS_REPOS_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_skills_repos(
    codex_home: *const c_char,
    repos_json: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(json_str) = ffi_string(repos_json) else {
        return 1;
    };
    let repos: skills_registry::SkillsRepoList = match serde_json::from_str(&json_str) {
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
    let hash = skills_hash::compute_dir_hash(Path::new(&path_str)).unwrap_or_default();
    write_cstring(&LAST_HASH_RESULT, &hash)
}

// ========== Skills Backups ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_skills_backups_json(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let backups = skills_backup::list_backups(&codex_home);
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
    let Some(backup_id) = ffi_string(backup_id) else {
        return 1;
    };

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

// ========== Prompts Registry ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_prompts_registry_json(
    codex_home: *const c_char,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let registry = prompts_registry::PromptsRegistry::load_or_default(&codex_home);
    let json = serde_json::to_string(&registry).unwrap_or_else(|_| "{}".into());
    write_cstring(&LAST_PROMPTS_REGISTRY_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_save_prompts_registry(
    codex_home: *const c_char,
    registry_json: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(json_str) = ffi_string(registry_json) else { return 1; };
    let registry: prompts_registry::PromptsRegistry = match serde_json::from_str(&json_str) {
        Ok(r) => r,
        Err(_) => return 1,
    };
    match registry.save(&codex_home) {
        Ok(()) => 0,
        Err(_) => 1,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_read_agents_md(
    codex_home: *const c_char,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let path = prompts_registry::agents_md_path(&codex_home);
    let content = std::fs::read_to_string(&path).unwrap_or_default();
    write_cstring(&LAST_AGENTS_MD_CONTENT, &content)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_write_agents_md(
    codex_home: *const c_char,
    content: *const c_char,
) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(content) = ffi_string(content) else { return 1; };
    let path = prompts_registry::agents_md_path(&codex_home);

    let tmp_path = path.with_extension("md.tmp");
    match std::fs::write(&tmp_path, &content) {
        Ok(()) => match std::fs::rename(&tmp_path, &path) {
            Ok(()) => 0,
            Err(_) => 1,
        },
        Err(_) => 1,
    }
}

fn start_host(codex_home: Option<PathBuf>, listen_url: String) -> Result<()> {
    {
        let state = HOST_STATE.lock().expect("host state lock");
        if state.running {
            drop(state);
            update_host_state(
                true,
                Some(listen_url),
                None,
                "embedded app-server already running".to_string(),
            );
            return Ok(());
        }
    }

    let codex_home = codex_home.unwrap_or_else(default_codex_home);
    std::fs::create_dir_all(&codex_home)?;
    ensure_provider_config(&codex_home)?;
    configure_environment(&codex_home);

    let transport = AppServerTransport::from_listen_url(&listen_url)
        .map_err(|err| anyhow::anyhow!("invalid listen url `{listen_url}`: {err}"))?;
    let bind_address = match transport {
        AppServerTransport::WebSocket { bind_address } => bind_address,
        AppServerTransport::Stdio => {
            return Err(anyhow::anyhow!(
                "embedded app-server only supports websocket listen urls"
            ));
        }
    };

    update_host_state(
        true,
        Some(listen_url.clone()),
        Some(codex_home.clone()),
        format!("starting embedded app-server on {listen_url}"),
    );

    let transport_for_thread = transport;
    thread::Builder::new()
        .name("codex-ohos-host".to_string())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(err) => {
                    update_host_state(
                        false,
                        None,
                        None,
                        format!("failed to build Tokio runtime: {err}"),
                    );
                    return;
                }
            };

            let result = runtime.block_on(async move {
                run_main_with_transport(
                    Arg0DispatchPaths::default(),
                    CliConfigOverrides::default(),
                    LoaderOverrides::default(),
                    /*default_analytics_enabled*/ false,
                    transport_for_thread,
                    SessionSource::VSCode,
                    AppServerWebsocketAuthSettings::default(),
                )
                .await
            });

            match result {
                Ok(()) => update_host_state(
                    false,
                    None,
                    None,
                    "embedded app-server stopped".to_string(),
                ),
                Err(err) => update_host_state(
                    false,
                    None,
                    None,
                    format!("embedded app-server stopped with error: {err}"),
                ),
            }
        })?;

    match wait_until_ready(bind_address) {
        Ok(()) => {
            update_host_state(
                true,
                Some(listen_url.clone()),
                None,
                format!("embedded app-server ready on {listen_url}"),
            );
            Ok(())
        }
        Err(err) => {
            let still_running = HOST_STATE.lock().expect("host state lock").running;
            if still_running {
                update_host_state(
                    true,
                    Some(listen_url.clone()),
                    None,
                    format!("embedded app-server is still starting on {listen_url}: {err}"),
                );
                Ok(())
            } else {
                Err(err)
            }
        }
    }
}

fn provider_settings_path(codex_home: &Path) -> PathBuf {
    codex_home.join("harmony-provider.json")
}

fn provider_catalog_path(codex_home: &Path) -> PathBuf {
    codex_home.join("harmony-provider-catalog.json")
}

fn codex_config_path(codex_home: &Path) -> PathBuf {
    codex_home.join("config.toml")
}

fn load_provider_settings(codex_home: &Path) -> Result<ProviderSettings> {
    let path = provider_settings_path(codex_home);
    if !path.exists() {
        return Ok(ProviderSettings::default());
    }

    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let settings: ProviderSettings = serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(settings)
}

fn ensure_provider_config(codex_home: &Path) -> Result<()> {
    let settings = load_provider_settings(codex_home).unwrap_or_default();
    persist_provider_settings(codex_home, &settings)?;
    let catalog = load_provider_catalog(codex_home).unwrap_or_else(|_| {
        ProviderCatalog {
            version: 1,
            active_provider_id: "live-provider".to_string(),
            providers: vec![catalog_record_from_settings("live-provider", "当前 Live Provider", &settings, true)],
            updated_at: current_timestamp_string(),
        }
    });
    persist_provider_catalog(codex_home, &catalog)
}

fn persist_provider_settings(codex_home: &Path, settings: &ProviderSettings) -> Result<()> {
    std::fs::create_dir_all(codex_home)?;

    let provider_path = provider_settings_path(codex_home);
    let provider_json = serde_json::to_string_pretty(settings)?;
    std::fs::write(&provider_path, provider_json)
        .with_context(|| format!("failed to write {}", provider_path.display()))?;

    let config_path = codex_config_path(codex_home);
    let config_toml = render_config_toml(settings);
    std::fs::write(&config_path, config_toml)
        .with_context(|| format!("failed to write {}", config_path.display()))?;

    Ok(())
}

fn load_provider_catalog(codex_home: &Path) -> Result<ProviderCatalog> {
    let path = provider_catalog_path(codex_home);
    if !path.exists() {
        let settings = load_provider_settings(codex_home).unwrap_or_default();
        return Ok(ProviderCatalog {
            version: 1,
            active_provider_id: "live-provider".to_string(),
            providers: vec![catalog_record_from_settings("live-provider", "当前 Live Provider", &settings, true)],
            updated_at: current_timestamp_string(),
        });
    }

    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let catalog: ProviderCatalog = serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(normalize_catalog(catalog))
}

fn persist_provider_catalog(codex_home: &Path, catalog: &ProviderCatalog) -> Result<()> {
    std::fs::create_dir_all(codex_home)?;
    let normalized = normalize_catalog(catalog.clone());
    let catalog_path = provider_catalog_path(codex_home);
    let catalog_json = serde_json::to_string_pretty(&normalized)?;
    std::fs::write(&catalog_path, catalog_json)
        .with_context(|| format!("failed to write {}", catalog_path.display()))?;

    if let Some(active) = normalized
        .providers
        .iter()
        .find(|provider| provider.id == normalized.active_provider_id || provider.is_active)
    {
        let settings = ProviderSettings {
            base_url: active.base_url.clone(),
            api_key: active.api_key.clone(),
            model: active.model.clone(),
        };
        persist_provider_settings(codex_home, &settings)?;
    }
    Ok(())
}

fn render_config_toml(settings: &ProviderSettings) -> String {
    let mut lines = vec![
        format!("approval_policy = {}", toml_string(DEFAULT_APPROVAL_POLICY)),
        format!("sandbox_mode = {}", toml_string(DEFAULT_SANDBOX_MODE)),
        String::new(),
        format!("model_provider = {}", toml_string(CUSTOM_PROVIDER_ID)),
        String::new(),
        format!("[model_providers.{CUSTOM_PROVIDER_ID}]"),
        format!("name = {}", toml_string("Harmony OpenAI Compatible")),
        format!("base_url = {}", toml_string(&settings.base_url)),
        r#"wire_api = "responses""#.to_string(),
        "requires_openai_auth = false".to_string(),
        "supports_websockets = false".to_string(),
    ];

    if !settings.api_key.trim().is_empty() {
        lines.push(format!(
            "experimental_bearer_token = {}",
            toml_string(&settings.api_key)
        ));
    }

    if !settings.model.trim().is_empty() {
        lines.insert(1, format!("model = {}", toml_string(&settings.model)));
    }

    lines.join("\n") + "\n"
}

fn catalog_record_from_settings(
    id: &str,
    name: &str,
    settings: &ProviderSettings,
    is_active: bool,
) -> ProviderCatalogRecord {
    ProviderCatalogRecord {
        id: id.to_string(),
        name: name.to_string(),
        app_type: "codex".to_string(),
        mode: DEFAULT_PROVIDER_MODE.to_string(),
        base_url: settings.base_url.clone(),
        api_key: settings.api_key.clone(),
        model: settings.model.clone(),
        is_active,
        sync_status: DEFAULT_PROVIDER_SYNC_STATUS.to_string(),
        updated_at: current_timestamp_string(),
    }
}

fn normalize_catalog(mut catalog: ProviderCatalog) -> ProviderCatalog {
    if catalog.version == 0 {
        catalog.version = 1;
    }
    if catalog.updated_at.trim().is_empty() {
        catalog.updated_at = current_timestamp_string();
    }
    if catalog.providers.is_empty() {
        catalog.active_provider_id.clear();
        return catalog;
    }

    if catalog.active_provider_id.trim().is_empty() {
        catalog.active_provider_id = catalog.providers[0].id.clone();
    }

    let active_id = catalog.active_provider_id.clone();
    for (index, provider) in catalog.providers.iter_mut().enumerate() {
        if provider.app_type.trim().is_empty() {
            provider.app_type = "codex".to_string();
        }
        if provider.mode.trim().is_empty() {
            provider.mode = DEFAULT_PROVIDER_MODE.to_string();
        }
        if provider.base_url.trim().is_empty() {
            provider.base_url = DEFAULT_PROVIDER_BASE_URL.to_string();
        }
        if provider.sync_status.trim().is_empty() {
            provider.sync_status = DEFAULT_PROVIDER_SYNC_STATUS.to_string();
        }
        if provider.updated_at.trim().is_empty() {
            provider.updated_at = catalog.updated_at.clone();
        }
        provider.is_active = provider.id == active_id || (index == 0 && active_id.is_empty());
    }

    if !catalog.providers.iter().any(|provider| provider.id == active_id) {
        catalog.active_provider_id = catalog.providers[0].id.clone();
        if let Some(first) = catalog.providers.first_mut() {
            first.is_active = true;
        }
    }
    catalog
}

fn current_timestamp_string() -> String {
    format!("{}", std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0))
}

fn toml_string(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");
    format!("\"{escaped}\"")
}

fn wait_until_ready(bind_address: SocketAddr) -> Result<()> {
    let deadline = Instant::now() + READY_TIMEOUT;
    while Instant::now() < deadline {
        if TcpStream::connect_timeout(&bind_address, Duration::from_millis(150)).is_ok() {
            return Ok(());
        }

        if !HOST_STATE.lock().expect("host state lock").running {
            break;
        }
        thread::sleep(READY_POLL_INTERVAL);
    }

    Err(anyhow::anyhow!(
        "embedded app-server did not become reachable on ws://{bind_address} within {} ms",
        READY_TIMEOUT.as_millis()
    ))
}

fn configure_environment(codex_home: &Path) {
    let home_dir = codex_home
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| codex_home.to_path_buf());

    // SAFETY: this host initializes CODEX_HOME/HOME exactly once before the
    // embedded app-server runtime starts. The containing app process is already
    // multi-threaded, but codex-rs currently resolves CODEX_HOME from process
    // environment during startup, so this is the least invasive integration
    // point for the OHOS embedder path.
    unsafe {
        std::env::set_var("CODEX_HOME", codex_home);
        std::env::set_var("HOME", home_dir);
        std::env::set_var("CODEX_APP_SERVER_ALLOW_ORIGIN_HEADER", "1");
    }
}

fn resolve_codex_home(codex_home: Option<PathBuf>) -> PathBuf {
    codex_home
        .filter(|path| !path.as_os_str().is_empty())
        .or_else(|| {
            let state = HOST_STATE.lock().expect("host state lock");
            if state.codex_home.is_empty() {
                None
            } else {
                Some(PathBuf::from(state.codex_home.clone()))
            }
        })
        .unwrap_or_else(default_codex_home)
}

fn default_codex_home() -> PathBuf {
    std::env::temp_dir().join("codex-ohos-home")
}

fn update_host_state(
    running: bool,
    server_url: Option<String>,
    codex_home: Option<PathBuf>,
    message: String,
) {
    let mut state = HOST_STATE.lock().expect("host state lock");
    state.running = running;
    if let Some(server_url) = server_url {
        state.server_url = server_url;
    }
    if let Some(codex_home) = codex_home {
        state.codex_home = codex_home.to_string_lossy().into_owned();
    }
    state.message = message;
}

fn set_host_message(message: String) {
    let mut state = HOST_STATE.lock().expect("host state lock");
    state.message = message;
}

fn ffi_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }

    // SAFETY: caller guarantees a null-terminated string or null pointer.
    let value = unsafe { CStr::from_ptr(ptr) };
    value.to_str().ok().map(ToOwned::to_owned)
}

fn write_cstring(target: &Mutex<CString>, value: &str) -> *const c_char {
    let sanitized = value.replace('\0', " ");
    let mut slot = target.lock().expect("cstring lock");
    *slot = CString::new(sanitized).expect("sanitized cstring");
    slot.as_ptr()
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_initialize(config_json: *const c_char) -> *const c_char {
    let config_text = ffi_string(config_json).unwrap_or_else(|| "{}".to_string());
    let json = format!("{{\"ok\":true,\"config\":{}}}", config_text);
    write_cstring(&LAST_INIT_RESULT_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_start(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let json = format!(
        "{{\"thread\":{{\"id\":\"native-thread\"}},\"params\":{}}}",
        params_text
    );
    write_cstring(&LAST_THREAD_RESULT_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_turn_start(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let json = format!(
        "{{\"turn\":{{\"id\":\"native-turn\",\"status\":\"completed\"}},\"params\":{}}}",
        params_text
    );
    write_cstring(&LAST_TURN_RESULT_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_turn_events(
    _thread_id: *const c_char,
    _turn_id: *const c_char,
) -> *const c_char {
    write_cstring(&LAST_TURN_EVENTS_JSON, "[]")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_turn_poll(
    thread_id: *const c_char,
    turn_id: *const c_char,
) -> *const c_char {
    let thread_id = ffi_string(thread_id).unwrap_or_default();
    let turn_id = ffi_string(turn_id).unwrap_or_default();
    let json = format!(
        "{{\"threadId\":\"{}\",\"turnId\":\"{}\",\"status\":\"completed\",\"messages\":[],\"summary\":[]}}",
        escape_json_string(&thread_id),
        escape_json_string(&turn_id)
    );
    write_cstring(&LAST_TURN_POLL_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_approval_poll() -> *const c_char {
    write_cstring(&LAST_APPROVAL_JSON, "null")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_approval_approve(_params_json: *const c_char) -> i32 {
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_approval_decline(_params_json: *const c_char) -> i32 {
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_status_list(_params_json: *const c_char) -> *const c_char {
    write_cstring(&LAST_MCP_STATUS_JSON, "{\"data\":[],\"nextCursor\":null}")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_read(_params_json: *const c_char) -> *const c_char {
    write_cstring(&LAST_MCP_CONFIG_JSON, "{\"config\":{}}")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_write(_params_json: *const c_char) -> i32 {
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_batch_write(_params_json: *const c_char) -> i32 {
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_reload() -> i32 {
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_oauth_start(_params_json: *const c_char) -> *const c_char {
    write_cstring(&LAST_MCP_OAUTH_JSON, "{\"authorizationUrl\":\"\"}")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_account_login(_params_json: *const c_char) -> *const c_char {
    write_cstring(&LAST_ACCOUNT_JSON, "{\"ok\":true}")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_account_read() -> *const c_char {
    write_cstring(&LAST_ACCOUNT_JSON, "{\"account\":null,\"requiresOpenaiAuth\":false}")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_check_workspace_access(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let root_path = serde_json::from_str::<serde_json::Value>(&params_text)
        .ok()
        .and_then(|value| value.get("rootPath").and_then(|field| field.as_str()).map(ToOwned::to_owned))
        .unwrap_or_default();

    let trimmed_root = root_path.trim().to_string();
    let status = if trimmed_root.is_empty() {
        WorkspaceAccessStatus {
            root_path: trimmed_root,
            access_kind: "unknown".to_string(),
            permission_state: "unavailable".to_string(),
            writable: false,
            exists: false,
            message: "workspace root is empty".to_string(),
        }
    } else {
        let path = PathBuf::from(&trimmed_root);
        let exists = path.exists();
        if !exists {
            WorkspaceAccessStatus {
                root_path: trimmed_root,
                access_kind: infer_workspace_access_kind(&path),
                permission_state: "unavailable".to_string(),
                writable: false,
                exists: false,
                message: "workspace path does not exist".to_string(),
            }
        } else if !path.is_dir() {
            WorkspaceAccessStatus {
                root_path: trimmed_root,
                access_kind: infer_workspace_access_kind(&path),
                permission_state: "unavailable".to_string(),
                writable: false,
                exists: true,
                message: "workspace path is not a directory".to_string(),
            }
        } else {
            let writable = can_write_to_directory(&path);
            WorkspaceAccessStatus {
                root_path: trimmed_root,
                access_kind: infer_workspace_access_kind(&path),
                permission_state: if writable { "writable".to_string() } else { "readonly".to_string() },
                writable,
                exists: true,
                message: if writable {
                    "workspace is writable".to_string()
                } else {
                    "workspace exists but is not writable".to_string()
                },
            }
        }
    };

    let json = serde_json::to_string(&status).unwrap_or_else(|_| "{}".to_string());
    write_cstring(&LAST_WORKSPACE_ACCESS_JSON, &json)
}

fn escape_json_string(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn infer_workspace_access_kind(path: &Path) -> String {
    let normalized = path.to_string_lossy();
    if normalized.contains("/data/storage/") {
        "sandbox".to_string()
    } else {
        "unknown".to_string()
    }
}

fn can_write_to_directory(path: &Path) -> bool {
    let probe_path = path.join(".codex-write-test.tmp");
    match std::fs::write(&probe_path, b"ok") {
        Ok(()) => {
            let _ = std::fs::remove_file(&probe_path);
            true
        }
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_config_toml_includes_workspace_write_defaults() {
        let config = render_config_toml(&ProviderSettings {
            base_url: "https://example.com/v1".to_string(),
            api_key: "secret".to_string(),
            model: "test-model".to_string(),
        });

        assert!(config.contains("approval_policy = \"on-request\""));
        assert!(config.contains("sandbox_mode = \"workspace-write\""));
        assert!(config.contains("model = \"test-model\""));
        assert!(config.contains("base_url = \"https://example.com/v1\""));
        assert!(config.contains("experimental_bearer_token = \"secret\""));
    }
}
