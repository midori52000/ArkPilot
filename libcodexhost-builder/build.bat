@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%") do set "BUILDER_DIR=%%~fI"
for %%I in ("%BUILDER_DIR%\..") do set "REPO_ROOT=%%~fI"

set "MODE=%~1"
set "ABI=%~2"
set "INSTALL_FLAG=%~3"
set "PREBUILT_SHARED_LIB=%PREBUILT_RUST_SHARED_LIB%"
set "AUTO_INSTALL=1"

if not defined MODE set "MODE=debug"
if not defined ABI set "ABI=x86_64"

if /I "%MODE%"=="--help" goto :help
if /I "%MODE%"=="-h" goto :help
if /I "%INSTALL_FLAG%"=="--no-install" set "AUTO_INSTALL=0"

if /I "%ABI%"=="arm64-v8a" (
  set "RUST_TARGET_TRIPLE=aarch64-unknown-linux-ohos"
  set "TARGET_ENV_SUFFIX=aarch64_unknown_linux_ohos"
  set "TARGET_LINKER_VAR=CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER"
  set "OHOS_CC=%REPO_ROOT%\codex-main\codex-rs\toolchains\ohos-aarch64-clang.cmd"
  set "OHOS_CXX=%REPO_ROOT%\codex-main\codex-rs\toolchains\ohos-aarch64-clangxx.cmd"
) else if /I "%ABI%"=="x86_64" (
  set "RUST_TARGET_TRIPLE=x86_64-unknown-linux-ohos"
  set "TARGET_ENV_SUFFIX=x86_64_unknown_linux_ohos"
  set "TARGET_LINKER_VAR=CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER"
  set "OHOS_CC=%REPO_ROOT%\codex-main\codex-rs\toolchains\ohos-x86_64-clang.cmd"
  set "OHOS_CXX=%REPO_ROOT%\codex-main\codex-rs\toolchains\ohos-x86_64-clangxx.cmd"
) else (
  echo [ERROR] Unsupported ABI: %ABI%
  goto :help
)

if /I not "%MODE%"=="debug" if /I not "%MODE%"=="release" (
  echo [ERROR] Unsupported build mode: %MODE%
  goto :help
)

set "RUST_WORKSPACE=%REPO_ROOT%\codex-main\codex-rs"
set "RUST_TARGET_DIR=%BUILDER_DIR%\out\rust-target"
set "RUST_OUTPUT_FILE=%RUST_TARGET_DIR%\%RUST_TARGET_TRIPLE%\%MODE%\libcodex_ohos_host.so"
set "INSTALL_DIR=%REPO_ROOT%\Agent\entry\libs\%ABI%"
set "INSTALL_FILE=%INSTALL_DIR%\libcodex_ohos_host.so"

if not exist "%RUST_WORKSPACE%\Cargo.toml" (
  echo [ERROR] Rust workspace not found:
  echo         %RUST_WORKSPACE%
  echo         Expected sibling directory: ..\codex-main\codex-rs
  exit /b 1
)

call :find_sdk_root
if errorlevel 1 exit /b 1

set "DEVECO_SDK_HOME=%SDK_ROOT%"
set "OHOS_NATIVE=%SDK_ROOT%\default\openharmony\native"
set "OHOS_SDK_NATIVE=%OHOS_NATIVE%"
set "OHOS_NDK_HOME=%OHOS_NATIVE%"
set "SDK_NATIVE=%OHOS_NATIVE%"
set "OHOS_CMAKE_BIN=%OHOS_NATIVE%\build-tools\cmake\bin"
set "OHOS_LLVM_BIN=%OHOS_NATIVE%\llvm\bin"
set "CMAKE_CMD=%OHOS_CMAKE_BIN%\cmake.exe"
set "NINJA_CMD=%OHOS_CMAKE_BIN%\ninja.exe"

if not exist "%OHOS_LLVM_BIN%\clang.exe" (
  echo [ERROR] OHOS clang not found:
  echo         %OHOS_LLVM_BIN%\clang.exe
  exit /b 1
)

if not defined PREBUILT_SHARED_LIB (
  if not exist "%OHOS_CC%" (
    echo [ERROR] Missing OHOS linker wrapper:
    echo         %OHOS_CC%
    exit /b 1
  )
  if not exist "%OHOS_CXX%" (
    echo [ERROR] Missing OHOS linker wrapper:
    echo         %OHOS_CXX%
    exit /b 1
  )
)

call :find_cargo
if errorlevel 1 exit /b 1

if not exist "%RUST_TARGET_DIR%" mkdir "%RUST_TARGET_DIR%" >nul 2>&1

set "PATH=%OHOS_CMAKE_BIN%;%PATH%"
set "CMAKE=%CMAKE_CMD%"
set "CMAKE_GENERATOR=Ninja"
set "CMAKE_MAKE_PROGRAM=%NINJA_CMD%"
call set "CMAKE_GENERATOR_%RUST_TARGET_TRIPLE%=Ninja"
call set "CMAKE_MAKE_PROGRAM_%RUST_TARGET_TRIPLE%=%NINJA_CMD%"
call set "CMAKE_TOOLCHAIN_FILE_%RUST_TARGET_TRIPLE%=%OHOS_NATIVE%\build\cmake\ohos.toolchain.cmake"
set "CMAKE_GENERATOR_%TARGET_ENV_SUFFIX%=Ninja"
set "CMAKE_MAKE_PROGRAM_%TARGET_ENV_SUFFIX%=%NINJA_CMD%"
set "CMAKE_TOOLCHAIN_FILE_%TARGET_ENV_SUFFIX%=%OHOS_NATIVE%\build\cmake\ohos.toolchain.cmake"
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
set "CARGO_TARGET_DIR=%RUST_TARGET_DIR%"

if defined PREBUILT_SHARED_LIB if not exist "%PREBUILT_SHARED_LIB%" (
  echo [ERROR] Prebuilt Rust shared lib does not exist:
  echo         %PREBUILT_SHARED_LIB%
  exit /b 1
)

set "EFFECTIVE_SHARED_LIB=%PREBUILT_SHARED_LIB%"

echo ========================================
echo libcodexhost standalone build
echo ========================================
echo Builder: %BUILDER_DIR%
echo Rust workspace: %RUST_WORKSPACE%
echo SDK root: %SDK_ROOT%
echo ABI: %ABI%
echo Mode: %MODE%
echo Cargo: %CARGO_CMD%
if defined PREBUILT_SHARED_LIB (
  echo Prebuilt Rust shared lib: %PREBUILT_SHARED_LIB%
) else (
  echo Rust output: %RUST_OUTPUT_FILE%
)
if "%AUTO_INSTALL%"=="1" (
  echo Install target: %INSTALL_FILE%
) else (
  echo Install target: disabled
)
echo.

if not defined PREBUILT_SHARED_LIB (
  pushd "%RUST_WORKSPACE%" >nul
  if /I "%MODE%"=="release" (
    echo ^> %CARGO_CMD% build --package codex-ohos-host --target %RUST_TARGET_TRIPLE% --release
    "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE% --release
  ) else (
    echo ^> %CARGO_CMD% build --package codex-ohos-host --target %RUST_TARGET_TRIPLE%
    "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE%
  )
  set "BUILD_EXIT_CODE=%ERRORLEVEL%"
  popd >nul
  if not "%BUILD_EXIT_CODE%"=="0" exit /b %BUILD_EXIT_CODE%

  if not exist "%RUST_OUTPUT_FILE%" (
    echo [ERROR] Rust build finished but output file was not found:
    echo         %RUST_OUTPUT_FILE%
    exit /b 1
  )

  set "EFFECTIVE_SHARED_LIB=%RUST_OUTPUT_FILE%"
)

if "%AUTO_INSTALL%"=="1" (
  if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1
  copy /Y "%EFFECTIVE_SHARED_LIB%" "%INSTALL_FILE%" >nul
  if errorlevel 1 exit /b 1
  echo [OK] Installed: %INSTALL_FILE%
)

echo [OK] Built: %EFFECTIVE_SHARED_LIB%
exit /b 0

:find_sdk_root
set "SDK_ROOT="

if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\default\openharmony\native" (
  set "SDK_ROOT=%DEVECO_SDK_HOME%"
)

if not defined SDK_ROOT (
  for %%D in (
    "C:\Program Files\Huawei\DevEco Studio\sdk"
    "D:\develop\deveco\DevEco Studio\sdk"
    "D:\DevEco Studio\sdk"
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

:help
echo Usage:
echo   build.bat [debug^|release] [x86_64^|arm64-v8a] [--no-install]
echo.
echo Examples:
echo   build.bat debug x86_64
echo   build.bat debug x86_64 --no-install
echo   build.bat release arm64-v8a
exit /b 1
