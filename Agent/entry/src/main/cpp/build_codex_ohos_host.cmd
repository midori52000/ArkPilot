@echo off
setlocal

set "RUST_WORKSPACE_DIR=%~1"
set "CARGO_TARGET_DIR=%~2"
set "RUST_PROFILE=%~3"
set "RUST_TARGET_TRIPLE=%~4"

set "OHOS_NATIVE=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native"
set "OHOS_CMAKE_BIN=%OHOS_NATIVE%\build-tools\cmake\bin"
set "OHOS_LLVM_BIN=%OHOS_NATIVE%\llvm\bin"
set "OHOS_TOOLCHAIN_FILE=%OHOS_NATIVE%\build\cmake\ohos.toolchain.cmake"
set "CARGO_CMD=%USERPROFILE%\.cargo\bin\cargo.exe"

if /I "%RUST_TARGET_TRIPLE%"=="aarch64-unknown-linux-ohos" (
  set "OHOS_CC=%RUST_WORKSPACE_DIR%\toolchains\ohos-aarch64-clang.cmd"
  set "TARGET_CC_VAR=CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER"
) else if /I "%RUST_TARGET_TRIPLE%"=="x86_64-unknown-linux-ohos" (
  set "OHOS_CC=%RUST_WORKSPACE_DIR%\toolchains\ohos-x86_64-clang.cmd"
  set "TARGET_CC_VAR=CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER"
) else (
  echo Unsupported Rust target triple: %RUST_TARGET_TRIPLE%
  exit /b 1
)

set "PATH=%OHOS_CMAKE_BIN%;%PATH%"
set "CMAKE=%OHOS_CMAKE_BIN%\cmake.exe"
set "CMAKE_GENERATOR=Ninja"
set "CMAKE_MAKE_PROGRAM=%OHOS_CMAKE_BIN%\ninja.exe"
set "CMAKE_GENERATOR_%RUST_TARGET_TRIPLE%=Ninja"
set "CMAKE_MAKE_PROGRAM_%RUST_TARGET_TRIPLE%=%OHOS_CMAKE_BIN%\ninja.exe"
set "CMAKE_TOOLCHAIN_FILE_%RUST_TARGET_TRIPLE%=%OHOS_TOOLCHAIN_FILE%"

call set "%TARGET_CC_VAR%=%OHOS_CC%"
set "CC=%OHOS_CC%"
set "TARGET_CC=%OHOS_CC%"
set "AR=%OHOS_LLVM_BIN%\llvm-ar.exe"
set "TARGET_AR=%OHOS_LLVM_BIN%\llvm-ar.exe"
set "RANLIB=%OHOS_LLVM_BIN%\llvm-ranlib.exe"

if /I "%RUST_TARGET_TRIPLE%"=="aarch64-unknown-linux-ohos" (
  set "CC_aarch64_unknown_linux_ohos=%OHOS_CC%"
  set "AR_aarch64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ar.exe"
  set "RANLIB_aarch64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ranlib.exe"
) else if /I "%RUST_TARGET_TRIPLE%"=="x86_64-unknown-linux-ohos" (
  set "CC_x86_64_unknown_linux_ohos=%OHOS_CC%"
  set "AR_x86_64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ar.exe"
  set "RANLIB_x86_64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ranlib.exe"
)

cd /D "%RUST_WORKSPACE_DIR%" || exit /b 1

if /I "%RUST_PROFILE%"=="release" (
  "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE% --release
) else (
  "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE%
)

exit /b %ERRORLEVEL%
