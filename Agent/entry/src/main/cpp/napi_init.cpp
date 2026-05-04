#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mutex>
#include <string>
#include "napi/native_api.h"
#include "codex_ohos_host.h"

namespace {
constexpr size_t MAX_HOME_ARG_LEN = 4096;
constexpr size_t MAX_URL_ARG_LEN = 1024;
constexpr size_t MAX_MODEL_ARG_LEN = 512;
constexpr size_t MAX_API_KEY_ARG_LEN = 8192;
constexpr size_t MAX_CATALOG_JSON_ARG_LEN = 65536;
constexpr size_t MAX_REGISTRY_JSON_ARG_LEN = 65536;
constexpr size_t MAX_DIR_PATH_ARG_LEN = 4096;
constexpr size_t MAX_SKILL_JSON_ARG_LEN = 8192;
constexpr size_t MAX_BACKUP_ID_ARG_LEN = 512;
constexpr size_t MAX_PROMPTS_CONTENT_ARG_LEN = 262144;
constexpr size_t MAX_JSON_ARG_LEN = 262144;
constexpr const char* OHOS_DEFAULT_PATH = "/system/bin:/vendor/bin:/system/xbin:/bin";
constexpr const char* OHOS_DEFAULT_SHELL = "/system/bin/sh";

struct BridgeApi {
    void* handle = nullptr;

    int32_t (*start)(const char*, const char*) = nullptr;
    int32_t (*is_running)(void) = nullptr;
    const char* (*last_message)(void) = nullptr;
    const char* (*server_url)(void) = nullptr;
    const char* (*provider_config_json)(const char*) = nullptr;
    int32_t (*save_provider_config)(const char*, const char*, const char*, const char*) = nullptr;
    const char* (*provider_catalog_json)(const char*) = nullptr;
    int32_t (*save_provider_catalog)(const char*, const char*) = nullptr;
    const char* (*skills_registry_json)(const char*) = nullptr;
    int32_t (*save_skills_registry)(const char*, const char*) = nullptr;
    const char* (*skills_repos_json)(const char*) = nullptr;
    int32_t (*save_skills_repos)(const char*, const char*) = nullptr;
    const char* (*compute_dir_hash)(const char*) = nullptr;
    const char* (*skills_backups_json)(const char*) = nullptr;
    const char* (*create_skill_backup)(const char*, const char*, const char*) = nullptr;
    int32_t (*delete_skill_backup)(const char*, const char*) = nullptr;
    const char* (*install_skill_from_dir)(const char*, const char*, const char*) = nullptr;
    const char* (*uninstall_skill)(const char*, const char*) = nullptr;
    const char* (*set_skill_enabled)(const char*, const char*, int32_t) = nullptr;
    const char* (*reconcile_skills)(const char*) = nullptr;
    const char* (*prompts_registry_json)(const char*) = nullptr;
    int32_t (*save_prompts_registry)(const char*, const char*) = nullptr;
    const char* (*read_agents_md)(const char*) = nullptr;
    int32_t (*write_agents_md)(const char*, const char*) = nullptr;
    const char* (*initialize)(const char*) = nullptr;
    const char* (*thread_start)(const char*) = nullptr;
    const char* (*thread_list)(const char*) = nullptr;
    const char* (*thread_read)(const char*) = nullptr;
    const char* (*thread_resume)(const char*) = nullptr;
    const char* (*thread_name_set)(const char*) = nullptr;
    const char* (*thread_archive)(const char*) = nullptr;
    const char* (*turn_start)(const char*) = nullptr;
    const char* (*turn_events)(const char*, const char*) = nullptr;
    const char* (*turn_poll)(const char*, const char*) = nullptr;
    const char* (*approval_poll)(void) = nullptr;
    int32_t (*approval_approve)(const char*) = nullptr;
    int32_t (*approval_decline)(const char*) = nullptr;
    const char* (*mcp_status_list)(const char*) = nullptr;
    const char* (*mcp_config_read)(const char*) = nullptr;
    int32_t (*mcp_config_write)(const char*) = nullptr;
    int32_t (*mcp_config_batch_write)(const char*) = nullptr;
    int32_t (*mcp_reload)(void) = nullptr;
    const char* (*mcp_oauth_start)(const char*) = nullptr;
    const char* (*account_login)(const char*) = nullptr;
    const char* (*account_read)(void) = nullptr;
    const char* (*check_workspace_access)(const char*) = nullptr;
};

template <typename T>
bool LoadSymbol(void* handle, const char* name, T* target) {
    *target = reinterpret_cast<T>(dlsym(handle, name));
    return *target != nullptr;
}

bool LoadBridgeApi(BridgeApi* api) {
    api->handle = dlopen("libcodex_ohos_host.so", RTLD_NOW);
    if (api->handle == nullptr) {
        return false;
    }

    bool ok =
        LoadSymbol(api->handle, "codex_ohos_host_start", &api->start) &&
        LoadSymbol(api->handle, "codex_ohos_host_is_running", &api->is_running) &&
        LoadSymbol(api->handle, "codex_ohos_host_last_message", &api->last_message) &&
        LoadSymbol(api->handle, "codex_ohos_host_server_url", &api->server_url) &&
        LoadSymbol(api->handle, "codex_ohos_host_provider_config_json", &api->provider_config_json) &&
        LoadSymbol(api->handle, "codex_ohos_host_save_provider_config", &api->save_provider_config) &&
        LoadSymbol(api->handle, "codex_ohos_host_provider_catalog_json", &api->provider_catalog_json) &&
        LoadSymbol(api->handle, "codex_ohos_host_save_provider_catalog", &api->save_provider_catalog) &&
        LoadSymbol(api->handle, "codex_ohos_host_skills_registry_json", &api->skills_registry_json) &&
        LoadSymbol(api->handle, "codex_ohos_host_save_skills_registry", &api->save_skills_registry) &&
        LoadSymbol(api->handle, "codex_ohos_host_skills_repos_json", &api->skills_repos_json) &&
        LoadSymbol(api->handle, "codex_ohos_host_save_skills_repos", &api->save_skills_repos) &&
        LoadSymbol(api->handle, "codex_ohos_host_compute_dir_hash", &api->compute_dir_hash) &&
        LoadSymbol(api->handle, "codex_ohos_host_skills_backups_json", &api->skills_backups_json) &&
        LoadSymbol(api->handle, "codex_ohos_host_create_skill_backup", &api->create_skill_backup) &&
        LoadSymbol(api->handle, "codex_ohos_host_delete_skill_backup", &api->delete_skill_backup) &&
        LoadSymbol(api->handle, "codex_ohos_host_install_skill_from_dir", &api->install_skill_from_dir) &&
        LoadSymbol(api->handle, "codex_ohos_host_uninstall_skill", &api->uninstall_skill) &&
        LoadSymbol(api->handle, "codex_ohos_host_set_skill_enabled", &api->set_skill_enabled) &&
        LoadSymbol(api->handle, "codex_ohos_host_reconcile_skills", &api->reconcile_skills) &&
        LoadSymbol(api->handle, "codex_ohos_host_prompts_registry_json", &api->prompts_registry_json) &&
        LoadSymbol(api->handle, "codex_ohos_host_save_prompts_registry", &api->save_prompts_registry) &&
        LoadSymbol(api->handle, "codex_ohos_host_read_agents_md", &api->read_agents_md) &&
        LoadSymbol(api->handle, "codex_ohos_host_write_agents_md", &api->write_agents_md) &&
        LoadSymbol(api->handle, "codex_ohos_host_initialize", &api->initialize) &&
        LoadSymbol(api->handle, "codex_ohos_host_thread_start", &api->thread_start) &&
        LoadSymbol(api->handle, "codex_ohos_host_thread_list", &api->thread_list) &&
        LoadSymbol(api->handle, "codex_ohos_host_thread_read", &api->thread_read) &&
        LoadSymbol(api->handle, "codex_ohos_host_thread_resume", &api->thread_resume) &&
        LoadSymbol(api->handle, "codex_ohos_host_thread_name_set", &api->thread_name_set) &&
        LoadSymbol(api->handle, "codex_ohos_host_thread_archive", &api->thread_archive) &&
        LoadSymbol(api->handle, "codex_ohos_host_turn_start", &api->turn_start) &&
        LoadSymbol(api->handle, "codex_ohos_host_turn_events", &api->turn_events) &&
        LoadSymbol(api->handle, "codex_ohos_host_turn_poll", &api->turn_poll) &&
        LoadSymbol(api->handle, "codex_ohos_host_approval_poll", &api->approval_poll) &&
        LoadSymbol(api->handle, "codex_ohos_host_approval_approve", &api->approval_approve) &&
        LoadSymbol(api->handle, "codex_ohos_host_approval_decline", &api->approval_decline) &&
        LoadSymbol(api->handle, "codex_ohos_host_mcp_status_list", &api->mcp_status_list) &&
        LoadSymbol(api->handle, "codex_ohos_host_mcp_config_read", &api->mcp_config_read) &&
        LoadSymbol(api->handle, "codex_ohos_host_mcp_config_write", &api->mcp_config_write) &&
        LoadSymbol(api->handle, "codex_ohos_host_mcp_config_batch_write", &api->mcp_config_batch_write) &&
        LoadSymbol(api->handle, "codex_ohos_host_mcp_reload", &api->mcp_reload) &&
        LoadSymbol(api->handle, "codex_ohos_host_mcp_oauth_start", &api->mcp_oauth_start) &&
        LoadSymbol(api->handle, "codex_ohos_host_account_login", &api->account_login) &&
        LoadSymbol(api->handle, "codex_ohos_host_account_read", &api->account_read);

    if (!ok) {
        dlclose(api->handle);
        api->handle = nullptr;
        return false;
    }

    LoadSymbol(api->handle, "codex_ohos_host_check_workspace_access", &api->check_workspace_access);
    return true;
}

BridgeApi& SharedBridgeApi() {
    static BridgeApi api;
    return api;
}

std::mutex& SharedBridgeApiMutex() {
    static std::mutex mutex;
    return mutex;
}

bool AcquireBridgeApi(BridgeApi** api) {
    std::lock_guard<std::mutex> lock(SharedBridgeApiMutex());
    BridgeApi& shared = SharedBridgeApi();
    if (shared.handle == nullptr && !LoadBridgeApi(&shared)) {
        *api = nullptr;
        return false;
    }
    *api = &shared;
    return true;
}

void UnloadBridgeApi(BridgeApi* api) {
    (void)api;
}

void EnsureOhosShellEnvironment() {
#if defined(__OHOS__)
    const char* current_path = std::getenv("PATH");
    if (current_path == nullptr || current_path[0] == '\0') {
        setenv("PATH", OHOS_DEFAULT_PATH, 1);
    } else if (std::strstr(current_path, "/system/bin") == nullptr) {
        std::string merged_path(OHOS_DEFAULT_PATH);
        merged_path.push_back(':');
        merged_path.append(current_path);
        setenv("PATH", merged_path.c_str(), 1);
    }

    const char* current_shell = std::getenv("SHELL");
    if (current_shell == nullptr || current_shell[0] == '\0') {
        setenv("SHELL", OHOS_DEFAULT_SHELL, 1);
    }
#endif
}


bool ReadOptionalUtf8(napi_env env, napi_value value, char* buffer, size_t capacity) {
    if (capacity == 0) {
        return false;
    }
    buffer[0] = '\0';
    if (value == nullptr) {
        return true;
    }
    napi_valuetype value_type = napi_undefined;
    if (napi_typeof(env, value, &value_type) != napi_ok) {
        return false;
    }
    if (value_type == napi_undefined || value_type == napi_null) {
        return true;
    }
    if (value_type != napi_string) {
        napi_throw_type_error(env, nullptr, "Expected a string argument.");
        return false;
    }
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer, capacity, &copied) != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to read UTF-8 string argument.");
        return false;
    }
    buffer[copied] = '\0';
    return true;
}

napi_value CreateUtf8String(napi_env env, const char* value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value == nullptr ? "" : value, NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value CreateBoolean(napi_env env, bool value) {
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value CreateInt32(napi_env env, int32_t value) {
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

napi_value ThrowLoadError(napi_env env) {
    napi_throw_error(env, nullptr, "Failed to load libcodex_ohos_host.so.");
    return nullptr;
}

napi_value BuildStatusObject(napi_env env, BridgeApi* api, int32_t code) {
    napi_value result = nullptr;
    napi_create_object(env, &result);
    napi_set_named_property(env, result, "running", CreateBoolean(env, api->is_running() == 1));
    napi_set_named_property(env, result, "message", CreateUtf8String(env, api->last_message()));
    napi_set_named_property(env, result, "serverUrl", CreateUtf8String(env, api->server_url()));
    napi_set_named_property(env, result, "code", CreateInt32(env, code));
    return result;
}

napi_value StartHost(napi_env env, napi_callback_info info) {
    BridgeApi* api = nullptr;
    if (!AcquireBridgeApi(&api)) {
        return ThrowLoadError(env);
    }
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN];
    char server_url[MAX_URL_ARG_LEN];
    codex_home[0] = '\0';
    server_url[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], server_url, sizeof(server_url))) {
        return nullptr;
    }
    EnsureOhosShellEnvironment();
    int32_t code = api->start(codex_home[0] == '\0' ? nullptr : codex_home, server_url[0] == '\0' ? nullptr : server_url);
    napi_value result = BuildStatusObject(env, api, code);
    return result;
}

napi_value GetStatus(napi_env env, napi_callback_info info) {
    (void)info;
    BridgeApi* api = nullptr;
    if (!AcquireBridgeApi(&api)) {
        return ThrowLoadError(env);
    }
    napi_value result = BuildStatusObject(env, api, 0);
    return result;
}

napi_value IsHostRunning(napi_env env, napi_callback_info info) {
    (void)info;
    BridgeApi* api = nullptr;
    if (!AcquireBridgeApi(&api)) {
        return ThrowLoadError(env);
    }
    napi_value result = CreateBoolean(env, api->is_running() == 1);
    return result;
}

napi_value GetLastMessage(napi_env env, napi_callback_info info) {
    (void)info;
    BridgeApi* api = nullptr;
    if (!AcquireBridgeApi(&api)) {
        return ThrowLoadError(env);
    }
    napi_value result = CreateUtf8String(env, api->last_message());
    return result;
}

napi_value GetServerUrl(napi_env env, napi_callback_info info) {
    (void)info;
    BridgeApi* api = nullptr;
    if (!AcquireBridgeApi(&api)) {
        return ThrowLoadError(env);
    }
    napi_value result = CreateUtf8String(env, api->server_url());
    return result;
}

napi_value CallString1(napi_env env, napi_callback_info info, const char* (*fn)(const char*)) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char arg0[MAX_JSON_ARG_LEN];
    arg0[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], arg0, sizeof(arg0))) {
        return nullptr;
    }
    return CreateUtf8String(env, fn(arg0[0] == '\0' ? nullptr : arg0));
}

napi_value CallString2(napi_env env, napi_callback_info info, const char* (*fn)(const char*, const char*)) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char arg0[MAX_JSON_ARG_LEN];
    char arg1[MAX_JSON_ARG_LEN];
    arg0[0] = '\0';
    arg1[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], arg0, sizeof(arg0))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], arg1, sizeof(arg1))) {
        return nullptr;
    }
    return CreateUtf8String(env, fn(arg0[0] == '\0' ? nullptr : arg0, arg1[0] == '\0' ? nullptr : arg1));
}

napi_value CallIntString1(napi_env env, napi_callback_info info, int32_t (*fn)(const char*)) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char arg0[MAX_JSON_ARG_LEN];
    arg0[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], arg0, sizeof(arg0))) {
        return nullptr;
    }
    return CreateInt32(env, fn(arg0[0] == '\0' ? nullptr : arg0));
}

napi_value GetProviderConfig(napi_env env, napi_callback_info info) {
    BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env);
    napi_value result = CallString1(env, info, api->provider_config_json);
    return result;
}

napi_value SaveProviderConfig(napi_env env, napi_callback_info info) {
    BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 4; napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], base_url[MAX_URL_ARG_LEN], api_key[MAX_API_KEY_ARG_LEN], model[MAX_MODEL_ARG_LEN];
    codex_home[0] = '\0'; base_url[0] = '\0'; api_key[0] = '\0'; model[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], base_url, sizeof(base_url))) { return nullptr; }
    if (argc >= 3 && !ReadOptionalUtf8(env, args[2], api_key, sizeof(api_key))) { return nullptr; }
    if (argc >= 4 && !ReadOptionalUtf8(env, args[3], model, sizeof(model))) { return nullptr; }
    int32_t code = api->save_provider_config(codex_home[0] == '\0' ? nullptr : codex_home, base_url[0] == '\0' ? nullptr : base_url, api_key[0] == '\0' ? nullptr : api_key, model[0] == '\0' ? nullptr : model);
    if (code != 0) { napi_throw_error(env, nullptr, "Failed to save provider config."); return nullptr; }
    napi_value result = CreateUtf8String(env, api->provider_config_json(codex_home[0] == '\0' ? nullptr : codex_home));
    return result;
}

napi_value GetProviderCatalog(napi_env env, napi_callback_info info) {
    BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env);
    napi_value result = CallString1(env, info, api->provider_catalog_json);
    return result;
}

napi_value SaveProviderCatalog(napi_env env, napi_callback_info info) {
    BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], catalog_json[MAX_CATALOG_JSON_ARG_LEN];
    codex_home[0] = '\0'; catalog_json[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], catalog_json, sizeof(catalog_json))) { return nullptr; }
    int32_t code = api->save_provider_catalog(codex_home[0] == '\0' ? nullptr : codex_home, catalog_json[0] == '\0' ? nullptr : catalog_json);
    if (code != 0) { napi_throw_error(env, nullptr, "Failed to save provider catalog."); return nullptr; }
    napi_value result = CreateUtf8String(env, api->provider_catalog_json(codex_home[0] == '\0' ? nullptr : codex_home));
    return result;
}

napi_value GetSkillsRegistry(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->skills_registry_json); return result; }
napi_value SaveSkillsRegistry(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], registry_json[MAX_REGISTRY_JSON_ARG_LEN]; codex_home[0] = '\0'; registry_json[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], registry_json, sizeof(registry_json))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateInt32(env, api.save_skills_registry(codex_home[0] == '\0' ? nullptr : codex_home, registry_json[0] == '\0' ? nullptr : registry_json));
    UnloadBridgeApi(&api); return result;
}
napi_value GetSkillsRepos(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->skills_repos_json); return result; }
napi_value SaveSkillsRepos(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], repos_json[MAX_REGISTRY_JSON_ARG_LEN]; codex_home[0] = '\0'; repos_json[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], repos_json, sizeof(repos_json))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateInt32(env, api.save_skills_repos(codex_home[0] == '\0' ? nullptr : codex_home, repos_json[0] == '\0' ? nullptr : repos_json));
    UnloadBridgeApi(&api); return result;
}
napi_value ComputeDirHash(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->compute_dir_hash); return result; }
napi_value GetSkillsBackups(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->skills_backups_json); return result; }

napi_value CreateSkillBackup(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 3; napi_value args[3] = {nullptr, nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], skill_dir[MAX_DIR_PATH_ARG_LEN], skill_json[MAX_SKILL_JSON_ARG_LEN]; codex_home[0] = '\0'; skill_dir[0] = '\0'; skill_json[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], skill_dir, sizeof(skill_dir))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 3 && !ReadOptionalUtf8(env, args[2], skill_json, sizeof(skill_json))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateUtf8String(env, api.create_skill_backup(codex_home[0] == '\0' ? nullptr : codex_home, skill_dir[0] == '\0' ? nullptr : skill_dir, skill_json[0] == '\0' ? nullptr : skill_json));
    UnloadBridgeApi(&api); return result;
}

napi_value DeleteSkillBackup(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], backup_id[MAX_BACKUP_ID_ARG_LEN]; codex_home[0] = '\0'; backup_id[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], backup_id, sizeof(backup_id))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateInt32(env, api.delete_skill_backup(codex_home[0] == '\0' ? nullptr : codex_home, backup_id[0] == '\0' ? nullptr : backup_id));
    UnloadBridgeApi(&api); return result;
}

napi_value InstallSkillFromDir(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 3; napi_value args[3] = {nullptr, nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], source_dir[MAX_DIR_PATH_ARG_LEN], skill_json[MAX_SKILL_JSON_ARG_LEN]; codex_home[0] = '\0'; source_dir[0] = '\0'; skill_json[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], source_dir, sizeof(source_dir))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 3 && !ReadOptionalUtf8(env, args[2], skill_json, sizeof(skill_json))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateUtf8String(env, api.install_skill_from_dir(codex_home[0] == '\0' ? nullptr : codex_home, source_dir[0] == '\0' ? nullptr : source_dir, skill_json[0] == '\0' ? nullptr : skill_json));
    UnloadBridgeApi(&api); return result;
}

napi_value UninstallSkill(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], skill_id[MAX_BACKUP_ID_ARG_LEN]; codex_home[0] = '\0'; skill_id[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], skill_id, sizeof(skill_id))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateUtf8String(env, api.uninstall_skill(codex_home[0] == '\0' ? nullptr : codex_home, skill_id[0] == '\0' ? nullptr : skill_id));
    UnloadBridgeApi(&api); return result;
}

napi_value SetSkillEnabled(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 3; napi_value args[3] = {nullptr, nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], skill_id[MAX_BACKUP_ID_ARG_LEN]; codex_home[0] = '\0'; skill_id[0] = '\0';
    int32_t enabled = 1;
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], skill_id, sizeof(skill_id))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 3) { napi_get_value_int32(env, args[2], &enabled); }
    napi_value result = CreateUtf8String(env, api.set_skill_enabled(codex_home[0] == '\0' ? nullptr : codex_home, skill_id[0] == '\0' ? nullptr : skill_id, enabled));
    UnloadBridgeApi(&api); return result;
}

napi_value ReconcileSkills(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->reconcile_skills); return result; }

napi_value GetPromptsRegistry(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->prompts_registry_json); return result; }
napi_value SavePromptsRegistry(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], registry_json[MAX_REGISTRY_JSON_ARG_LEN]; codex_home[0] = '\0'; registry_json[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], registry_json, sizeof(registry_json))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateInt32(env, api.save_prompts_registry(codex_home[0] == '\0' ? nullptr : codex_home, registry_json[0] == '\0' ? nullptr : registry_json));
    UnloadBridgeApi(&api); return result;
}
napi_value ReadAgentsMd(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->read_agents_md); return result; }

napi_value WriteAgentsMd(napi_env env, napi_callback_info info) {
    BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env);
    size_t argc = 2; napi_value args[2] = {nullptr, nullptr}; napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char codex_home[MAX_HOME_ARG_LEN], content[MAX_PROMPTS_CONTENT_ARG_LEN]; codex_home[0] = '\0'; content[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) { UnloadBridgeApi(&api); return nullptr; }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], content, sizeof(content))) { UnloadBridgeApi(&api); return nullptr; }
    napi_value result = CreateInt32(env, api.write_agents_md(codex_home[0] == '\0' ? nullptr : codex_home, content[0] == '\0' ? nullptr : content));
    UnloadBridgeApi(&api); return result;
}

napi_value InitializeBridge(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->initialize); return result; }
napi_value ThreadStart(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->thread_start); return result; }
napi_value ThreadList(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->thread_list); return result; }
napi_value ThreadRead(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->thread_read); return result; }
napi_value ThreadResume(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->thread_resume); return result; }
napi_value ThreadNameSet(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->thread_name_set); return result; }
napi_value ThreadArchive(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->thread_archive); return result; }
napi_value TurnStart(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api->turn_start); return result; }
napi_value TurnEvents(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString2(env, info, api->turn_events); return result; }
napi_value TurnPoll(napi_env env, napi_callback_info info) { BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString2(env, info, api->turn_poll); return result; }
napi_value ApprovalPoll(napi_env env, napi_callback_info info) { (void)info; BridgeApi* api = nullptr; if (!AcquireBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CreateUtf8String(env, api->approval_poll()); return result; }
napi_value ApprovalApprove(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallIntString1(env, info, api.approval_approve); UnloadBridgeApi(&api); return result; }
napi_value ApprovalDecline(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallIntString1(env, info, api.approval_decline); UnloadBridgeApi(&api); return result; }
napi_value McpStatusList(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api.mcp_status_list); UnloadBridgeApi(&api); return result; }
napi_value McpConfigRead(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api.mcp_config_read); UnloadBridgeApi(&api); return result; }
napi_value McpConfigWrite(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallIntString1(env, info, api.mcp_config_write); UnloadBridgeApi(&api); return result; }
napi_value McpConfigBatchWrite(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallIntString1(env, info, api.mcp_config_batch_write); UnloadBridgeApi(&api); return result; }
napi_value McpReload(napi_env env, napi_callback_info info) { (void)info; BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CreateInt32(env, api.mcp_reload()); UnloadBridgeApi(&api); return result; }
napi_value McpOauthStart(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api.mcp_oauth_start); UnloadBridgeApi(&api); return result; }
napi_value AccountLogin(napi_env env, napi_callback_info info) { BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CallString1(env, info, api.account_login); UnloadBridgeApi(&api); return result; }
napi_value AccountRead(napi_env env, napi_callback_info info) { (void)info; BridgeApi api; if (!LoadBridgeApi(&api)) return ThrowLoadError(env); napi_value result = CreateUtf8String(env, api.account_read()); UnloadBridgeApi(&api); return result; }
napi_value CheckWorkspaceAccess(napi_env env, napi_callback_info info) {
    BridgeApi api;
    if (!LoadBridgeApi(&api)) {
        return ThrowLoadError(env);
    }
    if (api.check_workspace_access == nullptr) {
        UnloadBridgeApi(&api);
        return CreateUtf8String(env, "{\"rootPath\":\"\",\"accessKind\":\"unknown\",\"permissionState\":\"unavailable\",\"writable\":false,\"exists\":false,\"message\":\"workspace access probe unavailable\"}");
    }
    napi_value result = CallString1(env, info, api.check_workspace_access);
    UnloadBridgeApi(&api);
    return result;
}
}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startHost", nullptr, StartHost, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isHostRunning", nullptr, IsHostRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLastMessage", nullptr, GetLastMessage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getServerUrl", nullptr, GetServerUrl, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getProviderConfig", nullptr, GetProviderConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveProviderConfig", nullptr, SaveProviderConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getProviderCatalog", nullptr, GetProviderCatalog, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveProviderCatalog", nullptr, SaveProviderCatalog, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSkillsRegistry", nullptr, GetSkillsRegistry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveSkillsRegistry", nullptr, SaveSkillsRegistry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSkillsRepos", nullptr, GetSkillsRepos, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveSkillsRepos", nullptr, SaveSkillsRepos, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"computeDirHash", nullptr, ComputeDirHash, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSkillsBackups", nullptr, GetSkillsBackups, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createSkillBackup", nullptr, CreateSkillBackup, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"deleteSkillBackup", nullptr, DeleteSkillBackup, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"installSkillFromDir", nullptr, InstallSkillFromDir, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"uninstallSkill", nullptr, UninstallSkill, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSkillEnabled", nullptr, SetSkillEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"reconcileSkills", nullptr, ReconcileSkills, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getPromptsRegistry", nullptr, GetPromptsRegistry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"savePromptsRegistry", nullptr, SavePromptsRegistry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"readAgentsMd", nullptr, ReadAgentsMd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"writeAgentsMd", nullptr, WriteAgentsMd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initialize", nullptr, InitializeBridge, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadStart", nullptr, ThreadStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadList", nullptr, ThreadList, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadRead", nullptr, ThreadRead, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadResume", nullptr, ThreadResume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadNameSet", nullptr, ThreadNameSet, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"threadArchive", nullptr, ThreadArchive, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"turnStart", nullptr, TurnStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"turnEvents", nullptr, TurnEvents, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"turnPoll", nullptr, TurnPoll, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"approvalPoll", nullptr, ApprovalPoll, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"approvalApprove", nullptr, ApprovalApprove, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"approvalDecline", nullptr, ApprovalDecline, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mcpStatusList", nullptr, McpStatusList, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mcpConfigRead", nullptr, McpConfigRead, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mcpConfigWrite", nullptr, McpConfigWrite, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mcpConfigBatchWrite", nullptr, McpConfigBatchWrite, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mcpReload", nullptr, McpReload, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mcpOauthStart", nullptr, McpOauthStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"accountLogin", nullptr, AccountLogin, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"accountRead", nullptr, AccountRead, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkWorkspaceAccess", nullptr, CheckWorkspaceAccess, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module entryModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&entryModule);
}
