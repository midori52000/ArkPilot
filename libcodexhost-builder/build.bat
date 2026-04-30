@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%") do set "BUILDER_DIR=%%~fI"
for %%I in ("%BUILDER_DIR%\..") do set "REPO_ROOT=%%~fI"

set "MODE=%~1"
set "ABI=%~2"
set "INSTALL_FLAG=%~3"
set "PREBUILT_STATIC_LIB=%PREBUILT_RUST_STATIC_LIB%"

if not defined MODE set "MODE=debug"
if not defined ABI set "ABI=x86_64"

if /I "%MODE%"=="--help" goto :help
if /I "%MODE%"=="-h" goto :help

if /I "%ABI%"=="arm64-v8a" (
  set "RUST_TARGET_TRIPLE=aarch64-unknown-linux-ohos"
) else if /I "%ABI%"=="x86_64" (
  set "RUST_TARGET_TRIPLE=x86_64-unknown-linux-ohos"
) else (
  echo [ERROR] Unsupported ABI: %ABI%
  goto :help
)

set "RUST_WORKSPACE=%REPO_ROOT%\codex-main\codex-rs"
set "BUILD_DIR=%BUILDER_DIR%\out\cmake\%ABI%\%MODE%"
set "OUTPUT_FILE=%BUILD_DIR%\staging\%ABI%\libcodexhost.so"
set "INSTALL_DIR=%REPO_ROOT%\Agent\entry\src\main\libs\%ABI%"
set "INSTALL_FILE=%INSTALL_DIR%\libcodexhost.so"

if /I not "%MODE%"=="debug" if /I not "%MODE%"=="release" (
  echo [ERROR] Unsupported build mode: %MODE%
  goto :help
)

if not exist "%RUST_WORKSPACE%\Cargo.toml" (
  echo [ERROR] Rust workspace not found:
  echo         %RUST_WORKSPACE%
  echo         Expected sibling directory: ..\codex-main\codex-rs
  exit /b 1
)

call :find_sdk_root
if errorlevel 1 exit /b 1

set "OHOS_NATIVE=%SDK_ROOT%\default\openharmony\native"
set "OHOS_CMAKE_BIN=%OHOS_NATIVE%\build-tools\cmake\bin"
set "CMAKE_CMD=%OHOS_CMAKE_BIN%\cmake.exe"

if not exist "%CMAKE_CMD%" (
  echo [ERROR] CMake not found:
  echo         %CMAKE_CMD%
  exit /b 1
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%" >nul 2>&1

echo ========================================
echo libcodexhost standalone build
echo ========================================
echo Builder: %BUILDER_DIR%
echo Rust workspace: %RUST_WORKSPACE%
echo ABI: %ABI%
echo Mode: %MODE%
if defined PREBUILT_STATIC_LIB echo Prebuilt Rust static lib: %PREBUILT_STATIC_LIB%
echo Output: %OUTPUT_FILE%
echo.

pushd "%BUILD_DIR%" >nul
"%CMAKE_CMD%" -G Ninja ^
  "-DCMAKE_BUILD_TYPE=%MODE%" ^
  "-DCMAKE_MAKE_PROGRAM=%OHOS_CMAKE_BIN%\ninja.exe" ^
  "-DCMAKE_TOOLCHAIN_FILE=%OHOS_NATIVE%\build\cmake\ohos.toolchain.cmake" ^
  "-DOHOS_ARCH=%ABI%" ^
  "-DOHOS_STL=c++_shared" ^
  "-DRUST_WORKSPACE_DIR=%RUST_WORKSPACE%" ^
  "-DPREBUILT_RUST_STATIC_LIB=%PREBUILT_STATIC_LIB%" ^
  "%BUILDER_DIR%"
if errorlevel 1 (
  popd >nul
  exit /b 1
)

"%CMAKE_CMD%" --build .
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
popd >nul
if not "%BUILD_EXIT_CODE%"=="0" exit /b %BUILD_EXIT_CODE%

if /I "%INSTALL_FLAG%"=="--install" (
  if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1
  copy /Y "%OUTPUT_FILE%" "%INSTALL_FILE%" >nul
  if errorlevel 1 exit /b 1
  echo [OK] Installed: %INSTALL_FILE%
)

echo [OK] Built: %OUTPUT_FILE%
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

:help
echo Usage:
echo   build.bat [debug^|release] [x86_64^|arm64-v8a] [--install]
echo.
echo Examples:
echo   build.bat debug x86_64
echo   build.bat debug x86_64 --install
echo   build.bat release arm64-v8a --install
exit /b 1
