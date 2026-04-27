@echo off
setlocal

set "RUST_WORKSPACE_DIR=%~1"
set "CARGO_TARGET_DIR=%~2"
set "RUST_PROFILE=%~3"

set "OHOS_NATIVE=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native"
set "OHOS_CMAKE_BIN=%OHOS_NATIVE%\build-tools\cmake\bin"
set "OHOS_LLVM_BIN=%OHOS_NATIVE%\llvm\bin"
set "OHOS_TOOLCHAIN_FILE=%OHOS_NATIVE%\build\cmake\ohos.toolchain.cmake"
set "OHOS_CC=%RUST_WORKSPACE_DIR%\toolchains\ohos-aarch64-clang.cmd"
set "CARGO_CMD=%USERPROFILE%\.cargo\bin\cargo.exe"

set "PATH=%OHOS_CMAKE_BIN%;%PATH%"
set "CMAKE=%OHOS_CMAKE_BIN%\cmake.exe"
set "CMAKE_GENERATOR=Ninja"
set "CMAKE_GENERATOR_aarch64_unknown_linux_ohos=Ninja"
set "CMAKE_MAKE_PROGRAM=%OHOS_CMAKE_BIN%\ninja.exe"
set "CMAKE_MAKE_PROGRAM_aarch64_unknown_linux_ohos=%OHOS_CMAKE_BIN%\ninja.exe"
set "CMAKE_TOOLCHAIN_FILE_aarch64_unknown_linux_ohos=%OHOS_TOOLCHAIN_FILE%"

set "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=%OHOS_CC%"
set "CC=%OHOS_CC%"
set "TARGET_CC=%OHOS_CC%"
set "CC_aarch64_unknown_linux_ohos=%OHOS_CC%"
set "AR=%OHOS_LLVM_BIN%\llvm-ar.exe"
set "TARGET_AR=%OHOS_LLVM_BIN%\llvm-ar.exe"
set "AR_aarch64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ar.exe"
set "RANLIB=%OHOS_LLVM_BIN%\llvm-ranlib.exe"
set "RANLIB_aarch64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ranlib.exe"

cd /D "%RUST_WORKSPACE_DIR%" || exit /b 1

if /I "%RUST_PROFILE%"=="release" (
  "%CARGO_CMD%" build --package codex-ohos-host --target aarch64-unknown-linux-ohos --release
) else (
  "%CARGO_CMD%" build --package codex-ohos-host --target aarch64-unknown-linux-ohos
)

exit /b %ERRORLEVEL%
