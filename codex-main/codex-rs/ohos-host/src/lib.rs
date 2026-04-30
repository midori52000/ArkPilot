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

const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:7456";
const DEFAULT_PROVIDER_BASE_URL: &str = "https://api.openai.com/v1";
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
