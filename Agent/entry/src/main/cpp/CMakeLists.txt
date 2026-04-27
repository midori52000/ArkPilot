# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(codexhost)

set(NATIVE_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVE_ROOT_PATH})

find_program(CARGO_EXECUTABLE cargo REQUIRED)

get_filename_component(
    RUST_WORKSPACE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../codex-main/codex-rs"
    ABSOLUTE
)
get_filename_component(
    AGENT_ROOT_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../.."
    ABSOLUTE
)
set(RUST_TARGET_TRIPLE "aarch64-unknown-linux-ohos")
set(RUST_TARGET_DIR "${AGENT_ROOT_DIR}/.cargo-target/codex-ohos-host")
set(OHOS_LLVM_BIN_DIR "C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native/llvm/bin")
set(OHOS_CMAKE_BIN_DIR "C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native/build-tools/cmake/bin")
set(RUST_BUILD_SCRIPT "${NATIVE_ROOT_PATH}/build_codex_ohos_host.cmd")

string(TOLOWER "${CMAKE_BUILD_TYPE}" CMAKE_BUILD_TYPE_LOWER)
if(CMAKE_BUILD_TYPE_LOWER STREQUAL "release")
    set(RUST_PROFILE_DIR "release")
else()
    set(RUST_PROFILE_DIR "debug")
endif()

set(RUST_STATIC_LIB
    "${RUST_TARGET_DIR}/${RUST_TARGET_TRIPLE}/${RUST_PROFILE_DIR}/libcodex_ohos_host.a"
)

add_custom_command(
    OUTPUT "${RUST_STATIC_LIB}"
    COMMAND cmd /c "${RUST_BUILD_SCRIPT}" "${RUST_WORKSPACE_DIR}" "${RUST_TARGET_DIR}" "${RUST_PROFILE_DIR}"
    WORKING_DIRECTORY "${RUST_WORKSPACE_DIR}"
    DEPENDS
        "${RUST_WORKSPACE_DIR}/Cargo.toml"
        "${RUST_WORKSPACE_DIR}/.cargo/config.toml"
        "${RUST_WORKSPACE_DIR}/ohos-host/Cargo.toml"
        "${RUST_WORKSPACE_DIR}/ohos-host/src/lib.rs"
        "${RUST_WORKSPACE_DIR}/core/src/tools/runtimes/apply_patch.rs"
        "${RUST_BUILD_SCRIPT}"
    COMMENT "Building embedded codex-ohos-host (${RUST_PROFILE_DIR})"
    VERBATIM
    USES_TERMINAL
)

add_custom_target(codex_ohos_host_build ALL DEPENDS "${RUST_STATIC_LIB}")

add_library(codex_ohos_host STATIC IMPORTED GLOBAL)
set_target_properties(
    codex_ohos_host
    PROPERTIES IMPORTED_LOCATION "${RUST_STATIC_LIB}"
)
add_dependencies(codex_ohos_host codex_ohos_host_build)

add_library(codexhost SHARED napi_init.cpp)
add_dependencies(codexhost codex_ohos_host_build)
set(CODEXHOST_STAGE_DIR "${CMAKE_BINARY_DIR}/staging/arm64-v8a")
set_target_properties(
    codexhost
    PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CODEXHOST_STAGE_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${CODEXHOST_STAGE_DIR}"
)
target_link_libraries(
    codexhost
    PUBLIC
    codex_ohos_host
    libace_napi.z.so
    z
    time_service_ndk
)
