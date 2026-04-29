@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MODE=%~1"

if not defined MODE set "MODE=debug"
if /I "%MODE%"=="--help" goto :help
if /I "%MODE%"=="-h" goto :help

call :find_project_root "%SCRIPT_DIR%"
if errorlevel 1 exit /b 1

for %%I in ("%PROJECT_DIR%\..") do set "REPO_ROOT=%%~fI"

call "%SCRIPT_DIR%\setup_env.bat"
if errorlevel 1 exit /b 1

set "SDK_ROOT=%DEVECO_SDK_HOME%"
if not defined SDK_ROOT (
  echo [ERROR] DEVECO_SDK_HOME is not set after setup.
  exit /b 1
)

set "OHOS_NATIVE=%SDK_ROOT%\default\openharmony\native"
set "HVIGOR_JS=%SDK_ROOT%\..\tools\hvigor\hvigor\bin\hvigor.js"
set "RUST_WORKSPACE=%REPO_ROOT%\codex-main\codex-rs"
for %%I in ("%RUST_WORKSPACE%") do set "RUST_WORKSPACE=%%~fI"

if not exist "%HVIGOR_JS%" (
  echo [ERROR] Hvigor entrypoint not found:
  echo         %HVIGOR_JS%
  exit /b 1
)

if not exist "%RUST_WORKSPACE%\Cargo.toml" (
  echo [ERROR] Rust workspace not found:
  echo         %RUST_WORKSPACE%
  echo         Expected sibling directory: ..\codex-main\codex-rs
  exit /b 1
)

set "PATH=%OHOS_NATIVE%\build-tools\cmake\bin;%OHOS_NATIVE%\llvm\bin;%PATH%"
set "DEVECO_SDK_HOME=%SDK_ROOT%"
set "OHOS_NATIVE=%OHOS_NATIVE%"
set "OHOS_SDK_NATIVE=%OHOS_NATIVE%"
set "OHOS_NDK_HOME=%OHOS_NATIVE%"
set "SDK_NATIVE=%OHOS_NATIVE%"

if /I "%MODE%"=="clean" goto :clean
if /I not "%MODE%"=="debug" if /I not "%MODE%"=="release" (
  echo [ERROR] Unsupported build mode: %MODE%
  goto :help
)

echo ========================================
echo ArkPilot Agent Windows Build
echo ========================================
echo Mode: %MODE%
echo DevEco SDK: %SDK_ROOT%
echo Rust workspace: %RUST_WORKSPACE%
echo.

node "%HVIGOR_JS%" --stop-daemon >nul 2>&1
if exist "%PROJECT_DIR%\.hvigor" rmdir /s /q "%PROJECT_DIR%\.hvigor"

if /I "%MODE%"=="release" (
  node "%HVIGOR_JS%" assembleHap --mode release
) else (
  node "%HVIGOR_JS%" assembleHap
)

if errorlevel 1 (
  echo.
  echo [ERROR] Build failed.
  exit /b 1
)

if /I "%MODE%"=="release" (
  set "OUTPUT_FILE=%PROJECT_DIR%\entry\build\default\outputs\default\entry-default-signed.hap"
) else (
  set "OUTPUT_FILE=%PROJECT_DIR%\entry\build\default\outputs\default\entry-default-unsigned.hap"
)

echo.
echo [OK] Build succeeded.
echo [OK] Output: %OUTPUT_FILE%
exit /b 0

:clean
echo ========================================
echo Cleaning ArkPilot Agent build artifacts
echo ========================================

node "%HVIGOR_JS%" --stop-daemon >nul 2>&1

if exist "%PROJECT_DIR%\.hvigor" rmdir /s /q "%PROJECT_DIR%\.hvigor"
if exist "%PROJECT_DIR%\entry\build" rmdir /s /q "%PROJECT_DIR%\entry\build"
if exist "%PROJECT_DIR%\entry\.cxx" rmdir /s /q "%PROJECT_DIR%\entry\.cxx"

echo [OK] Clean complete.
exit /b 0

:help
echo Usage:
echo   build.bat [debug^|release^|clean]
echo.
echo Examples:
echo   build.bat
echo   build.bat debug
echo   build.bat release
echo   build.bat clean
exit /b 1

:find_project_root
set "SEARCH_DIR=%~f1"
if not defined SEARCH_DIR set "SEARCH_DIR=%CD%"

:find_project_root_loop
if exist "%SEARCH_DIR%\oh-package.json5" if exist "%SEARCH_DIR%\entry\build-profile.json5" (
  set "PROJECT_DIR=%SEARCH_DIR%"
  exit /b 0
)

for %%I in ("%SEARCH_DIR%\..") do set "PARENT_DIR=%%~fI"
if /I "%PARENT_DIR%"=="%SEARCH_DIR%" (
  echo [ERROR] Failed to locate Agent project root from:
  echo         %~f1
  echo         Expected a directory containing oh-package.json5 and entry\build-profile.json5
  exit /b 1
)

set "SEARCH_DIR=%PARENT_DIR%"
goto :find_project_root_loop
