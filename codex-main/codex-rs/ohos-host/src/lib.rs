use std::collections::BTreeMap;
use std::ffi::CStr;
use std::ffi::CString;
use std::net::SocketAddr;
use std::net::TcpStream;
use std::os::raw::c_char;
use std::path::Path;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use std::time::Instant;

use anyhow::Context;
use anyhow::Result;
use codex_app_server::AppServerTransport;
use codex_app_server::AppServerWebsocketAuthSettings;
use codex_app_server::run_main_with_transport;
use codex_app_server_client::AppServerEvent;
use codex_app_server_client::RemoteAppServerClient;
use codex_app_server_client::RemoteAppServerConnectArgs;
use codex_app_server_protocol::ApplyPatchApprovalResponse;
use codex_app_server_protocol::ApprovalsReviewer;
use codex_app_server_protocol::AskForApproval;
use codex_app_server_protocol::ClientRequest;
use codex_app_server_protocol::CommandExecutionApprovalDecision;
use codex_app_server_protocol::CommandExecutionRequestApprovalResponse;
use codex_app_server_protocol::FileChangeApprovalDecision;
use codex_app_server_protocol::FileChangeRequestApprovalResponse;
use codex_app_server_protocol::GrantedPermissionProfile;
use codex_app_server_protocol::ListMcpServerStatusParams;
use codex_app_server_protocol::ListMcpServerStatusResponse;
use codex_app_server_protocol::McpServerOauthLoginParams;
use codex_app_server_protocol::McpServerOauthLoginResponse;
use codex_app_server_protocol::McpServerRefreshResponse;
use codex_app_server_protocol::PermissionGrantScope;
use codex_app_server_protocol::PermissionsRequestApprovalResponse;
use codex_app_server_protocol::RequestId;
use codex_app_server_protocol::SandboxMode;
use codex_app_server_protocol::SandboxPolicy;
use codex_app_server_protocol::ServerNotification;
use codex_app_server_protocol::ServerRequest;
use codex_app_server_protocol::Thread;
use codex_app_server_protocol::ThreadArchiveParams;
use codex_app_server_protocol::ThreadArchiveResponse;
use codex_app_server_protocol::ThreadListParams;
use codex_app_server_protocol::ThreadListResponse;
use codex_app_server_protocol::ThreadReadParams;
use codex_app_server_protocol::ThreadReadResponse;
use codex_app_server_protocol::ThreadResumeParams;
use codex_app_server_protocol::ThreadResumeResponse;
use codex_app_server_protocol::ThreadSetNameParams;
use codex_app_server_protocol::ThreadSetNameResponse;
use codex_app_server_protocol::ThreadStartParams;
use codex_app_server_protocol::ThreadStartResponse;
use codex_app_server_protocol::TurnInterruptParams;
use codex_app_server_protocol::TurnInterruptResponse;
use codex_app_server_protocol::TurnStartParams;
use codex_app_server_protocol::TurnStartResponse;
use codex_app_server_protocol::TurnStatus;
use codex_app_server_protocol::UserInput;
use codex_arg0::Arg0DispatchPaths;
use codex_core::config::edit::ConfigEditsBuilder;
use codex_core::config::load_global_mcp_servers;
use codex_core::config::types::McpServerConfig;
use codex_core::config_loader::LoaderOverrides;
use codex_core::turn_diff_tracker::TurnDiffTracker;
use codex_protocol::openai_models::ReasoningEffort;
use codex_protocol::protocol::SessionSource;
use codex_utils_absolute_path::AbsolutePathBuf;
use codex_utils_cli::CliConfigOverrides;
use once_cell::sync::Lazy;
use serde::Deserialize;
use serde::Serialize;
use tokio::sync::Mutex as AsyncMutex;

mod prompts_registry;
mod skills_backup;
mod skills_hash;
mod skills_registry;

const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:7456";
const DEFAULT_PROVIDER_BASE_URL: &str = "http://192.168.31.101:8317/v1";
const DEFAULT_PROVIDER_API_KEY: &str = "midori52000";
const DEFAULT_PROVIDER_MODEL: &str = "gpt-5.4";
const DEFAULT_APPROVAL_POLICY: &str = "on-request";
const DEFAULT_SANDBOX_MODE: &str = "workspace-write";
const CUSTOM_PROVIDER_ID: &str = "harmony-openai-compatible";
const READY_TIMEOUT: Duration = Duration::from_secs(20);
const READY_POLL_INTERVAL: Duration = Duration::from_millis(100);
const DEFAULT_PROVIDER_MODE: &str = "exclusive";
const DEFAULT_PROVIDER_SYNC_STATUS: &str = "synced";
const REMOTE_CLIENT_NAME: &str = "codex_harmony_agent_native";
const REMOTE_CLIENT_VERSION: &str = "0.1.0";
const REMOTE_CLIENT_CHANNEL_CAPACITY: usize = 256;

#[derive(Default)]
struct HostState {
    running: bool,
    server_url: String,
    message: String,
    codex_home: String,
}

#[derive(Default)]
struct NativeConversationState {
    next_request_id: i64,
    client: Option<RemoteAppServerClient>,
    initialized: bool,
    threads: std::collections::HashMap<String, NativeThreadState>,
    turns: std::collections::HashMap<String, NativeTurnState>,
    pending_approval: Option<PendingApprovalState>,
}

#[derive(Debug, Clone)]
enum PendingApprovalResolutionKind {
    CommandExecution,
    FileChange,
    Permissions,
    LegacyPatch,
    LegacyExec,
}

#[derive(Debug, Clone)]
struct PendingApprovalState {
    request_id: RequestId,
    resolution_kind: PendingApprovalResolutionKind,
    payload_json: String,
}

#[derive(Debug, Clone, Default)]
struct NativeThreadState {
    remote_thread_id: String,
    cwd: Option<PathBuf>,
    messages: Vec<NativeMessage>,
}

#[derive(Clone, Default)]
struct NativeTurnState {
    thread_id: String,
    status: String,
    messages: Vec<NativeMessage>,
    summary: Vec<String>,
    summary_title: String,
    diff: String,
    diff_authoritative: bool,
    error_message: String,
    cwd: Option<PathBuf>,
    local_diff_tracker: Option<Arc<AsyncMutex<TurnDiffTracker>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct NativeMessage {
    message_id: String,
    author: String,
    role: String,
    content: String,
    timestamp: String,
    #[serde(default)]
    item_type: Option<String>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    metadata: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeInitializeRequest {
    #[serde(default)]
    client_info: Option<NativeClientInfo>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeClientInfo {
    #[allow(dead_code)]
    name: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeThreadStartRequest {
    cwd: Option<String>,
    model: Option<String>,
    approval_policy: Option<String>,
    sandbox_mode: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeTurnInput {
    #[serde(rename = "type")]
    kind: String,
    text: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeTurnStartRequest {
    thread_id: String,
    #[serde(default)]
    input: Vec<NativeTurnInput>,
    cwd: Option<String>,
    model: Option<String>,
    effort: Option<String>,
    approval_policy: Option<String>,
    sandbox_mode: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpStatusListRequest {
    cursor: Option<String>,
    limit: Option<u32>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeThreadListRequest {
    cursor: Option<String>,
    limit: Option<u32>,
    archived: Option<bool>,
    cwd: Option<String>,
    search_term: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpOauthStartRequest {
    name: String,
    #[serde(default)]
    scopes: Option<Vec<String>>,
    #[serde(default)]
    timeout_secs: Option<i64>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeThreadReadRequest {
    thread_id: String,
    #[serde(default)]
    include_turns: bool,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeThreadResumeRequest {
    thread_id: String,
    cwd: Option<String>,
    model: Option<String>,
    approval_policy: Option<String>,
    sandbox_mode: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeThreadNameSetRequest {
    thread_id: String,
    name: String,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpConfigReadRequest {
    #[serde(default)]
    include_layers: bool,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpConfigBatchEditRequest {
    key_path: String,
    value: serde_json::Value,
    merge_strategy: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpConfigBatchWriteRequest {
    #[serde(default)]
    edits: Vec<NativeMcpConfigBatchEditRequest>,
    #[serde(default)]
    reload_user_config: bool,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpConfigAddRequest {
    name: String,
    config: serde_json::Value,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeMcpConfigRemoveRequest {
    name: String,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeThreadArchiveRequest {
    thread_id: String,
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

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeApprovalActionRequest {
    request_id: serde_json::Value,
    kind: Option<String>,
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
            api_key: DEFAULT_PROVIDER_API_KEY.to_string(),
            model: DEFAULT_PROVIDER_MODEL.to_string(),
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
    let json =
        serde_json::to_string(&ProviderCatalog::default()).expect("default provider catalog json");
    Mutex::new(CString::new(json).expect("provider catalog cstring"))
});
static LAST_SKILLS_REGISTRY_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_SKILLS_REPOS_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_HASH_RESULT: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("").expect("empty cstring")));
static LAST_BACKUPS_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("[]").expect("empty cstring")));
static LAST_BACKUP_PATH: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("").expect("empty cstring")));
static LAST_INSTALL_SKILL_RESULT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_UNINSTALL_BACKUP_PATH: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("").expect("empty cstring")));
static LAST_SET_ENABLED_RESULT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_RECONCILE_RESULT_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"removed\":[],\"registered\":[]}").expect("empty cstring"))
});
static LAST_PROMPTS_REGISTRY_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_AGENTS_MD_CONTENT: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("").expect("empty cstring")));
static LAST_ENABLE_PROMPT_RESULT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_INIT_RESULT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_THREAD_RESULT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_THREAD_LIST_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"data\":[],\"nextCursor\":null}").expect("empty cstring"))
});
static LAST_THREAD_READ_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_THREAD_RESUME_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_THREAD_MUTATION_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{\"ok\":false}").expect("empty cstring")));
static LAST_TURN_RESULT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_TURN_EVENTS_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("[]").expect("empty cstring")));
static LAST_TURN_POLL_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_TURN_INTERRUPT_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static LAST_APPROVAL_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("null").expect("empty cstring")));
static LAST_MCP_STATUS_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(CString::new("{\"data\":[],\"nextCursor\":null}").expect("empty cstring"))
});
static LAST_MCP_CONFIG_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{\"config\":{}}").expect("empty cstring")));
static LAST_MCP_OAUTH_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{\"authorizationUrl\":\"\"}").expect("empty cstring")));
static LAST_ACCOUNT_JSON: Lazy<Mutex<CString>> = Lazy::new(|| {
    Mutex::new(
        CString::new("{\"account\":null,\"requiresOpenaiAuth\":false}").expect("empty cstring"),
    )
});
static LAST_WORKSPACE_ACCESS_JSON: Lazy<Mutex<CString>> =
    Lazy::new(|| Mutex::new(CString::new("{}").expect("empty cstring")));
static NATIVE_CONVERSATION_STATE: Lazy<Mutex<NativeConversationState>> =
    Lazy::new(|| Mutex::new(NativeConversationState::default()));
static NATIVE_ASYNC_RUNTIME: Lazy<Mutex<tokio::runtime::Runtime>> = Lazy::new(|| {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .expect("native async runtime");
    Mutex::new(runtime)
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
            update_host_state(
                false,
                None,
                None,
                format!("embedded app-server start failed: {err}"),
            );
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
pub extern "C" fn codex_ohos_host_provider_catalog_json(
    codex_home: *const c_char,
) -> *const c_char {
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

// ========== Skills Install / Uninstall / Enable / Reconcile ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_install_skill_from_dir(
    codex_home: *const c_char,
    source_dir: *const c_char,
    skill_json: *const c_char,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(source_dir) = ffi_string(source_dir) else {
        return write_cstring(&LAST_INSTALL_SKILL_RESULT_JSON, "{}");
    };
    let Some(skill_json) = ffi_string(skill_json) else {
        return write_cstring(&LAST_INSTALL_SKILL_RESULT_JSON, "{}");
    };
    match skills_registry::install_skill_from_dir(&codex_home, Path::new(&source_dir), &skill_json)
    {
        Ok(entry) => {
            let json = serde_json::to_string(&entry).unwrap_or_else(|_| "{}".into());
            write_cstring(&LAST_INSTALL_SKILL_RESULT_JSON, &json)
        }
        Err(e) => write_cstring(
            &LAST_INSTALL_SKILL_RESULT_JSON,
            &format!("{{\"error\":\"{}\"}}", e),
        ),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_uninstall_skill(
    codex_home: *const c_char,
    skill_id: *const c_char,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(skill_id) = ffi_string(skill_id) else {
        return write_cstring(&LAST_UNINSTALL_BACKUP_PATH, "");
    };
    match skills_registry::uninstall_skill(&codex_home, &skill_id) {
        Ok(backup_path) => write_cstring(&LAST_UNINSTALL_BACKUP_PATH, &backup_path),
        Err(e) => write_cstring(&LAST_UNINSTALL_BACKUP_PATH, &format!("error:{}", e)),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_set_skill_enabled(
    codex_home: *const c_char,
    skill_id: *const c_char,
    enabled: i32,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(skill_id) = ffi_string(skill_id) else {
        return write_cstring(&LAST_SET_ENABLED_RESULT_JSON, "{}");
    };
    match skills_registry::set_skill_enabled(&codex_home, &skill_id, enabled != 0) {
        Ok(entry) => {
            let json = serde_json::to_string(&entry).unwrap_or_else(|_| "{}".into());
            write_cstring(&LAST_SET_ENABLED_RESULT_JSON, &json)
        }
        Err(e) => write_cstring(
            &LAST_SET_ENABLED_RESULT_JSON,
            &format!("{{\"error\":\"{}\"}}", e),
        ),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_reconcile_skills(codex_home: *const c_char) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let result = skills_registry::reconcile_skills(&codex_home);
    let json = serde_json::to_string(&result)
        .unwrap_or_else(|_| "{\"removed\":[],\"registered\":[]}".into());
    write_cstring(&LAST_RECONCILE_RESULT_JSON, &json)
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
    let Some(json_str) = ffi_string(registry_json) else {
        return 1;
    };
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
pub extern "C" fn codex_ohos_host_read_agents_md(codex_home: *const c_char) -> *const c_char {
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
    let Some(content) = ffi_string(content) else {
        return 1;
    };
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

// ========== Prompts Enable / DisableAll with AGENTS.md sync ==========

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_enable_prompt(
    codex_home: *const c_char,
    prompt_id: *const c_char,
) -> *const c_char {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    let Some(id) = ffi_string(prompt_id) else {
        return write_cstring(&LAST_ENABLE_PROMPT_RESULT_JSON, "{}");
    };
    match prompts_registry::enable_prompt_with_agents_md(&codex_home, &id) {
        Ok(entry) => {
            let json = serde_json::to_string(&entry).unwrap_or_else(|_| "{}".into());
            write_cstring(&LAST_ENABLE_PROMPT_RESULT_JSON, &json)
        }
        Err(e) => write_cstring(
            &LAST_ENABLE_PROMPT_RESULT_JSON,
            &format!("{{\"error\":\"{}\"}}", e),
        ),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_disable_all_prompts(codex_home: *const c_char) -> i32 {
    let codex_home = resolve_codex_home(ffi_string(codex_home).map(PathBuf::from));
    match prompts_registry::disable_all_with_agents_md(&codex_home) {
        Ok(()) => 0,
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
                Ok(()) => {
                    update_host_state(false, None, None, "embedded app-server stopped".to_string())
                }
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
    let catalog = load_provider_catalog(codex_home).unwrap_or_else(|_| ProviderCatalog {
        version: 1,
        active_provider_id: "live-provider".to_string(),
        providers: vec![catalog_record_from_settings(
            "live-provider",
            "当前 Live Provider",
            &settings,
            true,
        )],
        updated_at: current_timestamp_string(),
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
            providers: vec![catalog_record_from_settings(
                "live-provider",
                "当前 Live Provider",
                &settings,
                true,
            )],
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
        lines.insert(3, format!("model = {}", toml_string(&settings.model)));
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

    if !catalog
        .providers
        .iter()
        .any(|provider| provider.id == active_id)
    {
        catalog.active_provider_id = catalog.providers[0].id.clone();
        if let Some(first) = catalog.providers.first_mut() {
            first.is_active = true;
        }
    }
    catalog
}

fn current_timestamp_string() -> String {
    format!(
        "{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_secs())
            .unwrap_or(0)
    )
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
        // Explicit skills directory for the skill loader. On OHOS, `dirs` crate
        // v6+ uses `/etc/passwd` instead of `$HOME`, so the default
        // `$HOME/.agents/skills` path is wrong. This env var is checked by
        // `skill_roots_with_home_dir()` in core-skills as a fallback.
        std::env::set_var("CODEX_SKILLS_DIR", codex_home.join("skills"));
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

fn build_local_turn_diff_tracker(cwd: Option<&Path>) -> Option<Arc<AsyncMutex<TurnDiffTracker>>> {
    let cwd = cwd?.to_path_buf();
    let mut tracker = TurnDiffTracker::new();
    tracker.on_exec_begin(&cwd);
    Some(Arc::new(AsyncMutex::new(tracker)))
}

fn should_refresh_turn_diff_from_local_tracker(turn_id: &str) -> bool {
    if turn_id.is_empty() {
        return false;
    }
    with_native_state(|state| {
        state
            .turns
            .get(turn_id)
            .map(|turn| {
                !turn.diff_authoritative && turn.cwd.is_some() && turn.local_diff_tracker.is_some()
            })
            .unwrap_or(false)
    })
}

async fn refresh_turn_diff_from_local_tracker(turn_id: &str) -> Result<()> {
    let Some((cwd, tracker)) = with_native_state(|state| {
        state.turns.get(turn_id).and_then(|turn| {
            let cwd = turn.cwd.clone()?;
            let tracker = turn.local_diff_tracker.clone()?;
            Some((cwd, tracker))
        })
    }) else {
        return Ok(());
    };

    let diff = {
        let mut guard = tracker.lock().await;
        guard.on_exec_end(&cwd);
        guard.get_unified_diff()?
    };

    let normalized_diff = diff
        .as_deref()
        .map(str::trim)
        .unwrap_or_default()
        .to_string();
    with_native_state(|state| {
        if let Some(turn) = state.turns.get_mut(turn_id)
            && !turn.diff_authoritative
        {
            turn.diff = normalized_diff;
        }
    });

    Ok(())
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_initialize(config_json: *const c_char) -> *const c_char {
    let config_text = ffi_string(config_json).unwrap_or_else(|| "{}".to_string());
    let request = serde_json::from_str::<NativeInitializeRequest>(&config_text).ok();

    match with_runtime_result(connect_remote_client_if_needed()) {
        Ok(()) => {
            let mut state = NATIVE_CONVERSATION_STATE
                .lock()
                .expect("native conversation lock");
            state.initialized = true;
            let platform_os = "ohos";
            let client_name = request
                .and_then(|payload| payload.client_info.and_then(|info| info.name))
                .unwrap_or_else(|| REMOTE_CLIENT_NAME.to_string());
            let server_url = current_server_url();
            let json = serde_json::json!({
                "ok": true,
                "platformOs": platform_os,
                "serverUrl": server_url,
                "clientName": client_name,
            })
            .to_string();
            write_cstring(&LAST_INIT_RESULT_JSON, &json)
        }
        Err(err) => {
            let json = serde_json::json!({
                "ok": false,
                "platformOs": "ohos",
                "error": err.to_string(),
            })
            .to_string();
            write_cstring(&LAST_INIT_RESULT_JSON, &json)
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_start(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeThreadStartRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let mut params = ThreadStartParams::default();
        params.cwd = request.cwd.filter(|value| !value.trim().is_empty());
        params.model = request.model.filter(|value| !value.trim().is_empty());
        params.model_provider = Some(CUSTOM_PROVIDER_ID.to_string());
        params.approval_policy = parse_approval_policy(
            request
                .approval_policy
                .as_deref()
                .or(Some(DEFAULT_APPROVAL_POLICY)),
        )?;
        params.approvals_reviewer = Some(ApprovalsReviewer::User);
        params.sandbox = parse_thread_sandbox_mode(
            request
                .sandbox_mode
                .as_deref()
                .or(Some(DEFAULT_SANDBOX_MODE)),
        )?;
        params.ephemeral = Some(false);
        params.persist_extended_history = true;

        let response: ThreadStartResponse = handle
            .request_typed(ClientRequest::ThreadStart { request_id, params })
            .await
            .map_err(anyhow::Error::from)?;

        with_native_state(|state| {
            state.threads.insert(
                response.thread.id.clone(),
                NativeThreadState {
                    remote_thread_id: response.thread.id.clone(),
                    cwd: Some(response.cwd.clone()),
                    messages: collect_thread_messages(&response.thread.turns),
                },
            );
        });

        Ok::<ThreadStartResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => serde_json::json!({
            "thread": { "id": response.thread.id },
            "model": response.model,
            "cwd": response.cwd,
        })
        .to_string(),
        Err(err) => serde_json::json!({
            "thread": { "id": "" },
            "error": { "message": err.to_string() },
        })
        .to_string(),
    };
    write_cstring(&LAST_THREAD_RESULT_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_list(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = serde_json::from_str::<NativeThreadListRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let params = ThreadListParams {
            cursor: request.cursor.filter(|value| !value.trim().is_empty()),
            limit: request.limit,
            sort_key: Some(codex_app_server_protocol::ThreadSortKey::UpdatedAt),
            model_providers: None,
            source_kinds: None,
            archived: request.archived,
            cwd: request.cwd.filter(|value| !value.trim().is_empty()),
            search_term: request.search_term.filter(|value| !value.trim().is_empty()),
        };

        let response: ThreadListResponse = handle
            .request_typed(ClientRequest::ThreadList { request_id, params })
            .await
            .map_err(anyhow::Error::from)?;

        Ok::<ThreadListResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => build_thread_list_payload(&response).to_string(),
        Err(err) => serde_json::json!({
            "data": [],
            "nextCursor": null,
            "error": { "message": err.to_string() },
        })
        .to_string(),
    };
    write_cstring(&LAST_THREAD_LIST_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_read(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = serde_json::from_str::<NativeThreadReadRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let response: ThreadReadResponse = handle
            .request_typed(ClientRequest::ThreadRead {
                request_id,
                params: ThreadReadParams {
                    thread_id: request.thread_id.clone(),
                    include_turns: request.include_turns,
                },
            })
            .await
            .map_err(anyhow::Error::from)?;

        with_native_state(|state| {
            upsert_thread_state_from_protocol(state, &response.thread, request.include_turns);
        });

        Ok::<ThreadReadResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => build_thread_read_payload(&response.thread).to_string(),
        Err(err) => serde_json::json!({
            "thread": { "id": request.thread_id },
            "messages": [],
            "diff": "",
            "diffStat": "+0 -0",
            "changedFiles": [],
            "changedFilesText": "",
            "summaryTitle": "会话读取失败",
            "summary": [err.to_string()],
            "lastTurnId": "",
            "lastTurnStatus": "failed",
            "error": { "message": err.to_string() },
        })
        .to_string(),
    };
    write_cstring(&LAST_THREAD_READ_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_resume(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeThreadResumeRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let mut params = ThreadResumeParams::default();
        params.thread_id = request.thread_id.clone();
        params.cwd = request.cwd.filter(|value| !value.trim().is_empty());
        params.model = request.model.filter(|value| !value.trim().is_empty());
        params.model_provider = Some(CUSTOM_PROVIDER_ID.to_string());
        params.approval_policy = parse_approval_policy(
            request
                .approval_policy
                .as_deref()
                .or(Some(DEFAULT_APPROVAL_POLICY)),
        )?;
        params.approvals_reviewer = Some(ApprovalsReviewer::User);
        params.sandbox = parse_thread_sandbox_mode(
            request
                .sandbox_mode
                .as_deref()
                .or(Some(DEFAULT_SANDBOX_MODE)),
        )?;
        params.persist_extended_history = true;

        let response: ThreadResumeResponse = handle
            .request_typed(ClientRequest::ThreadResume { request_id, params })
            .await
            .map_err(anyhow::Error::from)?;

        with_native_state(|state| {
            upsert_thread_state_from_protocol(state, &response.thread, true);
        });

        Ok::<ThreadResumeResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => serde_json::json!({
            "thread": build_thread_meta_payload(&response.thread),
            "model": response.model,
            "cwd": response.cwd.display().to_string(),
        })
        .to_string(),
        Err(err) => serde_json::json!({
            "thread": { "id": request.thread_id },
            "error": { "message": err.to_string() },
        })
        .to_string(),
    };
    write_cstring(&LAST_THREAD_RESUME_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_name_set(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeThreadNameSetRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let _: ThreadSetNameResponse = handle
            .request_typed(ClientRequest::ThreadSetName {
                request_id,
                params: ThreadSetNameParams {
                    thread_id: request.thread_id.clone(),
                    name: request.name.clone(),
                },
            })
            .await
            .map_err(anyhow::Error::from)?;

        Ok::<(), anyhow::Error>(())
    });

    let json = match response {
        Ok(()) => serde_json::json!({
            "ok": true,
            "threadId": request.thread_id,
            "name": request.name,
        })
        .to_string(),
        Err(err) => serde_json::json!({
            "ok": false,
            "threadId": request.thread_id,
            "error": { "message": err.to_string() },
        })
        .to_string(),
    };
    write_cstring(&LAST_THREAD_MUTATION_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_thread_archive(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeThreadArchiveRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let _: ThreadArchiveResponse = handle
            .request_typed(ClientRequest::ThreadArchive {
                request_id,
                params: ThreadArchiveParams {
                    thread_id: request.thread_id.clone(),
                },
            })
            .await
            .map_err(anyhow::Error::from)?;

        with_native_state(|state| {
            state.threads.remove(&request.thread_id);
            state
                .turns
                .retain(|_, turn| turn.thread_id != request.thread_id);
        });

        Ok::<(), anyhow::Error>(())
    });

    let json = match response {
        Ok(()) => serde_json::json!({
            "ok": true,
            "threadId": request.thread_id,
        })
        .to_string(),
        Err(err) => serde_json::json!({
            "ok": false,
            "threadId": request.thread_id,
            "error": { "message": err.to_string() },
        })
        .to_string(),
    };
    write_cstring(&LAST_THREAD_MUTATION_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_turn_start(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = serde_json::from_str::<NativeTurnStartRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let mut params = TurnStartParams::default();
        params.thread_id = request.thread_id.clone();
        let cwd = request
            .cwd
            .filter(|value| !value.trim().is_empty())
            .map(PathBuf::from);
        params.cwd = cwd.clone();
        params.model = request.model.filter(|value| !value.trim().is_empty());
        params.effort = parse_reasoning_effort(request.effort.as_deref())?;
        params.approval_policy = parse_approval_policy(
            request
                .approval_policy
                .as_deref()
                .or(Some(DEFAULT_APPROVAL_POLICY)),
        )?;
        params.approvals_reviewer = Some(ApprovalsReviewer::User);
        params.sandbox_policy = build_sandbox_policy(
            request
                .sandbox_mode
                .as_deref()
                .or(Some(DEFAULT_SANDBOX_MODE)),
            cwd.as_deref(),
        )?;
        params.input = request
            .input
            .into_iter()
            .filter_map(|item| {
                if item.kind == "text" {
                    let text = item.text.unwrap_or_default();
                    Some(UserInput::Text {
                        text,
                        text_elements: Vec::new(),
                    })
                } else {
                    None
                }
            })
            .collect();

        let response: TurnStartResponse = handle
            .request_typed(ClientRequest::TurnStart { request_id, params })
            .await
            .map_err(anyhow::Error::from)?;

        let turn_cwd = cwd.clone().or_else(|| {
            with_native_state(|state| {
                state
                    .threads
                    .get(&request.thread_id)
                    .and_then(|thread| thread.cwd.clone())
            })
        });
        let local_diff_tracker = build_local_turn_diff_tracker(turn_cwd.as_deref());

        with_native_state(|state| {
            state.turns.insert(
                response.turn.id.clone(),
                NativeTurnState {
                    thread_id: request.thread_id.clone(),
                    status: map_turn_status(&response.turn.status).to_string(),
                    messages: Vec::new(),
                    summary: vec!["正在等待 Codex 响应".to_string()],
                    summary_title: "执行中".to_string(),
                    diff: String::new(),
                    diff_authoritative: false,
                    error_message: String::new(),
                    cwd: turn_cwd,
                    local_diff_tracker,
                },
            );
        });

        Ok::<TurnStartResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => serde_json::json!({
            "turn": {
                "id": response.turn.id,
                "status": map_turn_status(&response.turn.status),
            }
        })
        .to_string(),
        Err(err) => serde_json::json!({
            "turn": {
                "id": "",
                "status": "failed",
                "error": { "message": err.to_string() }
            }
        })
        .to_string(),
    };
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
    let response = with_runtime_result(async {
        process_pending_events(Some(&turn_id)).await?;
        if should_wait_for_trailing_turn_diff(&turn_id) {
            process_pending_events_with_idle_timeout(Some(&turn_id), Duration::from_millis(300))
                .await?;
        }
        if should_refresh_turn_diff_from_local_tracker(&turn_id) {
            refresh_turn_diff_from_local_tracker(&turn_id).await?;
        }
        Ok(())
    });

    let json = match response {
        Ok(()) => {
            let snapshot =
                with_native_state(|state| build_turn_poll_payload(state, &thread_id, &turn_id));
            serde_json::to_string(&snapshot).unwrap_or_else(|_| {
                serde_json::json!({
                    "threadId": thread_id,
                    "turnId": turn_id,
                    "status": "failed",
                    "messages": [],
                    "summary": ["轮询结果序列化失败。"],
                })
                .to_string()
            })
        }
        Err(err) => serde_json::json!({
            "threadId": thread_id,
            "turnId": turn_id,
            "status": "failed",
            "messages": [],
            "summaryTitle": "轮询失败",
            "summary": [err.to_string()],
        })
        .to_string(),
    };
    write_cstring(&LAST_TURN_POLL_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_turn_interrupt(
    thread_id: *const c_char,
    turn_id: *const c_char,
) -> *const c_char {
    let thread_id = ffi_string(thread_id).unwrap_or_default();
    let turn_id = ffi_string(turn_id).unwrap_or_default();

    let setup = with_native_handle(|state| {
        let handle = state
            .client
            .as_ref()
            .map(RemoteAppServerClient::request_handle)
            .context("remote app-server client is not initialized")?;
        let request_id = next_request_id(state);
        Ok::<_, anyhow::Error>((handle, request_id, thread_id.clone(), turn_id.clone()))
    });

    match setup {
        Ok((handle, request_id, tid, tturn_id)) => {
            thread::spawn(move || {
                let runtime = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build();
                match runtime {
                    Ok(rt) => {
                        let result: Result<()> = rt.block_on(async {
                            let _: TurnInterruptResponse = handle
                                .request_typed(ClientRequest::TurnInterrupt {
                                    request_id,
                                    params: TurnInterruptParams {
                                        thread_id: tid,
                                        turn_id: tturn_id,
                                    },
                                })
                                .await
                                .map_err(anyhow::Error::from)?;
                            Ok(())
                        });
                        let _ = result;
                    }
                    Err(_) => {}
                }
            });
            write_cstring(
                &LAST_TURN_INTERRUPT_JSON,
                &serde_json::json!({ "ok": true }).to_string(),
            )
        }
        Err(err) => write_cstring(
            &LAST_TURN_INTERRUPT_JSON,
            &serde_json::json!({ "ok": false, "error": { "message": err.to_string() } }).to_string(),
        ),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_approval_poll() -> *const c_char {
    let payload = with_native_state(|state| {
        state
            .pending_approval
            .as_ref()
            .map(|approval| approval.payload_json.clone())
            .unwrap_or_else(|| "null".to_string())
    });
    write_cstring(&LAST_APPROVAL_JSON, &payload)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_approval_approve(params_json: *const c_char) -> i32 {
    resolve_pending_approval(params_json, true)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_approval_decline(params_json: *const c_char) -> i32 {
    resolve_pending_approval(params_json, false)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_status_list(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeMcpStatusListRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let params = ListMcpServerStatusParams {
            cursor: request.cursor.filter(|value| !value.trim().is_empty()),
            limit: request.limit,
        };

        let response: ListMcpServerStatusResponse = handle
            .request_typed(ClientRequest::McpServerStatusList { request_id, params })
            .await
            .map_err(anyhow::Error::from)?;

        Ok::<ListMcpServerStatusResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => serde_json::to_string(&response)
            .unwrap_or_else(|_| "{\"data\":[],\"nextCursor\":null}".to_string()),
        Err(err) => {
            set_host_message(format!("failed to list MCP status: {err}"));
            "{\"data\":[],\"nextCursor\":null}".to_string()
        }
    };
    write_cstring(&LAST_MCP_STATUS_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_read(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let _request =
        serde_json::from_str::<NativeMcpConfigReadRequest>(&params_text).unwrap_or_default();
    let codex_home = resolve_codex_home(None);

    let json = match mcp_servers_to_config_json(&codex_home) {
        Ok(json) => json,
        Err(err) => {
            set_host_message(format!("failed to read MCP config: {err}"));
            "{\"config\":{}}".to_string()
        }
    };
    write_cstring(&LAST_MCP_CONFIG_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_write(params_json: *const c_char) -> i32 {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = match serde_json::from_str::<NativeMcpConfigBatchEditRequest>(&params_text) {
        Ok(request) => request,
        Err(err) => {
            set_host_message(format!("failed to parse MCP config write request: {err}"));
            return 1;
        }
    };
    let codex_home = resolve_codex_home(None);
    match apply_mcp_batch_edits(&codex_home, vec![request]) {
        Ok(()) => 0,
        Err(err) => {
            set_host_message(format!("failed to write MCP config: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_batch_write(params_json: *const c_char) -> i32 {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = match serde_json::from_str::<NativeMcpConfigBatchWriteRequest>(&params_text) {
        Ok(request) => request,
        Err(err) => {
            set_host_message(format!("failed to parse MCP batch write request: {err}"));
            return 1;
        }
    };
    let codex_home = resolve_codex_home(None);
    match apply_mcp_batch_edits(&codex_home, request.edits) {
        Ok(()) => 0,
        Err(err) => {
            set_host_message(format!("failed to batch write MCP config: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_add(params_json: *const c_char) -> i32 {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = match serde_json::from_str::<NativeMcpConfigAddRequest>(&params_text) {
        Ok(request) => request,
        Err(err) => {
            set_host_message(format!("failed to parse MCP config add request: {err}"));
            return 1;
        }
    };
    let name = request.name.trim().to_string();
    if name.is_empty() {
        set_host_message("MCP server name cannot be empty".to_string());
        return 1;
    }
    let codex_home = resolve_codex_home(None);
    let result = (|| -> Result<()> {
        let mut servers = with_runtime_result(async {
            load_global_mcp_servers(&codex_home)
                .await
                .map_err(anyhow::Error::from)
        })?;
        if servers.contains_key(&name) {
            anyhow::bail!("MCP server '{name}' already exists");
        }
        let parsed = parse_mcp_server_value(request.config)?;
        servers.insert(name, parsed);
        write_mcp_servers(&codex_home, &servers)
    })();
    match result {
        Ok(()) => 0,
        Err(err) => {
            set_host_message(format!("failed to add MCP server: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_config_remove(params_json: *const c_char) -> i32 {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request = match serde_json::from_str::<NativeMcpConfigRemoveRequest>(&params_text) {
        Ok(request) => request,
        Err(err) => {
            set_host_message(format!("failed to parse MCP config remove request: {err}"));
            return 1;
        }
    };
    let name = request.name.trim().to_string();
    if name.is_empty() {
        set_host_message("MCP server name cannot be empty".to_string());
        return 1;
    }
    let codex_home = resolve_codex_home(None);
    let result = (|| -> Result<()> {
        let mut servers = with_runtime_result(async {
            load_global_mcp_servers(&codex_home)
                .await
                .map_err(anyhow::Error::from)
        })?;
        if !servers.contains_key(&name) {
            anyhow::bail!("MCP server '{name}' not found");
        }
        servers.remove(&name);
        write_mcp_servers(&codex_home, &servers)
    })();
    match result {
        Ok(()) => 0,
        Err(err) => {
            set_host_message(format!("failed to remove MCP server: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_reload() -> i32 {
    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let _response: McpServerRefreshResponse = handle
            .request_typed(ClientRequest::McpServerRefresh {
                request_id,
                params: None,
            })
            .await
            .map_err(anyhow::Error::from)?;
        Ok::<(), anyhow::Error>(())
    });

    match response {
        Ok(()) => 0,
        Err(err) => {
            set_host_message(format!("failed to reload MCP config: {err}"));
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_mcp_oauth_start(params_json: *const c_char) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeMcpOauthStartRequest>(&params_text).unwrap_or_default();

    let response = with_runtime_result(async {
        let (handle, request_id) = with_native_handle(|state| {
            let handle = state
                .client
                .as_ref()
                .map(RemoteAppServerClient::request_handle)
                .context("remote app-server client is not initialized")?;
            let request_id = next_request_id(state);
            Ok::<_, anyhow::Error>((handle, request_id))
        })?;

        let params = McpServerOauthLoginParams {
            name: request.name,
            scopes: request.scopes,
            timeout_secs: request.timeout_secs,
        };

        let response: McpServerOauthLoginResponse = handle
            .request_typed(ClientRequest::McpServerOauthLogin { request_id, params })
            .await
            .map_err(anyhow::Error::from)?;

        Ok::<McpServerOauthLoginResponse, anyhow::Error>(response)
    });

    let json = match response {
        Ok(response) => serde_json::json!({
            "authorizationUrl": response.authorization_url,
        })
        .to_string(),
        Err(err) => {
            set_host_message(format!("failed to start MCP OAuth login: {err}"));
            "{\"authorizationUrl\":\"\"}".to_string()
        }
    };
    write_cstring(&LAST_MCP_OAUTH_JSON, &json)
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_account_login(_params_json: *const c_char) -> *const c_char {
    write_cstring(&LAST_ACCOUNT_JSON, "{\"ok\":true}")
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_account_read() -> *const c_char {
    write_cstring(
        &LAST_ACCOUNT_JSON,
        "{\"account\":null,\"requiresOpenaiAuth\":false}",
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn codex_ohos_host_check_workspace_access(
    params_json: *const c_char,
) -> *const c_char {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let root_path = serde_json::from_str::<serde_json::Value>(&params_text)
        .ok()
        .and_then(|value| {
            value
                .get("rootPath")
                .and_then(|field| field.as_str())
                .map(ToOwned::to_owned)
        })
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
                permission_state: if writable {
                    "writable".to_string()
                } else {
                    "readonly".to_string()
                },
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

fn current_server_url() -> String {
    let state = HOST_STATE.lock().expect("host state lock");
    if state.server_url.trim().is_empty() {
        DEFAULT_LISTEN_URL.to_string()
    } else {
        state.server_url.clone()
    }
}

fn with_runtime_result<F, T>(future: F) -> Result<T>
where
    F: std::future::Future<Output = Result<T>>,
{
    let runtime = NATIVE_ASYNC_RUNTIME
        .lock()
        .expect("native async runtime lock");
    runtime.block_on(future)
}

fn with_native_state<T>(f: impl FnOnce(&mut NativeConversationState) -> T) -> T {
    let mut state = NATIVE_CONVERSATION_STATE
        .lock()
        .expect("native conversation lock");
    f(&mut state)
}

fn with_native_handle<T>(f: impl FnOnce(&mut NativeConversationState) -> Result<T>) -> Result<T> {
    let mut state = NATIVE_CONVERSATION_STATE
        .lock()
        .expect("native conversation lock");
    f(&mut state)
}

fn clear_pending_approval() {
    with_native_state(|state| {
        state.pending_approval = None;
    });
    let _ = write_cstring(&LAST_APPROVAL_JSON, "null");
}

fn set_pending_approval(state: &mut NativeConversationState, approval: PendingApprovalState) {
    let payload = approval.payload_json.clone();
    state.pending_approval = Some(approval);
    let _ = write_cstring(&LAST_APPROVAL_JSON, &payload);
}

fn next_request_id(state: &mut NativeConversationState) -> RequestId {
    state.next_request_id += 1;
    RequestId::Integer(state.next_request_id)
}

async fn connect_remote_client_if_needed() -> Result<()> {
    let already_connected = {
        let state = NATIVE_CONVERSATION_STATE
            .lock()
            .expect("native conversation lock");
        state.client.is_some()
    };
    if already_connected {
        return Ok(());
    }

    let args = RemoteAppServerConnectArgs {
        websocket_url: current_server_url(),
        auth_token: None,
        client_name: REMOTE_CLIENT_NAME.to_string(),
        client_version: REMOTE_CLIENT_VERSION.to_string(),
        experimental_api: true,
        opt_out_notification_methods: Vec::new(),
        channel_capacity: REMOTE_CLIENT_CHANNEL_CAPACITY,
    };
    let client = RemoteAppServerClient::connect(args)
        .await
        .context("failed to connect embedded websocket app-server")?;
    with_native_state(|state| {
        state.client = Some(client);
        state.initialized = true;
    });
    Ok(())
}

fn parse_reasoning_effort(raw: Option<&str>) -> Result<Option<ReasoningEffort>> {
    match raw.map(str::trim).filter(|value| !value.is_empty()) {
        None => Ok(None),
        Some("default") => Ok(None),
        Some(value) => value
            .parse::<ReasoningEffort>()
            .map(Some)
            .map_err(anyhow::Error::msg),
    }
}

fn mcp_servers_to_config_json(codex_home: &Path) -> Result<String> {
    let servers = with_runtime_result(async {
        load_global_mcp_servers(codex_home)
            .await
            .map_err(anyhow::Error::from)
    })?;
    let config = serde_json::json!({ "config": { "mcp_servers": servers } });
    serde_json::to_string(&config).map_err(anyhow::Error::from)
}

fn parse_mcp_server_value(value: serde_json::Value) -> Result<McpServerConfig> {
    serde_json::from_value::<McpServerConfig>(value).map_err(anyhow::Error::from)
}

fn write_mcp_servers(codex_home: &Path, servers: &BTreeMap<String, McpServerConfig>) -> Result<()> {
    ConfigEditsBuilder::new(codex_home)
        .replace_mcp_servers(servers)
        .apply_blocking()
}

fn apply_mcp_batch_edits(
    codex_home: &Path,
    edits: Vec<NativeMcpConfigBatchEditRequest>,
) -> Result<()> {
    let mut servers = with_runtime_result(async {
        load_global_mcp_servers(codex_home)
            .await
            .map_err(anyhow::Error::from)
    })?;
    for edit in edits {
        let key_path = edit.key_path.trim();
        if !key_path.starts_with("mcp_servers.") {
            anyhow::bail!("unsupported MCP config key path: {key_path}");
        }
        let server_name = key_path.trim_start_matches("mcp_servers.").trim();
        if server_name.is_empty() || server_name.contains('.') {
            anyhow::bail!("invalid MCP server key path: {key_path}");
        }
        let merge_strategy = edit.merge_strategy.unwrap_or_else(|| "replace".to_string());
        if merge_strategy != "replace" {
            anyhow::bail!("unsupported MCP merge strategy: {merge_strategy}");
        }
        let parsed = parse_mcp_server_value(edit.value)?;
        servers.insert(server_name.to_string(), parsed);
    }
    write_mcp_servers(codex_home, &servers)
}

fn parse_approval_policy(raw: Option<&str>) -> Result<Option<AskForApproval>> {
    match raw.map(str::trim).filter(|value| !value.is_empty()) {
        None => Ok(None),
        Some("default") => Ok(None),
        Some("untrusted") | Some("unless-trusted") => Ok(Some(AskForApproval::UnlessTrusted)),
        Some("on-failure") => Ok(Some(AskForApproval::OnFailure)),
        Some("on-request") => Ok(Some(AskForApproval::OnRequest)),
        Some("never") => Ok(Some(AskForApproval::Never)),
        Some(other) => anyhow::bail!("unsupported approval policy: {other}"),
    }
}

fn parse_thread_sandbox_mode(raw: Option<&str>) -> Result<Option<SandboxMode>> {
    match raw.map(str::trim).filter(|value| !value.is_empty()) {
        None => Ok(None),
        Some("danger-full-access") => Ok(Some(SandboxMode::DangerFullAccess)),
        Some("read-only") => Ok(Some(SandboxMode::ReadOnly)),
        Some("workspace-write") => Ok(Some(SandboxMode::WorkspaceWrite)),
        Some(other) => anyhow::bail!("unsupported sandbox mode: {other}"),
    }
}

fn build_sandbox_policy(raw: Option<&str>, cwd: Option<&Path>) -> Result<Option<SandboxPolicy>> {
    match raw.map(str::trim).filter(|value| !value.is_empty()) {
        None => Ok(None),
        Some("default") => Ok(None),
        Some("danger-full-access") => Ok(Some(SandboxPolicy::DangerFullAccess)),
        Some("read-only") => Ok(Some(SandboxPolicy::ReadOnly {
            access: codex_app_server_protocol::ReadOnlyAccess::Restricted {
                include_platform_defaults: true,
                readable_roots: Vec::new(),
            },
            network_access: true,
        })),
        Some("workspace-write") => {
            let writable_roots = cwd
                .into_iter()
                .map(|path| AbsolutePathBuf::try_from(path.to_path_buf()))
                .collect::<std::result::Result<Vec<_>, _>>()
                .map_err(anyhow::Error::from)?;
            Ok(Some(SandboxPolicy::WorkspaceWrite {
                writable_roots,
                read_only_access: codex_app_server_protocol::ReadOnlyAccess::Restricted {
                    include_platform_defaults: true,
                    readable_roots: Vec::new(),
                },
                network_access: true,
                exclude_tmpdir_env_var: false,
                exclude_slash_tmp: false,
            }))
        }
        Some(other) => anyhow::bail!("unsupported sandbox mode: {other}"),
    }
}

async fn process_pending_events(target_turn_id: Option<&str>) -> Result<()> {
    process_pending_events_with_idle_timeout(target_turn_id, Duration::from_millis(50)).await
}

async fn process_pending_events_with_idle_timeout(
    target_turn_id: Option<&str>,
    idle_timeout: Duration,
) -> Result<()> {
    loop {
        let mut client = with_native_state(|state| state.client.take())
            .context("remote app-server client is not initialized")?;
        let event = tokio::time::timeout(idle_timeout, client.next_event())
            .await
            .ok()
            .flatten();
        let should_stop = event.is_none();
        if let Some(app_event) = event {
            handle_app_server_event(&mut client, app_event, target_turn_id).await?;
        }
        with_native_state(|state| {
            state.client = Some(client);
        });
        if should_stop {
            break;
        }
    }
    Ok(())
}

fn should_wait_for_trailing_turn_diff(turn_id: &str) -> bool {
    if turn_id.is_empty() {
        return false;
    }
    with_native_state(|state| {
        state
            .turns
            .get(turn_id)
            .map(|turn| {
                turn.diff.trim().is_empty()
                    && matches!(turn.status.as_str(), "completed" | "failed" | "cancelled")
            })
            .unwrap_or(false)
    })
}

async fn handle_app_server_event(
    client: &mut RemoteAppServerClient,
    event: AppServerEvent,
    target_turn_id: Option<&str>,
) -> Result<()> {
    match event {
        AppServerEvent::ServerNotification(notification) => {
            apply_server_notification(&notification, target_turn_id);
            Ok(())
        }
        AppServerEvent::ServerRequest(request) => handle_server_request(client, request).await,
        AppServerEvent::Lagged { skipped } => {
            set_host_message(format!(
                "app-server event stream lagged; skipped {skipped} events"
            ));
            Ok(())
        }
        AppServerEvent::Disconnected { message } => Err(anyhow::anyhow!(
            "embedded websocket app-server disconnected: {message}"
        )),
    }
}

async fn handle_server_request(
    client: &mut RemoteAppServerClient,
    request: ServerRequest,
) -> Result<()> {
    match request {
        ServerRequest::CommandExecutionRequestApproval { request_id, params } => {
            let request_id_json = request_id_to_json_value(&request_id);
            let title = if let Some(command) = params.command.as_deref() {
                format!("需要批准执行命令: {command}")
            } else {
                "需要批准执行命令".to_string()
            };
            let detail = serde_json::json!({
                "reason": params.reason,
                "cwd": params.cwd,
                "command": params.command,
                "availableDecisions": params.available_decisions,
            })
            .to_string();
            with_native_state(|state| {
                set_pending_approval(
                    state,
                    PendingApprovalState {
                        request_id,
                        resolution_kind: PendingApprovalResolutionKind::CommandExecution,
                        payload_json: serde_json::json!({
                            "requestId": request_id_json,
                            "kind": "command",
                            "title": title,
                            "detail": detail,
                            "threadId": params.thread_id,
                            "turnId": params.turn_id,
                            "itemId": params.item_id,
                        })
                        .to_string(),
                    },
                );
            });
            Ok(())
        }
        ServerRequest::FileChangeRequestApproval { request_id, params } => {
            let request_id_json = request_id_to_json_value(&request_id);
            let detail = serde_json::json!({
                "reason": params.reason,
                "grantRoot": params.grant_root,
            })
            .to_string();
            with_native_state(|state| {
                set_pending_approval(
                    state,
                    PendingApprovalState {
                        request_id,
                        resolution_kind: PendingApprovalResolutionKind::FileChange,
                        payload_json: serde_json::json!({
                            "requestId": request_id_json,
                            "kind": "fileChange",
                            "title": "需要批准文件修改",
                            "detail": detail,
                            "threadId": params.thread_id,
                            "turnId": params.turn_id,
                            "itemId": params.item_id,
                        })
                        .to_string(),
                    },
                );
            });
            Ok(())
        }
        ServerRequest::PermissionsRequestApproval { request_id, params } => {
            let request_id_json = request_id_to_json_value(&request_id);
            let detail = serde_json::json!({
                "reason": params.reason,
                "permissions": params.permissions,
            })
            .to_string();
            with_native_state(|state| {
                set_pending_approval(
                    state,
                    PendingApprovalState {
                        request_id,
                        resolution_kind: PendingApprovalResolutionKind::Permissions,
                        payload_json: serde_json::json!({
                            "requestId": request_id_json,
                            "kind": "permissions",
                            "title": "需要批准权限申请",
                            "detail": detail,
                            "threadId": params.thread_id,
                            "turnId": params.turn_id,
                            "itemId": params.item_id,
                        })
                        .to_string(),
                    },
                );
            });
            Ok(())
        }
        ServerRequest::ApplyPatchApproval { request_id, params } => {
            let request_id_json = request_id_to_json_value(&request_id);
            let detail = serde_json::json!({
                "reason": params.reason,
                "grantRoot": params.grant_root,
                "fileChanges": params.file_changes,
            })
            .to_string();
            with_native_state(|state| {
                set_pending_approval(
                    state,
                    PendingApprovalState {
                        request_id,
                        resolution_kind: PendingApprovalResolutionKind::LegacyPatch,
                        payload_json: serde_json::json!({
                            "requestId": request_id_json,
                            "kind": "fileChange",
                            "title": "需要批准补丁修改",
                            "detail": detail,
                            "threadId": params.conversation_id.to_string(),
                            "turnId": "",
                            "itemId": params.call_id,
                        })
                        .to_string(),
                    },
                );
            });
            Ok(())
        }
        ServerRequest::ExecCommandApproval { request_id, params } => {
            let request_id_json = request_id_to_json_value(&request_id);
            let detail = serde_json::json!({
                "reason": params.reason,
                "cwd": params.cwd,
                "command": params.command,
            })
            .to_string();
            with_native_state(|state| {
                set_pending_approval(
                    state,
                    PendingApprovalState {
                        request_id,
                        resolution_kind: PendingApprovalResolutionKind::LegacyExec,
                        payload_json: serde_json::json!({
                            "requestId": request_id_json,
                            "kind": "command",
                            "title": "需要批准执行命令",
                            "detail": detail,
                            "threadId": params.conversation_id.to_string(),
                            "turnId": "",
                            "itemId": params.call_id,
                        })
                        .to_string(),
                    },
                );
            });
            Ok(())
        }
        ServerRequest::ToolRequestUserInput { request_id, params } => {
            client
                .reject_server_request(
                    request_id,
                    codex_app_server_protocol::JSONRPCErrorError {
                        code: -32601,
                        data: None,
                        message: format!(
                            "tool/requestUserInput is not supported in Harmony UI yet for turn `{}`",
                            params.turn_id
                        ),
                    },
                )
                .await
                .map_err(anyhow::Error::from)
        }
        ServerRequest::McpServerElicitationRequest { request_id, params } => {
            client
                .reject_server_request(
                    request_id,
                    codex_app_server_protocol::JSONRPCErrorError {
                        code: -32601,
                        data: None,
                        message: format!(
                            "mcpServer/elicitation/request is not supported in Harmony UI yet for server `{}`",
                            params.server_name
                        ),
                    },
                )
                .await
                .map_err(anyhow::Error::from)
        }
        ServerRequest::DynamicToolCall { request_id, .. } => {
            client
                .reject_server_request(
                    request_id,
                    codex_app_server_protocol::JSONRPCErrorError {
                        code: -32601,
                        data: None,
                        message: "dynamic tool calls are not supported in Harmony UI yet".to_string(),
                    },
                )
                .await
                .map_err(anyhow::Error::from)
        }
        ServerRequest::ChatgptAuthTokensRefresh { request_id, .. } => {
            client
                .resolve_server_request(request_id, serde_json::json!({}))
                .await
                .map_err(anyhow::Error::from)
        }
    }
}

fn apply_server_notification(notification: &ServerNotification, _target_turn_id: Option<&str>) {
    match notification {
        ServerNotification::TurnStarted(payload) => {
            with_native_state(|state| {
                let entry = state
                    .turns
                    .entry(payload.turn.id.clone())
                    .or_insert_with(NativeTurnState::default);
                entry.thread_id = payload.thread_id.clone();
                entry.status = map_turn_status(&payload.turn.status).to_string();
                if entry.cwd.is_none() {
                    entry.cwd = state
                        .threads
                        .get(&payload.thread_id)
                        .and_then(|thread| thread.cwd.clone());
                }
                if entry.local_diff_tracker.is_none() {
                    entry.local_diff_tracker = build_local_turn_diff_tracker(entry.cwd.as_deref());
                }
                if entry.summary_title.is_empty() {
                    entry.summary_title = "执行中".to_string();
                }
                if entry.summary.is_empty() {
                    entry.summary.push("Codex 正在处理请求。".to_string());
                }
            });
        }
        ServerNotification::ItemStarted(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "执行中".to_string();
                push_turn_summary(turn, describe_started_item(&payload.item));
                upsert_item_started_message(
                    state,
                    &payload.thread_id,
                    &payload.turn_id,
                    &payload.item,
                );
            });
        }
        ServerNotification::AgentMessageDelta(payload) => {
            with_native_state(|state| {
                {
                    let turn = state
                        .turns
                        .entry(payload.turn_id.clone())
                        .or_insert_with(|| NativeTurnState {
                            thread_id: payload.thread_id.clone(),
                            status: "inProgress".to_string(),
                            ..Default::default()
                        });
                    turn.status = "inProgress".to_string();
                    turn.summary_title = "执行中".to_string();
                    push_turn_summary(turn, "Codex 正在生成回复。".to_string());
                }
                append_assistant_delta(
                    state,
                    &payload.thread_id,
                    &payload.turn_id,
                    &payload.item_id,
                    &payload.delta,
                );
            });
        }
        ServerNotification::PlanDelta(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "计划中".to_string();
                push_turn_summary(turn, format!("计划: {}", compact_text(&payload.delta, 160)));
            });
        }
        ServerNotification::ReasoningSummaryTextDelta(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "推理中".to_string();
                push_turn_summary(turn, format!("推理摘要: {}", compact_text(&payload.delta, 160)));
                append_reasoning_delta(state, &payload.thread_id, &payload.turn_id, &payload.item_id, &payload.delta);
            });
        }
        ServerNotification::ReasoningTextDelta(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "推理中".to_string();
                push_turn_summary(turn, format!("推理: {}", compact_text(&payload.delta, 160)));
                append_reasoning_delta(state, &payload.thread_id, &payload.turn_id, &payload.item_id, &payload.delta);
            });
        }
        ServerNotification::CommandExecutionOutputDelta(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "执行工具中".to_string();
                push_turn_summary(
                    turn,
                    format!("命令输出: {}", compact_text(&payload.delta, 160)),
                );
            });
        }
        ServerNotification::FileChangeOutputDelta(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "更改文件中".to_string();
                push_turn_summary(
                    turn,
                    format!("文件变更: {}", compact_text(&payload.delta, 160)),
                );
            });
        }
        ServerNotification::McpToolCallProgress(payload) => {
            with_native_state(|state| {
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                turn.status = "inProgress".to_string();
                turn.summary_title = "执行工具中".to_string();
                push_turn_summary(
                    turn,
                    format!("工具进度: {}", compact_text(&payload.message, 160)),
                );
            });
        }
        ServerNotification::ItemCompleted(payload) => {
            with_native_state(|state| {
                sync_thread_from_completed_item(
                    state,
                    &payload.thread_id,
                    &payload.turn_id,
                    &payload.item,
                );
                let turn = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        status: "inProgress".to_string(),
                        ..Default::default()
                    });
                if let Some(summary) = describe_completed_item(&payload.item) {
                    push_turn_summary(turn, summary);
                }
                if let Some(diff) = diff_from_thread_item(&payload.item) {
                    append_turn_diff(turn, &diff);
                    turn.diff_authoritative = true;
                }
                upsert_item_completed_message(
                    state,
                    &payload.thread_id,
                    &payload.turn_id,
                    &payload.item,
                );
            });
        }
        ServerNotification::TurnCompleted(payload) => {
            with_native_state(|state| {
                let entry = state
                    .turns
                    .entry(payload.turn.id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        ..Default::default()
                    });
                entry.status = map_turn_status(&payload.turn.status).to_string();
                entry.error_message = payload
                    .turn
                    .error
                    .as_ref()
                    .map(|err| err.message.clone())
                    .unwrap_or_default();
                entry.summary_title = if entry.status == "completed" {
                    "本轮已完成".to_string()
                } else if entry.status == "failed" {
                    "本轮失败".to_string()
                } else {
                    "本轮已结束".to_string()
                };
                if entry.error_message.is_empty() {
                    push_turn_summary(entry, "本轮对话已完成。".to_string());
                } else {
                    entry.summary = vec![entry.error_message.clone()];
                }
            });
        }
        ServerNotification::TurnDiffUpdated(payload) => {
            with_native_state(|state| {
                let entry = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        ..Default::default()
                    });
                entry.diff = payload.diff.clone();
                entry.diff_authoritative = true;
            });
        }
        ServerNotification::Error(payload) => {
            with_native_state(|state| {
                let entry = state
                    .turns
                    .entry(payload.turn_id.clone())
                    .or_insert_with(|| NativeTurnState {
                        thread_id: payload.thread_id.clone(),
                        ..Default::default()
                    });
                entry.status = "failed".to_string();
                entry.error_message = payload.error.message.clone();
                entry.summary_title = "本轮失败".to_string();
                entry.summary = vec![payload.error.message.clone()];
            });
        }
        _ => {}
    }
}

fn request_id_to_json_value(request_id: &RequestId) -> serde_json::Value {
    match request_id {
        RequestId::Integer(value) => serde_json::json!(*value),
        RequestId::String(value) => serde_json::json!(value),
    }
}

fn parse_request_id_value(value: &serde_json::Value) -> Option<RequestId> {
    if let Some(raw) = value.as_i64() {
        return Some(RequestId::Integer(raw));
    }
    value.as_str().map(|raw| RequestId::String(raw.to_string()))
}

fn resolve_pending_approval(params_json: *const c_char, approved: bool) -> i32 {
    let params_text = ffi_string(params_json).unwrap_or_else(|| "{}".to_string());
    let request =
        serde_json::from_str::<NativeApprovalActionRequest>(&params_text).unwrap_or_default();
    let request_id_from_payload = parse_request_id_value(&request.request_id);
    let result = with_runtime_result(async move {
        let (mut client, pending) = with_native_state(|state| {
            let client = state.client.take();
            let pending = state.pending_approval.clone();
            if pending.is_none() {
                state.pending_approval = None;
            }
            (client, pending)
        });
        let mut client = client.context("remote app-server client is not initialized")?;
        let pending = pending.context("no pending approval request")?;
        if let Some(request_id) = request_id_from_payload {
            if request_id != pending.request_id {
                with_native_state(|state| {
                    state.client = Some(client);
                });
                anyhow::bail!("approval request id does not match current pending approval");
            }
        }
        let response = match pending.resolution_kind {
            PendingApprovalResolutionKind::CommandExecution => {
                let decision = if approved {
                    CommandExecutionApprovalDecision::Accept
                } else {
                    CommandExecutionApprovalDecision::Decline
                };
                serde_json::to_value(CommandExecutionRequestApprovalResponse { decision })?
            }
            PendingApprovalResolutionKind::FileChange => {
                let decision = if approved {
                    FileChangeApprovalDecision::Accept
                } else {
                    FileChangeApprovalDecision::Decline
                };
                serde_json::to_value(FileChangeRequestApprovalResponse { decision })?
            }
            PendingApprovalResolutionKind::Permissions => {
                let permissions = if approved {
                    GrantedPermissionProfile {
                        network: None,
                        file_system: None,
                    }
                } else {
                    GrantedPermissionProfile::default()
                };
                serde_json::to_value(PermissionsRequestApprovalResponse {
                    permissions,
                    scope: PermissionGrantScope::Turn,
                })?
            }
            PendingApprovalResolutionKind::LegacyPatch => {
                let decision = if approved {
                    codex_protocol::protocol::ReviewDecision::Approved
                } else {
                    codex_protocol::protocol::ReviewDecision::Denied
                };
                serde_json::to_value(ApplyPatchApprovalResponse { decision })?
            }
            PendingApprovalResolutionKind::LegacyExec => {
                let decision = if approved {
                    codex_protocol::protocol::ReviewDecision::Approved
                } else {
                    codex_protocol::protocol::ReviewDecision::Denied
                };
                serde_json::to_value(codex_app_server_protocol::ExecCommandApprovalResponse {
                    decision,
                })?
            }
        };
        client
            .resolve_server_request(pending.request_id.clone(), response)
            .await
            .map_err(anyhow::Error::from)?;
        with_native_state(|state| {
            state.client = Some(client);
            state.pending_approval = None;
        });
        clear_pending_approval();
        Ok::<(), anyhow::Error>(())
    });
    if let Err(err) = result {
        set_host_message(format!("approval resolution failed: {err}"));
        return -1;
    }
    0
}

fn push_turn_summary(turn: &mut NativeTurnState, line: String) {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return;
    }
    if turn
        .summary
        .last()
        .map(|last| last == trimmed)
        .unwrap_or(false)
    {
        return;
    }
    turn.summary.push(trimmed.to_string());
    const MAX_SUMMARY_LINES: usize = 12;
    if turn.summary.len() > MAX_SUMMARY_LINES {
        let drain_count = turn.summary.len() - MAX_SUMMARY_LINES;
        turn.summary.drain(0..drain_count);
    }
}

fn compact_text(value: &str, limit: usize) -> String {
    let compact = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= limit {
        return compact;
    }
    let mut truncated = compact.chars().take(limit).collect::<String>();
    truncated.push('…');
    truncated
}

fn describe_started_item(item: &codex_app_server_protocol::ThreadItem) -> String {
    match item {
        codex_app_server_protocol::ThreadItem::Plan { .. } => "开始生成计划。".to_string(),
        codex_app_server_protocol::ThreadItem::Reasoning { .. } => "开始推理。".to_string(),
        codex_app_server_protocol::ThreadItem::CommandExecution { command, cwd, .. } => {
            format!(
                "开始执行命令: {} (cwd: {})",
                compact_text(command, 120),
                cwd.display()
            )
        }
        codex_app_server_protocol::ThreadItem::FileChange { changes, .. } => {
            format!("开始应用文件变更，共 {} 处。", changes.len())
        }
        codex_app_server_protocol::ThreadItem::McpToolCall { server, tool, .. } => {
            format!("开始调用 MCP 工具: {} / {}", server, tool)
        }
        codex_app_server_protocol::ThreadItem::DynamicToolCall { tool, .. } => {
            format!("开始调用动态工具: {}", tool)
        }
        codex_app_server_protocol::ThreadItem::CollabAgentToolCall { tool, .. } => {
            format!("开始协作工具调用: {:?}", tool)
        }
        codex_app_server_protocol::ThreadItem::WebSearch { query, .. } => {
            format!("开始网络搜索: {}", compact_text(query, 120))
        }
        codex_app_server_protocol::ThreadItem::ImageView { path, .. } => {
            format!("正在查看图像: {}", path)
        }
        codex_app_server_protocol::ThreadItem::ImageGeneration { .. } => {
            "开始生成图像。".to_string()
        }
        codex_app_server_protocol::ThreadItem::EnteredReviewMode { review, .. } => {
            format!("进入审查模式: {}", review)
        }
        codex_app_server_protocol::ThreadItem::ExitedReviewMode { review, .. } => {
            format!("退出审查模式: {}", review)
        }
        codex_app_server_protocol::ThreadItem::ContextCompaction { .. } => {
            "开始压缩上下文。".to_string()
        }
        codex_app_server_protocol::ThreadItem::AgentMessage { .. }
        | codex_app_server_protocol::ThreadItem::UserMessage { .. }
        | codex_app_server_protocol::ThreadItem::HookPrompt { .. } => "更新对话内容。".to_string(),
    }
}

fn describe_completed_item(item: &codex_app_server_protocol::ThreadItem) -> Option<String> {
    match item {
        codex_app_server_protocol::ThreadItem::Plan { text, .. } => {
            Some(format!("计划已生成: {}", compact_text(text, 160)))
        }
        codex_app_server_protocol::ThreadItem::Reasoning {
            summary, content, ..
        } => {
            let source = if !summary.is_empty() {
                summary.join(" ")
            } else {
                content.join(" ")
            };
            Some(format!("推理完成: {}", compact_text(&source, 160)))
        }
        codex_app_server_protocol::ThreadItem::CommandExecution {
            command,
            status,
            exit_code,
            aggregated_output,
            ..
        } => {
            let status_text = match status {
                codex_app_server_protocol::CommandExecutionStatus::InProgress => "进行中",
                codex_app_server_protocol::CommandExecutionStatus::Completed => "已完成",
                codex_app_server_protocol::CommandExecutionStatus::Failed => "失败",
                codex_app_server_protocol::CommandExecutionStatus::Declined => "已拒绝",
            };
            let mut message = format!("命令{}: {}", status_text, compact_text(command, 120));
            if let Some(code) = exit_code {
                message.push_str(&format!(" (exit={code})"));
            }
            if let Some(output) = aggregated_output {
                if !output.trim().is_empty() {
                    message.push_str(&format!(" | {}", compact_text(output, 120)));
                }
            }
            Some(message)
        }
        codex_app_server_protocol::ThreadItem::FileChange {
            changes, status, ..
        } => {
            let status_text = match status {
                codex_app_server_protocol::PatchApplyStatus::InProgress => "进行中",
                codex_app_server_protocol::PatchApplyStatus::Completed => "已完成",
                codex_app_server_protocol::PatchApplyStatus::Failed => "失败",
                codex_app_server_protocol::PatchApplyStatus::Declined => "已拒绝",
            };
            Some(format!(
                "文件变更{}，共 {} 处。",
                status_text,
                changes.len()
            ))
        }
        codex_app_server_protocol::ThreadItem::McpToolCall {
            server,
            tool,
            status,
            error,
            ..
        } => {
            let status_text = match status {
                codex_app_server_protocol::McpToolCallStatus::InProgress => "进行中",
                codex_app_server_protocol::McpToolCallStatus::Completed => "已完成",
                codex_app_server_protocol::McpToolCallStatus::Failed => "失败",
            };
            let mut message = format!("MCP 工具 {} / {} {}", server, tool, status_text);
            if let Some(err) = error {
                message.push_str(&format!(": {}", compact_text(&err.message, 120)));
            }
            Some(message)
        }
        codex_app_server_protocol::ThreadItem::DynamicToolCall { tool, status, .. } => {
            let status_text = match status {
                codex_app_server_protocol::DynamicToolCallStatus::InProgress => "进行中",
                codex_app_server_protocol::DynamicToolCallStatus::Completed => "已完成",
                codex_app_server_protocol::DynamicToolCallStatus::Failed => "失败",
            };
            Some(format!("动态工具 {} {}", tool, status_text))
        }
        codex_app_server_protocol::ThreadItem::CollabAgentToolCall { tool, status, .. } => {
            let status_text = match status {
                codex_app_server_protocol::CollabAgentToolCallStatus::InProgress => "进行中",
                codex_app_server_protocol::CollabAgentToolCallStatus::Completed => "已完成",
                codex_app_server_protocol::CollabAgentToolCallStatus::Failed => "失败",
            };
            Some(format!("协作工具 {:?} {}", tool, status_text))
        }
        codex_app_server_protocol::ThreadItem::WebSearch { query, .. } => {
            Some(format!("网络搜索完成: {}", compact_text(query, 120)))
        }
        codex_app_server_protocol::ThreadItem::ImageView { path, .. } => {
            Some(format!("图像已加载: {}", path))
        }
        codex_app_server_protocol::ThreadItem::ImageGeneration {
            status,
            revised_prompt,
            saved_path,
            ..
        } => {
            let mut message = format!("图像生成状态: {}", status);
            if let Some(prompt) = revised_prompt {
                if !prompt.trim().is_empty() {
                    message.push_str(&format!(" | prompt: {}", compact_text(prompt, 120)));
                }
            }
            if let Some(path) = saved_path {
                message.push_str(&format!(" | saved: {}", path));
            }
            Some(message)
        }
        codex_app_server_protocol::ThreadItem::EnteredReviewMode { review, .. } => {
            Some(format!("已进入审查模式: {}", review))
        }
        codex_app_server_protocol::ThreadItem::ExitedReviewMode { review, .. } => {
            Some(format!("已退出审查模式: {}", review))
        }
        codex_app_server_protocol::ThreadItem::ContextCompaction { .. } => {
            Some("上下文压缩已完成。".to_string())
        }
        codex_app_server_protocol::ThreadItem::AgentMessage { .. }
        | codex_app_server_protocol::ThreadItem::UserMessage { .. }
        | codex_app_server_protocol::ThreadItem::HookPrompt { .. } => None,
    }
}

fn append_assistant_delta(
    state: &mut NativeConversationState,
    thread_id: &str,
    turn_id: &str,
    item_id: &str,
    delta: &str,
) {
    let thread_messages = {
        let thread = state
            .threads
            .entry(thread_id.to_string())
            .or_insert_with(|| NativeThreadState {
                remote_thread_id: thread_id.to_string(),
                cwd: None,
                messages: Vec::new(),
            });
        let target_message_id = format!("{turn_id}:{item_id}");
        if let Some(message) = thread
            .messages
            .iter_mut()
            .find(|message| message.message_id == target_message_id)
        {
            message.content.push_str(delta);
        } else {
            thread.messages.push(NativeMessage {
                message_id: target_message_id,
                author: "Codex".to_string(),
                role: "assistant".to_string(),
                content: delta.to_string(),
                timestamp: current_timestamp_string(),
                item_type: None,
                status: None,
                metadata: None,
            });
        }
        thread.messages.clone()
    };

    if let Some(turn) = state.turns.get_mut(turn_id) {
        turn.messages = thread_messages;
    }
}

fn append_reasoning_delta(
    state: &mut NativeConversationState,
    thread_id: &str,
    turn_id: &str,
    item_id: &str,
    delta: &str,
) {
    let thread_messages = {
        let thread = state
            .threads
            .entry(thread_id.to_string())
            .or_insert_with(|| NativeThreadState {
                remote_thread_id: thread_id.to_string(),
                cwd: None,
                messages: Vec::new(),
            });
        let target_message_id = format!("{turn_id}:{item_id}");
        if let Some(message) = thread
            .messages
            .iter_mut()
            .find(|message| message.message_id == target_message_id)
        {
            // 如果消息已存在，追加增量内容
            message.content.push_str(delta);
        } else {
            // 如果消息不存在，创建新的推理消息
            thread.messages.push(NativeMessage {
                message_id: target_message_id,
                author: "思考过程".to_string(),
                role: "reasoning".to_string(),
                content: delta.to_string(),
                timestamp: current_timestamp_string(),
                item_type: Some("reasoning".to_string()),
                status: Some("inProgress".to_string()),
                metadata: None,
            });
        }
        thread.messages.clone()
    };

    if let Some(turn) = state.turns.get_mut(turn_id) {
        turn.messages = thread_messages;
    }
}

fn sync_thread_from_completed_item(
    state: &mut NativeConversationState,
    thread_id: &str,
    turn_id: &str,
    item: &codex_app_server_protocol::ThreadItem,
) {
    if let codex_app_server_protocol::ThreadItem::AgentMessage { id, text, .. } = item {
        let thread_messages = {
            let thread = state
                .threads
                .entry(thread_id.to_string())
                .or_insert_with(|| NativeThreadState {
                    remote_thread_id: thread_id.to_string(),
                    cwd: None,
                    messages: Vec::new(),
                });
            let message_id = format!("{turn_id}:{id}");
            if let Some(message) = thread
                .messages
                .iter_mut()
                .find(|message| message.message_id == message_id)
            {
                message.content = text.clone();
            } else {
                thread.messages.push(NativeMessage {
                    message_id,
                    author: "Codex".to_string(),
                    role: "assistant".to_string(),
                    content: text.clone(),
                    timestamp: current_timestamp_string(),
                    item_type: None,
                    status: None,
                    metadata: None,
                });
            }
            thread.messages.clone()
        };
        if let Some(turn) = state.turns.get_mut(turn_id) {
            turn.messages = thread_messages;
        }
    }
}

fn append_turn_diff(turn: &mut NativeTurnState, diff: &str) {
    let chunk = diff.trim();
    if chunk.is_empty() {
        return;
    }
    if turn.diff.trim().is_empty() {
        turn.diff = chunk.to_string();
        return;
    }
    turn.diff = merge_unified_diff(&turn.diff, chunk);
}

fn extract_diff_section_path(section: &str) -> Option<String> {
    for line in section.lines() {
        if let Some(rest) = line.strip_prefix("diff --git ") {
            if let Some(index) = rest.rfind(" b/") {
                let path = rest[index + 3..].trim();
                if !path.is_empty() {
                    return Some(path.to_string());
                }
            }
        }
        if let Some(path) = line.strip_prefix("+++ b/") {
            let normalized = path.trim();
            if !normalized.is_empty() {
                return Some(normalized.to_string());
            }
        }
    }
    None
}

fn split_unified_diff_sections(diff: &str) -> Vec<(Option<String>, String)> {
    let trimmed = diff.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }

    let mut sections: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut saw_structured_header = false;

    for line in trimmed.lines() {
        if line.starts_with("diff --git ") {
            saw_structured_header = true;
            if !current.trim().is_empty() {
                sections.push(current.trim().to_string());
                current.clear();
            }
        }
        if !current.is_empty() {
            current.push('\n');
        }
        current.push_str(line);
    }

    if !current.trim().is_empty() {
        sections.push(current.trim().to_string());
    }

    if !saw_structured_header {
        return vec![(extract_diff_section_path(trimmed), trimmed.to_string())];
    }

    sections
        .into_iter()
        .map(|section| {
            let path = extract_diff_section_path(&section);
            (path, section)
        })
        .collect()
}

fn merge_unified_diff(existing: &str, incoming: &str) -> String {
    let existing_sections = split_unified_diff_sections(existing);
    let incoming_sections = split_unified_diff_sections(incoming);

    if existing_sections.is_empty() {
        return incoming.trim().to_string();
    }
    if incoming_sections.is_empty() {
        return existing.trim().to_string();
    }

    let mut merged = existing_sections;
    for (incoming_path, incoming_section) in incoming_sections {
        let incoming_trimmed = incoming_section.trim();
        if incoming_trimmed.is_empty() {
            continue;
        }

        let mut handled = false;
        if let Some(path) = incoming_path.as_ref() {
            let matching_indexes = merged
                .iter()
                .enumerate()
                .filter_map(|(index, (existing_path, _))| {
                    if existing_path.as_ref() == Some(path) {
                        Some(index)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();

            for index in matching_indexes {
                let existing_trimmed = merged[index].1.trim();
                if existing_trimmed == incoming_trimmed
                    || existing_trimmed.contains(incoming_trimmed)
                {
                    handled = true;
                    break;
                }
                if incoming_trimmed.contains(existing_trimmed)
                    || incoming_section.lines().count() >= merged[index].1.lines().count()
                {
                    merged[index] = (incoming_path.clone(), incoming_section.clone());
                    handled = true;
                    break;
                }
                handled = true;
            }
        } else if merged
            .iter()
            .any(|(_, existing_section)| existing_section.trim() == incoming_trimmed)
        {
            handled = true;
        }

        if !handled
            && !merged
                .iter()
                .any(|(_, existing_section)| existing_section.trim() == incoming_trimmed)
        {
            merged.push((incoming_path.clone(), incoming_section));
        }
    }

    merged
        .into_iter()
        .map(|(_, section)| section)
        .collect::<Vec<_>>()
        .join("\n")
}

fn diff_from_thread_item(item: &codex_app_server_protocol::ThreadItem) -> Option<String> {
    match item {
        codex_app_server_protocol::ThreadItem::FileChange { changes, .. } => {
            let chunks = changes
                .iter()
                .filter_map(|change| {
                    let diff = change.diff.trim();
                    if diff.is_empty() {
                        None
                    } else {
                        Some(diff.to_string())
                    }
                })
                .collect::<Vec<_>>();
            if chunks.is_empty() {
                None
            } else {
                Some(chunks.join("\n"))
            }
        }
        _ => None,
    }
}

fn build_turn_poll_payload(
    state: &NativeConversationState,
    thread_id: &str,
    turn_id: &str,
) -> serde_json::Value {
    let turn = state.turns.get(turn_id).cloned().unwrap_or_default();
    let effective_thread_id = if thread_id.is_empty() {
        turn.thread_id.clone()
    } else {
        thread_id.to_string()
    };
    let thread_messages = state
        .threads
        .get(&effective_thread_id)
        .map(|thread| thread.messages.clone())
        .unwrap_or_else(|| turn.messages.clone());
    let status = if turn.status.is_empty() {
        "inProgress".to_string()
    } else {
        turn.status.clone()
    };
    let summary_title = if turn.summary_title.is_empty() {
        "执行中".to_string()
    } else {
        turn.summary_title.clone()
    };
    serde_json::json!({
        "threadId": effective_thread_id,
        "turnId": turn_id,
        "status": status,
        "messages": thread_messages,
        "summaryTitle": summary_title,
        "summary": if turn.summary.is_empty() { vec!["等待更多事件。".to_string()] } else { turn.summary },
        "diff": turn.diff,
    })
}

fn upsert_thread_state_from_protocol(
    state: &mut NativeConversationState,
    thread: &Thread,
    refresh_messages: bool,
) {
    let entry = state
        .threads
        .entry(thread.id.clone())
        .or_insert_with(|| NativeThreadState {
            remote_thread_id: thread.id.clone(),
            cwd: Some(thread.cwd.clone()),
            messages: Vec::new(),
        });
    entry.remote_thread_id = thread.id.clone();
    entry.cwd = Some(thread.cwd.clone());
    if refresh_messages {
        entry.messages = collect_thread_messages(&thread.turns);
    }
}

fn build_thread_meta_payload(thread: &Thread) -> serde_json::Value {
    serde_json::json!({
        "id": thread.id.clone(),
        "title": thread_title(thread),
        "name": thread.name.clone(),
        "preview": thread.preview.clone(),
        "cwd": thread.cwd.display().to_string(),
        "createdAt": thread.created_at,
        "updatedAt": thread.updated_at,
        "path": thread.path.as_ref().map(|path| path.display().to_string()),
        "modelProvider": thread.model_provider.clone(),
        "ephemeral": thread.ephemeral,
        "status": serde_json::to_value(&thread.status).unwrap_or(serde_json::Value::Null),
        "statusText": thread_status_text(&thread.status),
    })
}

fn build_thread_list_payload(response: &ThreadListResponse) -> serde_json::Value {
    let data = response
        .data
        .iter()
        .map(build_thread_meta_payload)
        .collect::<Vec<_>>();
    serde_json::json!({
        "data": data,
        "nextCursor": response.next_cursor.clone(),
    })
}

fn build_thread_read_payload(thread: &Thread) -> serde_json::Value {
    let (summary_title, summary_points, last_turn_id, last_turn_status) =
        collect_thread_summary_from_turns(&thread.turns);
    let diff = collect_thread_diff_from_turns(&thread.turns);
    let changed_files = collect_thread_changed_files(&thread.turns);
    let changed_files_text = if changed_files.is_empty() {
        "尚未产生文件改动".to_string()
    } else {
        changed_files.join("、")
    };

    serde_json::json!({
        "thread": build_thread_meta_payload(thread),
        "messages": collect_thread_messages(&thread.turns),
        "summaryTitle": summary_title,
        "summary": summary_points,
        "changedFiles": changed_files,
        "changedFilesText": changed_files_text,
        "diff": diff,
        "diffStat": diff_stat_from_unified_diff(&diff),
        "lastTurnId": last_turn_id,
        "lastTurnStatus": last_turn_status,
    })
}

fn collect_thread_summary_from_turns(
    turns: &[codex_app_server_protocol::Turn],
) -> (String, Vec<String>, String, String) {
    let mut summary: Vec<String> = Vec::new();
    for turn in turns.iter().rev() {
        for item in turn.items.iter().rev() {
            if let Some(line) = describe_completed_item(item) {
                if !line.trim().is_empty() {
                    summary.push(line);
                }
            }
            if summary.len() >= 6 {
                break;
            }
        }
        if summary.len() >= 6 {
            break;
        }
    }
    summary.reverse();

    let (last_turn_id, last_turn_status, summary_title) = if let Some(turn) = turns.last() {
        let status_text = map_turn_status(&turn.status).to_string();
        let title = match turn.status {
            TurnStatus::Completed => "会话已恢复",
            TurnStatus::Failed => "会话最后一轮失败",
            TurnStatus::Interrupted => "会话最后一轮已中断",
            TurnStatus::InProgress => "会话仍在执行中",
        }
        .to_string();
        (turn.id.clone(), status_text, title)
    } else {
        (
            String::new(),
            "completed".to_string(),
            "会话已恢复".to_string(),
        )
    };

    if summary.is_empty() {
        summary.push("历史会话已从 app-server rollout 恢复。".to_string());
    }

    (summary_title, summary, last_turn_id, last_turn_status)
}

fn collect_thread_changed_files(turns: &[codex_app_server_protocol::Turn]) -> Vec<String> {
    let mut files: Vec<String> = Vec::new();
    for turn in turns {
        for item in &turn.items {
            if let codex_app_server_protocol::ThreadItem::FileChange { changes, .. } = item {
                for change in changes {
                    if !change.path.trim().is_empty()
                        && !files.iter().any(|existing| existing == &change.path)
                    {
                        files.push(change.path.clone());
                    }
                }
            }
        }
    }
    files
}

fn collect_thread_diff_from_turns(turns: &[codex_app_server_protocol::Turn]) -> String {
    let mut chunks: Vec<String> = Vec::new();
    for turn in turns {
        for item in &turn.items {
            if let Some(diff) = diff_from_thread_item(item) {
                chunks.push(diff);
            }
        }
    }
    chunks.join("\n")
}

fn diff_stat_from_unified_diff(diff: &str) -> String {
    let mut adds: usize = 0;
    let mut deletes: usize = 0;
    for line in diff.lines() {
        if line.starts_with("+++") || line.starts_with("---") {
            continue;
        }
        if line.starts_with('+') {
            adds += 1;
        } else if line.starts_with('-') {
            deletes += 1;
        }
    }
    format!("+{} -{}", adds, deletes)
}

fn thread_status_text(status: &codex_app_server_protocol::ThreadStatus) -> &'static str {
    match status {
        codex_app_server_protocol::ThreadStatus::NotLoaded => "notLoaded",
        codex_app_server_protocol::ThreadStatus::Idle => "idle",
        codex_app_server_protocol::ThreadStatus::SystemError => "systemError",
        codex_app_server_protocol::ThreadStatus::Active { .. } => "active",
    }
}

fn thread_title(thread: &Thread) -> String {
    if let Some(name) = &thread.name {
        if !name.trim().is_empty() {
            return name.clone();
        }
    }
    if !thread.preview.trim().is_empty() {
        return compact_text(&thread.preview, 80);
    }
    "未命名会话".to_string()
}

fn collect_thread_messages(turns: &[codex_app_server_protocol::Turn]) -> Vec<NativeMessage> {
    let mut messages: Vec<NativeMessage> = Vec::new();
    for turn in turns {
        for item in &turn.items {
            match item {
                codex_app_server_protocol::ThreadItem::UserMessage { id, content } => {
                    let text = content
                        .iter()
                        .filter_map(|input| match input {
                            UserInput::Text { text, .. } => Some(text.clone()),
                            _ => None,
                        })
                        .collect::<Vec<String>>()
                        .join("\n");
                    messages.push(NativeMessage {
                        message_id: id.clone(),
                        author: "你".to_string(),
                        role: "user".to_string(),
                        content: text,
                        timestamp: current_timestamp_string(),
                        item_type: None,
                        status: None,
                        metadata: None,
                    });
                }
                codex_app_server_protocol::ThreadItem::AgentMessage { id, text, .. } => {
                    messages.push(NativeMessage {
                        message_id: id.clone(),
                        author: "Codex".to_string(),
                        role: "assistant".to_string(),
                        content: text.clone(),
                        timestamp: current_timestamp_string(),
                        item_type: Some("agent".to_string()),
                        status: Some("completed".to_string()),
                        metadata: None,
                    });
                }
                item => {
                    if let Some(msg) = thread_item_to_message(item) {
                        messages.push(msg);
                    }
                }
            }
        }
    }
    messages
}

fn thread_item_to_message(item: &codex_app_server_protocol::ThreadItem) -> Option<NativeMessage> {
    match item {
        codex_app_server_protocol::ThreadItem::Plan { id, text } => {
            Some(NativeMessage {
                message_id: id.clone(),
                author: "计划".to_string(),
                role: "plan".to_string(),
                content: text.clone(),
                timestamp: current_timestamp_string(),
                item_type: Some("plan".to_string()),
                status: Some("completed".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::Reasoning { id, summary, content, .. } => {
            let text = if !summary.is_empty() {
                summary.join("\n")
            } else {
                content.join("\n")
            };
            Some(NativeMessage {
                message_id: id.clone(),
                author: "思考过程".to_string(),
                role: "reasoning".to_string(),
                content: text,
                timestamp: current_timestamp_string(),
                item_type: Some("reasoning".to_string()),
                status: Some("completed".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::CommandExecution {
            id,
            command,
            cwd,
            status,
            aggregated_output,
            exit_code,
            duration_ms,
            ..
        } => {
            let status_str = match status {
                codex_app_server_protocol::CommandExecutionStatus::InProgress => "inProgress",
                codex_app_server_protocol::CommandExecutionStatus::Completed => "completed",
                codex_app_server_protocol::CommandExecutionStatus::Failed => "failed",
                codex_app_server_protocol::CommandExecutionStatus::Declined => "declined",
            };
            let mut content_parts = vec![command.clone()];
            if let Some(output) = aggregated_output {
                if !output.trim().is_empty() {
                    content_parts.push("--- 输出 ---".to_string());
                    content_parts.push(output.clone());
                }
            }
            Some(NativeMessage {
                message_id: id.clone(),
                author: "命令执行".to_string(),
                role: "command".to_string(),
                content: content_parts.join("\n"),
                timestamp: current_timestamp_string(),
                item_type: Some("command".to_string()),
                status: Some(status_str.to_string()),
                metadata: Some(serde_json::json!({
                    "command": command,
                    "cwd": cwd.display().to_string(),
                    "exitCode": exit_code,
                    "durationMs": duration_ms,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::FileChange { id, changes, status, .. } => {
            let status_str = match status {
                codex_app_server_protocol::PatchApplyStatus::InProgress => "inProgress",
                codex_app_server_protocol::PatchApplyStatus::Completed => "completed",
                codex_app_server_protocol::PatchApplyStatus::Failed => "failed",
                codex_app_server_protocol::PatchApplyStatus::Declined => "declined",
            };
            let paths: Vec<String> = changes.iter().map(|c| c.path.clone()).collect();
            Some(NativeMessage {
                message_id: id.clone(),
                author: "文件变更".to_string(),
                role: "file".to_string(),
                content: format!("修改了 {} 个文件:\n{}", changes.len(), paths.join("\n")),
                timestamp: current_timestamp_string(),
                item_type: Some("file".to_string()),
                status: Some(status_str.to_string()),
                metadata: Some(serde_json::json!({
                    "files": paths,
                    "changeCount": changes.len(),
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::McpToolCall {
            id,
            server,
            tool,
            status,
            arguments,
            result,
            error,
            duration_ms,
            ..
        } => {
            let status_str = match status {
                codex_app_server_protocol::McpToolCallStatus::InProgress => "inProgress",
                codex_app_server_protocol::McpToolCallStatus::Completed => "completed",
                codex_app_server_protocol::McpToolCallStatus::Failed => "failed",
            };
            let mut content_parts = vec![format!("调用 {}/{}", server, tool)];
            if let Some(err) = error {
                content_parts.push(format!("错误: {}", err.message));
            }
            if let Some(res) = result {
                let result_text: String = res.content
                    .iter()
                    .filter_map(|v| v.as_str())
                    .collect::<Vec<&str>>()
                    .join("\n");
                if !result_text.trim().is_empty() {
                    content_parts.push("--- 结果 ---".to_string());
                    content_parts.push(result_text);
                }
            }
            Some(NativeMessage {
                message_id: id.clone(),
                author: "MCP 工具".to_string(),
                role: "tool".to_string(),
                content: content_parts.join("\n"),
                timestamp: current_timestamp_string(),
                item_type: Some("tool".to_string()),
                status: Some(status_str.to_string()),
                metadata: Some(serde_json::json!({
                    "server": server,
                    "tool": tool,
                    "arguments": arguments,
                    "durationMs": duration_ms,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::WebSearch { id, query, .. } => {
            Some(NativeMessage {
                message_id: id.clone(),
                author: "网络搜索".to_string(),
                role: "search".to_string(),
                content: format!("搜索: {}", query),
                timestamp: current_timestamp_string(),
                item_type: Some("search".to_string()),
                status: Some("completed".to_string()),
                metadata: Some(serde_json::json!({
                    "query": query,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::DynamicToolCall {
            id,
            tool,
            status,
            arguments,
            content_items,
            ..
        } => {
            let status_str = match status {
                codex_app_server_protocol::DynamicToolCallStatus::InProgress => "inProgress",
                codex_app_server_protocol::DynamicToolCallStatus::Completed => "completed",
                codex_app_server_protocol::DynamicToolCallStatus::Failed => "failed",
            };
            let mut content_parts = vec![format!("工具调用: {}", tool)];
            if let Some(items) = content_items {
                for item in items {
                    match item {
                        codex_app_server_protocol::DynamicToolCallOutputContentItem::InputText { text } => {
                            content_parts.push(text.clone());
                        }
                        codex_app_server_protocol::DynamicToolCallOutputContentItem::InputImage { image_url } => {
                            content_parts.push(format!("[图片: {}]", image_url));
                        }
                    }
                }
            }
            Some(NativeMessage {
                message_id: id.clone(),
                author: "动态工具".to_string(),
                role: "tool".to_string(),
                content: content_parts.join("\n"),
                timestamp: current_timestamp_string(),
                item_type: Some("tool".to_string()),
                status: Some(status_str.to_string()),
                metadata: Some(serde_json::json!({
                    "tool": tool,
                    "arguments": arguments,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::ImageGeneration {
            id,
            status,
            revised_prompt,
            saved_path,
            ..
        } => {
            let mut content_parts = vec![format!("图像生成状态: {}", status)];
            if let Some(prompt) = revised_prompt {
                content_parts.push(format!("Prompt: {}", prompt));
            }
            if let Some(path) = saved_path {
                content_parts.push(format!("保存路径: {}", path));
            }
            Some(NativeMessage {
                message_id: id.clone(),
                author: "图像生成".to_string(),
                role: "image".to_string(),
                content: content_parts.join("\n"),
                timestamp: current_timestamp_string(),
                item_type: Some("image".to_string()),
                status: Some(status.clone()),
                metadata: Some(serde_json::json!({
                    "savedPath": saved_path,
                    "revisedPrompt": revised_prompt,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::CollabAgentToolCall {
            id,
            tool,
            status,
            sender_thread_id,
            receiver_thread_ids,
            prompt,
            model,
            reasoning_effort,
            agents_states,
        } => {
            let status_str = match status {
                codex_app_server_protocol::CollabAgentToolCallStatus::InProgress => "inProgress",
                codex_app_server_protocol::CollabAgentToolCallStatus::Completed => "completed",
                codex_app_server_protocol::CollabAgentToolCallStatus::Failed => "failed",
            };
            let tool_name = match tool {
                codex_app_server_protocol::CollabAgentTool::SpawnAgent => "创建子代理",
                codex_app_server_protocol::CollabAgentTool::SendInput => "发送输入",
                codex_app_server_protocol::CollabAgentTool::ResumeAgent => "恢复代理",
                codex_app_server_protocol::CollabAgentTool::Wait => "等待",
                codex_app_server_protocol::CollabAgentTool::CloseAgent => "关闭代理",
            };
            let mut content_parts = vec![format!("协作工具: {}", tool_name)];
            if let Some(p) = prompt {
                if !p.is_empty() {
                    content_parts.push(format!("提示词: {}", p));
                }
            }
            if let Some(m) = model {
                content_parts.push(format!("模型: {}", m));
            }
            if !receiver_thread_ids.is_empty() {
                content_parts.push(format!("接收线程: {}", receiver_thread_ids.join(", ")));
            }
            // 显示各代理的状态
            for (agent_id, state) in agents_states {
                let state_str = match state.status {
                    codex_app_server_protocol::CollabAgentStatus::PendingInit => "等待初始化",
                    codex_app_server_protocol::CollabAgentStatus::Running => "运行中",
                    codex_app_server_protocol::CollabAgentStatus::Interrupted => "已中断",
                    codex_app_server_protocol::CollabAgentStatus::Completed => "已完成",
                    codex_app_server_protocol::CollabAgentStatus::Errored => "出错",
                    codex_app_server_protocol::CollabAgentStatus::Shutdown => "已关闭",
                    codex_app_server_protocol::CollabAgentStatus::NotFound => "未找到",
                };
                content_parts.push(format!("代理 {}: {}", agent_id, state_str));
                if let Some(msg) = &state.message {
                    content_parts.push(format!("  消息: {}", msg));
                }
            }
            Some(NativeMessage {
                message_id: id.clone(),
                author: "协作工具".to_string(),
                role: "tool".to_string(),
                content: content_parts.join("\n"),
                timestamp: current_timestamp_string(),
                item_type: Some("tool".to_string()),
                status: Some(status_str.to_string()),
                metadata: Some(serde_json::json!({
                    "tool": format!("{:?}", tool),
                    "senderThreadId": sender_thread_id,
                    "receiverThreadIds": receiver_thread_ids,
                    "model": model,
                    "reasoningEffort": reasoning_effort.as_ref().map(|e| format!("{:?}", e)),
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::HookPrompt { id, fragments } => {
            let text: String = fragments.iter().map(|f| f.text.as_str()).collect::<Vec<&str>>().join("");
            Some(NativeMessage {
                message_id: id.clone(),
                author: "Hook提示".to_string(),
                role: "hook".to_string(),
                content: if text.is_empty() { "Hook提示已触发".to_string() } else { text },
                timestamp: current_timestamp_string(),
                item_type: Some("hook".to_string()),
                status: Some("completed".to_string()),
                metadata: Some(serde_json::json!({
                    "fragmentCount": fragments.len(),
                    "hookRunIds": fragments.iter().map(|f| f.hook_run_id.clone()).collect::<Vec<String>>(),
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::ImageView { id, path } => {
            Some(NativeMessage {
                message_id: id.clone(),
                author: "图像查看".to_string(),
                role: "image".to_string(),
                content: format!("查看图片: {}", path),
                timestamp: current_timestamp_string(),
                item_type: Some("image".to_string()),
                status: Some("completed".to_string()),
                metadata: Some(serde_json::json!({
                    "path": path,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::EnteredReviewMode { id, review } => {
            Some(NativeMessage {
                message_id: id.clone(),
                author: "审查模式".to_string(),
                role: "review".to_string(),
                content: format!("进入审查模式\n{}", review),
                timestamp: current_timestamp_string(),
                item_type: Some("review".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "review": review,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::ExitedReviewMode { id, review } => {
            Some(NativeMessage {
                message_id: id.clone(),
                author: "审查模式".to_string(),
                role: "review".to_string(),
                content: format!("退出审查模式\n{}", review),
                timestamp: current_timestamp_string(),
                item_type: Some("review".to_string()),
                status: Some("completed".to_string()),
                metadata: Some(serde_json::json!({
                    "review": review,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::ContextCompaction { id } => {
            Some(NativeMessage {
                message_id: id.clone(),
                author: "上下文压缩".to_string(),
                role: "system".to_string(),
                content: "上下文已压缩以释放空间".to_string(),
                timestamp: current_timestamp_string(),
                item_type: Some("system".to_string()),
                status: Some("completed".to_string()),
                metadata: None,
            })
        }
        _ => None,
    }
}

fn thread_item_id(item: &codex_app_server_protocol::ThreadItem) -> Option<String> {
    match item {
        codex_app_server_protocol::ThreadItem::UserMessage { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::HookPrompt { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::AgentMessage { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::Plan { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::Reasoning { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::CommandExecution { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::FileChange { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::McpToolCall { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::DynamicToolCall { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::CollabAgentToolCall { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::WebSearch { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::ImageView { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::ImageGeneration { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::EnteredReviewMode { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::ExitedReviewMode { id, .. } => Some(id.clone()),
        codex_app_server_protocol::ThreadItem::ContextCompaction { id, .. } => Some(id.clone()),
    }
}

fn upsert_item_started_message(
    state: &mut NativeConversationState,
    thread_id: &str,
    turn_id: &str,
    item: &codex_app_server_protocol::ThreadItem,
) {
    let item_id = match thread_item_id(item) {
        Some(id) => id,
        None => return,
    };
    let message_id = format!("{}:{}", turn_id, item_id);

    if let Some(msg) = thread_item_started_to_message(item, &message_id) {
        let thread = state
            .threads
            .entry(thread_id.to_string())
            .or_insert_with(|| NativeThreadState {
                remote_thread_id: thread_id.to_string(),
                cwd: None,
                messages: Vec::new(),
            });

        if let Some(existing) = thread.messages.iter_mut().find(|m| m.message_id == message_id) {
            *existing = msg.clone();
        } else {
            thread.messages.push(msg.clone());
        }

        if let Some(turn) = state.turns.get_mut(turn_id) {
            turn.messages = thread.messages.clone();
        }
    }
}

fn upsert_item_completed_message(
    state: &mut NativeConversationState,
    thread_id: &str,
    turn_id: &str,
    item: &codex_app_server_protocol::ThreadItem,
) {
    let item_id = match thread_item_id(item) {
        Some(id) => id,
        None => return,
    };
    let message_id = format!("{}:{}", turn_id, item_id);

    if let Some(msg) = thread_item_to_message(item) {
        let thread = state
            .threads
            .entry(thread_id.to_string())
            .or_insert_with(|| NativeThreadState {
                remote_thread_id: thread_id.to_string(),
                cwd: None,
                messages: Vec::new(),
            });

        // 检查是否是 Reasoning 消息，且已有内容
        let is_reasoning = matches!(item, codex_app_server_protocol::ThreadItem::Reasoning { .. });

        if let Some(existing) = thread.messages.iter_mut().find(|m| m.message_id == message_id) {
            // 对于 Reasoning 消息，如果已有内容，保留内容，只更新状态
            if is_reasoning && !existing.content.is_empty() && existing.content != "正在思考..." {
                existing.status = Some("completed".to_string());
            } else {
                let updated_msg = NativeMessage {
                    message_id: message_id.clone(),
                    ..msg
                };
                *existing = updated_msg;
            }
        } else {
            let updated_msg = NativeMessage {
                message_id: message_id.clone(),
                ..msg
            };
            thread.messages.push(updated_msg);
        }

        if let Some(turn) = state.turns.get_mut(turn_id) {
            turn.messages = thread.messages.clone();
        }
    }
}

fn thread_item_started_to_message(
    item: &codex_app_server_protocol::ThreadItem,
    message_id: &str,
) -> Option<NativeMessage> {
    match item {
        codex_app_server_protocol::ThreadItem::Plan { .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "计划".to_string(),
                role: "plan".to_string(),
                content: "正在生成计划...".to_string(),
                timestamp: current_timestamp_string(),
                item_type: Some("plan".to_string()),
                status: Some("inProgress".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::Reasoning { .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "思考过程".to_string(),
                role: "reasoning".to_string(),
                content: "正在思考...".to_string(),
                timestamp: current_timestamp_string(),
                item_type: Some("reasoning".to_string()),
                status: Some("inProgress".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::CommandExecution { command, cwd, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "命令执行".to_string(),
                role: "command".to_string(),
                content: format!("正在执行: {}", command),
                timestamp: current_timestamp_string(),
                item_type: Some("command".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "command": command,
                    "cwd": cwd.display().to_string(),
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::FileChange { changes, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "文件变更".to_string(),
                role: "file".to_string(),
                content: format!("正在修改 {} 个文件...", changes.len()),
                timestamp: current_timestamp_string(),
                item_type: Some("file".to_string()),
                status: Some("inProgress".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::McpToolCall { server, tool, arguments, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "MCP 工具".to_string(),
                role: "tool".to_string(),
                content: format!("正在调用 {}/{}", server, tool),
                timestamp: current_timestamp_string(),
                item_type: Some("tool".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "server": server,
                    "tool": tool,
                    "arguments": arguments,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::WebSearch { query, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "网络搜索".to_string(),
                role: "search".to_string(),
                content: format!("正在搜索: {}", query),
                timestamp: current_timestamp_string(),
                item_type: Some("search".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "query": query,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::DynamicToolCall { tool, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "动态工具".to_string(),
                role: "tool".to_string(),
                content: format!("正在调用工具: {}", tool),
                timestamp: current_timestamp_string(),
                item_type: Some("tool".to_string()),
                status: Some("inProgress".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::ImageGeneration { .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "图像生成".to_string(),
                role: "image".to_string(),
                content: "正在生成图像...".to_string(),
                timestamp: current_timestamp_string(),
                item_type: Some("image".to_string()),
                status: Some("inProgress".to_string()),
                metadata: None,
            })
        }
        codex_app_server_protocol::ThreadItem::CollabAgentToolCall { tool, prompt, model, .. } => {
            let tool_name = match tool {
                codex_app_server_protocol::CollabAgentTool::SpawnAgent => "创建子代理",
                codex_app_server_protocol::CollabAgentTool::SendInput => "发送输入",
                codex_app_server_protocol::CollabAgentTool::ResumeAgent => "恢复代理",
                codex_app_server_protocol::CollabAgentTool::Wait => "等待",
                codex_app_server_protocol::CollabAgentTool::CloseAgent => "关闭代理",
            };
            let mut content_parts = vec![format!("正在执行: {}", tool_name)];
            if let Some(p) = prompt {
                if !p.is_empty() {
                    content_parts.push(format!("提示词: {}", p));
                }
            }
            if let Some(m) = model {
                content_parts.push(format!("模型: {}", m));
            }
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "协作工具".to_string(),
                role: "tool".to_string(),
                content: content_parts.join("\n"),
                timestamp: current_timestamp_string(),
                item_type: Some("tool".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "tool": format!("{:?}", tool),
                    "model": model,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::HookPrompt { fragments, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "Hook提示".to_string(),
                role: "hook".to_string(),
                content: "Hook提示正在处理...".to_string(),
                timestamp: current_timestamp_string(),
                item_type: Some("hook".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "fragmentCount": fragments.len(),
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::ImageView { path, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "图像查看".to_string(),
                role: "image".to_string(),
                content: format!("正在查看图片: {}", path),
                timestamp: current_timestamp_string(),
                item_type: Some("image".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "path": path,
                })),
            })
        }
        codex_app_server_protocol::ThreadItem::EnteredReviewMode { review, .. } => {
            Some(NativeMessage {
                message_id: message_id.to_string(),
                author: "审查模式".to_string(),
                role: "review".to_string(),
                content: format!("进入审查模式\n{}", review),
                timestamp: current_timestamp_string(),
                item_type: Some("review".to_string()),
                status: Some("inProgress".to_string()),
                metadata: Some(serde_json::json!({
                    "review": review,
                })),
            })
        }
        _ => None,
    }
}

fn map_turn_status(status: &TurnStatus) -> &'static str {
    match status {
        TurnStatus::Completed => "completed",
        TurnStatus::Failed => "failed",
        TurnStatus::Interrupted => "interrupted",
        TurnStatus::InProgress => "inProgress",
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
    use codex_app_server_protocol::FileUpdateChange;
    use codex_app_server_protocol::ItemCompletedNotification;
    use codex_app_server_protocol::PatchApplyStatus;
    use codex_app_server_protocol::PatchChangeKind;
    use codex_app_server_protocol::ServerNotification;
    use codex_app_server_protocol::ThreadItem;
    use std::fs;
    use std::time::SystemTime;

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
        assert!(config.contains("experimental_use_freeform_apply_patch = true"));
    }

    #[test]
    fn item_completed_file_change_backfills_turn_diff() {
        let diff = "diff --git a/foo.py b/foo.py\n--- a/foo.py\n+++ b/foo.py\n@@ -0,0 +1 @@\n+print('hello')";
        with_native_state(|state| {
            *state = NativeConversationState::default();
            state.turns.insert(
                "turn".to_string(),
                NativeTurnState {
                    thread_id: "thread".to_string(),
                    status: "inProgress".to_string(),
                    ..Default::default()
                },
            );
        });

        apply_server_notification(
            &ServerNotification::ItemCompleted(ItemCompletedNotification {
                thread_id: "thread".to_string(),
                turn_id: "turn".to_string(),
                item: ThreadItem::FileChange {
                    id: "item".to_string(),
                    changes: vec![FileUpdateChange {
                        path: "foo.py".to_string(),
                        kind: PatchChangeKind::Add,
                        diff: diff.to_string(),
                    }],
                    status: PatchApplyStatus::Completed,
                },
            }),
            Some("turn"),
        );

        let stored = with_native_state(|state| {
            state
                .turns
                .get("turn")
                .cloned()
                .expect("turn state should exist after notification")
        });
        assert_eq!(stored.diff, diff);
    }

    #[test]
    fn append_turn_diff_preserves_multiple_files() {
        let mut turn = NativeTurnState {
            diff: "diff --git a/foo.py b/foo.py\n--- a/foo.py\n+++ b/foo.py\n@@ -0,0 +1 @@\n+print('foo')"
                .to_string(),
            ..Default::default()
        };

        append_turn_diff(
            &mut turn,
            "diff --git a/bar.py b/bar.py\n--- a/bar.py\n+++ b/bar.py\n@@ -0,0 +1 @@\n+print('bar')",
        );

        assert!(turn.diff.contains("diff --git a/foo.py b/foo.py"));
        assert!(turn.diff.contains("diff --git a/bar.py b/bar.py"));
    }

    #[test]
    fn append_turn_diff_replaces_same_file_with_more_complete_section() {
        let mut turn = NativeTurnState {
            diff: "diff --git a/foo.py b/foo.py\n--- a/foo.py\n+++ b/foo.py\n@@ -0,0 +1 @@\n+print('foo')"
                .to_string(),
            ..Default::default()
        };

        append_turn_diff(
            &mut turn,
            "diff --git a/foo.py b/foo.py\n--- a/foo.py\n+++ b/foo.py\n@@ -0,0 +1,2 @@\n+print('foo')\n+print('bar')",
        );

        assert_eq!(turn.diff.matches("diff --git a/foo.py b/foo.py").count(), 1);
        assert!(turn.diff.contains("+print('foo')"));
        assert!(turn.diff.contains("+print('bar')"));
    }

    #[test]
    fn completed_turn_with_empty_diff_waits_for_trailing_turn_diff() {
        with_native_state(|state| {
            *state = NativeConversationState::default();
            state.turns.insert(
                "turn".to_string(),
                NativeTurnState {
                    thread_id: "thread".to_string(),
                    status: "completed".to_string(),
                    diff: String::new(),
                    ..Default::default()
                },
            );
        });

        assert!(should_wait_for_trailing_turn_diff("turn"));
    }

    #[test]
    fn completed_turn_with_diff_does_not_wait_for_trailing_turn_diff() {
        with_native_state(|state| {
            *state = NativeConversationState::default();
            state.turns.insert(
                "turn".to_string(),
                NativeTurnState {
                    thread_id: "thread".to_string(),
                    status: "completed".to_string(),
                    diff: "diff --git a/foo b/foo".to_string(),
                    ..Default::default()
                },
            );
        });

        assert!(!should_wait_for_trailing_turn_diff("turn"));
    }

    #[tokio::test]
    async fn local_turn_diff_tracker_backfills_completed_turn_without_remote_diff() {
        let unique = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .expect("system clock should be after unix epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("codex-ohos-host-diff-{unique}"));
        fs::create_dir_all(&dir).expect("temp test dir should create");
        let file = dir.join("created.txt");
        let tracker =
            build_local_turn_diff_tracker(Some(&dir)).expect("tracker should be created for cwd");

        fs::write(&file, "hello world\n").expect("file write should succeed");

        with_native_state(|state| {
            *state = NativeConversationState::default();
            state.turns.insert(
                "turn".to_string(),
                NativeTurnState {
                    thread_id: "thread".to_string(),
                    status: "completed".to_string(),
                    cwd: Some(dir.clone()),
                    local_diff_tracker: Some(tracker),
                    ..Default::default()
                },
            );
        });

        refresh_turn_diff_from_local_tracker("turn")
            .await
            .expect("local diff refresh should succeed");

        let stored = with_native_state(|state| {
            state
                .turns
                .get("turn")
                .cloned()
                .expect("turn state should exist after local diff refresh")
        });
        assert!(stored.diff.contains("created.txt"));
        assert!(stored.diff.contains("+hello world"));
        assert!(!stored.diff_authoritative);

        let _ = fs::remove_dir_all(&dir);
    }
}
