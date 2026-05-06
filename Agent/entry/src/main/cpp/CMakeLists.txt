cmake_minimum_required(VERSION 3.5.0)
project(entry)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(RUST_BRIDGE_LIB_NAME libcodex_ohos_host.so)
set(RUST_BRIDGE_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH})
set(RUST_BRIDGE_LIB_PATH ${RUST_BRIDGE_LIB_DIR}/${RUST_BRIDGE_LIB_NAME})

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(entry SHARED napi_init.cpp)
# Avoid emitting libentry.so directly to hvigor's final native-lib directory.
# If source and destination are identical, some hvigor versions try to copy the
# file onto itself and fail the build on Windows.
set_target_properties(entry PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/native-lib
)

if(EXISTS ${RUST_BRIDGE_LIB_PATH})
    target_link_directories(entry PUBLIC ${RUST_BRIDGE_LIB_DIR})
    target_link_libraries(entry PUBLIC ${RUST_BRIDGE_LIB_NAME})
endif()

target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libc++.a
    libhilog_ndk.z.so
    libdl.so
)
