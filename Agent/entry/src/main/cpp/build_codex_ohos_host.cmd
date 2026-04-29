@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "RUST_WORKSPACE_DIR=%~1"
set "CARGO_TARGET_DIR=%~2"
set "RUST_PROFILE=%~3"
set "RUST_TARGET_TRIPLE=%~4"

if not defined RUST_WORKSPACE_DIR (
  echo [ERROR] Missing RUST_WORKSPACE_DIR argument.
  exit /b 1
)
if not defined CARGO_TARGET_DIR (
  echo [ERROR] Missing CARGO_TARGET_DIR argument.
  exit /b 1
)
if not defined RUST_PROFILE set "RUST_PROFILE=debug"
if not defined RUST_TARGET_TRIPLE (
  echo [ERROR] Missing RUST_TARGET_TRIPLE argument.
  exit /b 1
)

call :find_sdk_root
if errorlevel 1 exit /b 1

set "OHOS_NATIVE=%SDK_ROOT%\default\openharmony\native"
set "OHOS_CMAKE_BIN=%OHOS_NATIVE%\build-tools\cmake\bin"
set "OHOS_LLVM_BIN=%OHOS_NATIVE%\llvm\bin"
set "OHOS_TOOLCHAIN_FILE=%OHOS_NATIVE%\build\cmake\ohos.toolchain.cmake"

if not exist "%OHOS_NATIVE%\llvm\bin\clang.exe" (
  echo [ERROR] Invalid OHOS native SDK path:
  echo         %OHOS_NATIVE%
  exit /b 1
)

call :find_cargo
if errorlevel 1 exit /b 1

if /I "%RUST_TARGET_TRIPLE%"=="aarch64-unknown-linux-ohos" (
  set "OHOS_CC=%RUST_WORKSPACE_DIR%\toolchains\ohos-aarch64-clang.cmd"
  set "OHOS_CXX=%RUST_WORKSPACE_DIR%\toolchains\ohos-aarch64-clangxx.cmd"
  set "TARGET_LINKER_VAR=CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER"
  set "TARGET_ENV_SUFFIX=aarch64_unknown_linux_ohos"
) else if /I "%RUST_TARGET_TRIPLE%"=="x86_64-unknown-linux-ohos" (
  set "OHOS_CC=%RUST_WORKSPACE_DIR%\toolchains\ohos-x86_64-clang.cmd"
  set "OHOS_CXX=%RUST_WORKSPACE_DIR%\toolchains\ohos-x86_64-clangxx.cmd"
  set "TARGET_LINKER_VAR=CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER"
  set "TARGET_ENV_SUFFIX=x86_64_unknown_linux_ohos"
) else (
  echo [ERROR] Unsupported Rust target triple:
  echo         %RUST_TARGET_TRIPLE%
  exit /b 1
)

if not exist "%OHOS_CC%" (
  echo [ERROR] Missing OHOS linker wrapper:
  echo         %OHOS_CC%
  exit /b 1
)

if not exist "%CARGO_TARGET_DIR%" mkdir "%CARGO_TARGET_DIR%" >nul 2>&1

set "DEVECO_SDK_HOME=%SDK_ROOT%"
set "OHOS_NATIVE=%OHOS_NATIVE%"
set "OHOS_SDK_NATIVE=%OHOS_NATIVE%"
set "OHOS_NDK_HOME=%OHOS_NATIVE%"
set "SDK_NATIVE=%OHOS_NATIVE%"
set "CARGO_TARGET_DIR=%CARGO_TARGET_DIR%"

set "PATH=%OHOS_CMAKE_BIN%;%PATH%"
set "CMAKE=%OHOS_CMAKE_BIN%\cmake.exe"
set "CMAKE_GENERATOR=Ninja"
set "CMAKE_MAKE_PROGRAM=%OHOS_CMAKE_BIN%\ninja.exe"

call set "CMAKE_GENERATOR_%RUST_TARGET_TRIPLE%=Ninja"
call set "CMAKE_MAKE_PROGRAM_%RUST_TARGET_TRIPLE%=%OHOS_CMAKE_BIN%\ninja.exe"
call set "CMAKE_TOOLCHAIN_FILE_%RUST_TARGET_TRIPLE%=%OHOS_TOOLCHAIN_FILE%"

set "CMAKE_GENERATOR_%TARGET_ENV_SUFFIX%=Ninja"
set "CMAKE_MAKE_PROGRAM_%TARGET_ENV_SUFFIX%=%OHOS_CMAKE_BIN%\ninja.exe"
set "CMAKE_TOOLCHAIN_FILE_%TARGET_ENV_SUFFIX%=%OHOS_TOOLCHAIN_FILE%"

call set "%TARGET_LINKER_VAR%=%OHOS_CC%"

set "CC="
set "CXX="
set "TARGET_CC="
set "TARGET_CXX="
set "AR="
set "TARGET_AR="
set "RANLIB="

set "CC_%TARGET_ENV_SUFFIX%=%OHOS_CC%"
set "CXX_%TARGET_ENV_SUFFIX%=%OHOS_CXX%"
set "AR_%TARGET_ENV_SUFFIX%=%OHOS_LLVM_BIN%\llvm-ar.exe"
set "RANLIB_%TARGET_ENV_SUFFIX%=%OHOS_LLVM_BIN%\llvm-ranlib.exe"

pushd "%RUST_WORKSPACE_DIR%" || exit /b 1

if /I "%RUST_PROFILE%"=="release" (
  "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE% --release
) else (
  "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE%
)

set "BUILD_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %BUILD_EXIT_CODE%

:find_sdk_root
set "SDK_ROOT="

if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\default\openharmony\native" (
  set "SDK_ROOT=%DEVECO_SDK_HOME%"
)

if not defined SDK_ROOT (
  for %%D in (
    "C:\Program Files\Huawei\DevEco Studio\sdk"
    "D:\develop\deveco\DevEco Studio\sdk"
  ) do (
    if not defined SDK_ROOT if exist "%%~D\default\openharmony\native" set "SDK_ROOT=%%~D"
  )
)

if not defined SDK_ROOT (
  echo [ERROR] DevEco SDK not found.
  echo         Set DEVECO_SDK_HOME to your DevEco Studio sdk directory.
  exit /b 1
)

exit /b 0

:find_cargo
set "CARGO_CMD="

if defined CARGO if exist "%CARGO%" (
  set "CARGO_CMD=%CARGO%"
)

if not defined CARGO_CMD if defined CARGO_HOME if exist "%CARGO_HOME%\bin\cargo.exe" (
  set "CARGO_CMD=%CARGO_HOME%\bin\cargo.exe"
)

if not defined CARGO_CMD if exist "%USERPROFILE%\.cargo\bin\cargo.exe" (
  set "CARGO_CMD=%USERPROFILE%\.cargo\bin\cargo.exe"
)

if not defined CARGO_CMD (
  for /f "delims=" %%I in ('where cargo 2^>nul') do if not defined CARGO_CMD set "CARGO_CMD=%%~fI"
)

if not defined CARGO_CMD (
  echo [ERROR] Cargo not found.
  echo         Checked CARGO, CARGO_HOME\bin\cargo.exe, %%USERPROFILE%%\.cargo\bin\cargo.exe, and PATH.
  exit /b 1
)

exit /b 0
