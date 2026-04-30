#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "napi/native_api.h"

extern "C" {
int32_t codex_ohos_host_start(const char* codex_home, const char* listen_url);
int32_t codex_ohos_host_is_running(void);
const char* codex_ohos_host_last_message(void);
const char* codex_ohos_host_server_url(void);
const char* codex_ohos_host_provider_config_json(const char* codex_home);
int32_t codex_ohos_host_save_provider_config(
    const char* codex_home,
    const char* base_url,
    const char* api_key,
    const char* model
);
const char* codex_ohos_host_provider_catalog_json(const char* codex_home);
int32_t codex_ohos_host_save_provider_catalog(const char* codex_home, const char* catalog_json);

// Skills management
const char* codex_ohos_host_skills_registry_json(const char* codex_home);
int32_t codex_ohos_host_save_skills_registry(const char* codex_home, const char* registry_json);
const char* codex_ohos_host_skills_repos_json(const char* codex_home);
int32_t codex_ohos_host_save_skills_repos(const char* codex_home, const char* repos_json);
const char* codex_ohos_host_compute_dir_hash(const char* dir_path);
const char* codex_ohos_host_skills_backups_json(const char* codex_home);
const char* codex_ohos_host_create_skill_backup(
    const char* codex_home,
    const char* skill_dir,
    const char* skill_json
);
int32_t codex_ohos_host_delete_skill_backup(const char* codex_home, const char* backup_id);

// Prompts management
const char* codex_ohos_host_prompts_registry_json(const char* codex_home);
int32_t codex_ohos_host_save_prompts_registry(const char* codex_home, const char* registry_json);
const char* codex_ohos_host_read_agents_md(const char* codex_home);
int32_t codex_ohos_host_write_agents_md(const char* codex_home, const char* content);
}

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

bool ReadOptionalUtf8(
    napi_env env,
    napi_value value,
    char* buffer,
    size_t capacity
) {
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
    const char* safe_value = value == nullptr ? "" : value;
    napi_create_string_utf8(env, safe_value, NAPI_AUTO_LENGTH, &result);
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

napi_value BuildStatusObject(napi_env env, int32_t code) {
    napi_value result = nullptr;
    napi_create_object(env, &result);

    napi_value running = CreateBoolean(env, codex_ohos_host_is_running() == 1);
    napi_value message = CreateUtf8String(env, codex_ohos_host_last_message());
    napi_value server_url = CreateUtf8String(env, codex_ohos_host_server_url());
    napi_value code_value = CreateInt32(env, code);

    napi_set_named_property(env, result, "running", running);
    napi_set_named_property(env, result, "message", message);
    napi_set_named_property(env, result, "serverUrl", server_url);
    napi_set_named_property(env, result, "code", code_value);
    return result;
}

napi_value StartHost(napi_env env, napi_callback_info info) {
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

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* server_url_ptr = server_url[0] == '\0' ? nullptr : server_url;
    int32_t code = codex_ohos_host_start(codex_home_ptr, server_url_ptr);
    return BuildStatusObject(env, code);
}

napi_value GetStatus(napi_env env, napi_callback_info info) {
    (void)info;
    return BuildStatusObject(env, 0);
}

napi_value IsHostRunning(napi_env env, napi_callback_info info) {
    (void)info;
    return CreateBoolean(env, codex_ohos_host_is_running() == 1);
}

napi_value GetLastMessage(napi_env env, napi_callback_info info) {
    (void)info;
    return CreateUtf8String(env, codex_ohos_host_last_message());
}

napi_value GetServerUrl(napi_env env, napi_callback_info info) {
    (void)info;
    return CreateUtf8String(env, codex_ohos_host_server_url());
}

napi_value GetProviderConfig(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_provider_config_json(codex_home_ptr));
}

napi_value SaveProviderConfig(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char base_url[MAX_URL_ARG_LEN];
    char api_key[MAX_API_KEY_ARG_LEN];
    char model[MAX_MODEL_ARG_LEN];
    codex_home[0] = '\0';
    base_url[0] = '\0';
    api_key[0] = '\0';
    model[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], base_url, sizeof(base_url))) {
        return nullptr;
    }
    if (argc >= 3 && !ReadOptionalUtf8(env, args[2], api_key, sizeof(api_key))) {
        return nullptr;
    }
    if (argc >= 4 && !ReadOptionalUtf8(env, args[3], model, sizeof(model))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* base_url_ptr = base_url[0] == '\0' ? nullptr : base_url;
    const char* api_key_ptr = api_key[0] == '\0' ? nullptr : api_key;
    const char* model_ptr = model[0] == '\0' ? nullptr : model;

    int32_t code = codex_ohos_host_save_provider_config(
        codex_home_ptr,
        base_url_ptr,
        api_key_ptr,
        model_ptr
    );
    if (code != 0) {
        napi_throw_error(env, nullptr, "Failed to save provider config.");
        return nullptr;
    }

    return CreateUtf8String(env, codex_ohos_host_provider_config_json(codex_home_ptr));
}

napi_value GetProviderCatalog(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_provider_catalog_json(codex_home_ptr));
}

napi_value SaveProviderCatalog(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char catalog_json[MAX_CATALOG_JSON_ARG_LEN];
    codex_home[0] = '\0';
    catalog_json[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], catalog_json, sizeof(catalog_json))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* catalog_json_ptr = catalog_json[0] == '\0' ? nullptr : catalog_json;
    int32_t code = codex_ohos_host_save_provider_catalog(codex_home_ptr, catalog_json_ptr);
    if (code != 0) {
        napi_throw_error(env, nullptr, "Failed to save provider catalog.");
        return nullptr;
    }

    return CreateUtf8String(env, codex_ohos_host_provider_catalog_json(codex_home_ptr));
}

napi_value GetSkillsRegistry(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_skills_registry_json(codex_home_ptr));
}

napi_value SaveSkillsRegistry(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char registry_json[MAX_REGISTRY_JSON_ARG_LEN];
    codex_home[0] = '\0';
    registry_json[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], registry_json, sizeof(registry_json))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* registry_json_ptr = registry_json[0] == '\0' ? nullptr : registry_json;
    int32_t code = codex_ohos_host_save_skills_registry(codex_home_ptr, registry_json_ptr);
    if (code != 0) {
        napi_throw_error(env, nullptr, "Failed to save skills registry.");
        return nullptr;
    }

    return CreateInt32(env, code);
}

napi_value GetSkillsRepos(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_skills_repos_json(codex_home_ptr));
}

napi_value SaveSkillsRepos(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char repos_json[MAX_REGISTRY_JSON_ARG_LEN];
    codex_home[0] = '\0';
    repos_json[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], repos_json, sizeof(repos_json))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* repos_json_ptr = repos_json[0] == '\0' ? nullptr : repos_json;
    int32_t code = codex_ohos_host_save_skills_repos(codex_home_ptr, repos_json_ptr);
    if (code != 0) {
        napi_throw_error(env, nullptr, "Failed to save skills repos.");
        return nullptr;
    }

    return CreateInt32(env, code);
}

napi_value ComputeDirHash(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char dir_path[MAX_DIR_PATH_ARG_LEN];
    dir_path[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], dir_path, sizeof(dir_path))) {
        return nullptr;
    }

    const char* dir_path_ptr = dir_path[0] == '\0' ? nullptr : dir_path;
    return CreateUtf8String(env, codex_ohos_host_compute_dir_hash(dir_path_ptr));
}

napi_value GetSkillsBackups(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_skills_backups_json(codex_home_ptr));
}

napi_value CreateSkillBackup(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char skill_dir[MAX_DIR_PATH_ARG_LEN];
    char skill_json[MAX_SKILL_JSON_ARG_LEN];
    codex_home[0] = '\0';
    skill_dir[0] = '\0';
    skill_json[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], skill_dir, sizeof(skill_dir))) {
        return nullptr;
    }
    if (argc >= 3 && !ReadOptionalUtf8(env, args[2], skill_json, sizeof(skill_json))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* skill_dir_ptr = skill_dir[0] == '\0' ? nullptr : skill_dir;
    const char* skill_json_ptr = skill_json[0] == '\0' ? nullptr : skill_json;

    return CreateUtf8String(
        env,
        codex_ohos_host_create_skill_backup(codex_home_ptr, skill_dir_ptr, skill_json_ptr)
    );
}

napi_value DeleteSkillBackup(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char backup_id[MAX_BACKUP_ID_ARG_LEN];
    codex_home[0] = '\0';
    backup_id[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], backup_id, sizeof(backup_id))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* backup_id_ptr = backup_id[0] == '\0' ? nullptr : backup_id;
    int32_t code = codex_ohos_host_delete_skill_backup(codex_home_ptr, backup_id_ptr);
    return CreateInt32(env, code);
}

// ── Prompts management ──

napi_value GetPromptsRegistry(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_prompts_registry_json(codex_home_ptr));
}

napi_value SavePromptsRegistry(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char registry_json[MAX_REGISTRY_JSON_ARG_LEN];
    codex_home[0] = '\0';
    registry_json[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], registry_json, sizeof(registry_json))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* registry_json_ptr = registry_json[0] == '\0' ? nullptr : registry_json;
    int32_t code = codex_ohos_host_save_prompts_registry(codex_home_ptr, registry_json_ptr);
    return CreateInt32(env, code);
}

napi_value ReadAgentsMd(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    codex_home[0] = '\0';
    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    return CreateUtf8String(env, codex_ohos_host_read_agents_md(codex_home_ptr));
}

napi_value WriteAgentsMd(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codex_home[MAX_HOME_ARG_LEN];
    char content[MAX_PROMPTS_CONTENT_ARG_LEN];
    codex_home[0] = '\0';
    content[0] = '\0';

    if (argc >= 1 && !ReadOptionalUtf8(env, args[0], codex_home, sizeof(codex_home))) {
        return nullptr;
    }
    if (argc >= 2 && !ReadOptionalUtf8(env, args[1], content, sizeof(content))) {
        return nullptr;
    }

    const char* codex_home_ptr = codex_home[0] == '\0' ? nullptr : codex_home;
    const char* content_ptr = content[0] == '\0' ? nullptr : content;
    int32_t code = codex_ohos_host_write_agents_md(codex_home_ptr, content_ptr);
    return CreateInt32(env, code);
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
        {"getPromptsRegistry", nullptr, GetPromptsRegistry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"savePromptsRegistry", nullptr, SavePromptsRegistry, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"readAgentsMd", nullptr, ReadAgentsMd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"writeAgentsMd", nullptr, WriteAgentsMd, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module codexHostModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "codexhost",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterCodexHostModule(void) {
    napi_module_register(&codexHostModule);
}
