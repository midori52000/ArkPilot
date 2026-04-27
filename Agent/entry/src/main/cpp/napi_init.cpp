#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "napi/native_api.h"

extern "C" {
int32_t codex_ohos_host_start(const char* codex_home, const char* listen_url);
int32_t codex_ohos_host_is_running(void);
const char* codex_ohos_host_last_message(void);
const char* codex_ohos_host_server_url(void);
}

namespace {
constexpr size_t MAX_HOME_ARG_LEN = 4096;
constexpr size_t MAX_URL_ARG_LEN = 1024;

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
}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startHost", nullptr, StartHost, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isHostRunning", nullptr, IsHostRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLastMessage", nullptr, GetLastMessage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getServerUrl", nullptr, GetServerUrl, nullptr, nullptr, nullptr, napi_default, nullptr},
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
