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

call "%SCRIPT_DIR%\setup_env.bat" --quiet
if errorlevel 1 exit /b 1

if /I "%MODE%"=="clean" goto :clean
if /I not "%MODE%"=="debug" (
  echo [ERROR] Unsupported build mode: %MODE%
  echo         This portable script only supports unsigned debug HAP builds.
  goto :help
)

set "SDK_ROOT=%DEVECO_SDK_HOME%"
set "DEVECO_NODE_HOME=%DEVECO_NODE_HOME%"
set "HVIGOR_CMD=%DEVECO_HVIGOR_CMD%"
set "OHOS_NATIVE=%SDK_ROOT%\default\openharmony\native"
set "OUTPUT_FILE=%PROJECT_DIR%\entry\build\default\outputs\default\entry-default-unsigned.hap"
set "PREBUILT_LIB_DIR=%PROJECT_DIR%\entry\src\main\libs\x86_64"
set "PREBUILT_LIB=%PREBUILT_LIB_DIR%\libcodexhost.so"
set "REPACK_SCRIPT=%PROJECT_DIR%\script\helpsetup\repack_hap_with_native.js"

if not defined SDK_ROOT (
  echo [ERROR] DEVECO_SDK_HOME is not set after setup.
  exit /b 1
)

if not exist "%DEVECO_NODE_HOME%\node.exe" (
  echo [ERROR] DevEco bundled node.exe not found:
  echo         %DEVECO_NODE_HOME%\node.exe
  exit /b 1
)

if not exist "%HVIGOR_CMD%" (
  echo [ERROR] Hvigor wrapper not found:
  echo         %HVIGOR_CMD%
  exit /b 1
)

if not exist "%PREBUILT_LIB%" (
  echo [ERROR] Prebuilt native library not found:
  echo         %PREBUILT_LIB%
  echo         Build it first with:
  echo         ..\libcodexhost-builder\build.bat debug x86_64 --install
  exit /b 1
)

set "PATH=%OHOS_NATIVE%\build-tools\cmake\bin;%OHOS_NATIVE%\llvm\bin;%PATH%"
set "DEVECO_SDK_HOME=%SDK_ROOT%"
set "OHOS_NATIVE=%OHOS_NATIVE%"
set "OHOS_SDK_NATIVE=%OHOS_NATIVE%"
set "OHOS_NDK_HOME=%OHOS_NATIVE%"
set "SDK_NATIVE=%OHOS_NATIVE%"
set "NODE_HOME=%DEVECO_NODE_HOME%"

echo ========================================
echo ArkPilot Agent Debug HAP Build
echo ========================================
echo Project: %PROJECT_DIR%
echo DevEco SDK: %SDK_ROOT%
echo Native library: %PREBUILT_LIB%
echo Output: %OUTPUT_FILE%
echo.

call "%HVIGOR_CMD%" --stop-daemon >nul 2>&1
if exist "%PROJECT_DIR%\.hvigor" rmdir /s /q "%PROJECT_DIR%\.hvigor"

pushd "%PROJECT_DIR%" >nul
call "%HVIGOR_CMD%" assembleHap
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
popd >nul

if not "%BUILD_EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] Build failed.
  exit /b %BUILD_EXIT_CODE%
)

call "%DEVECO_NODE_HOME%\node.exe" "%REPACK_SCRIPT%" "%PROJECT_DIR%"
if errorlevel 1 (
  echo.
  echo [ERROR] HAP repack with native library failed.
  exit /b 1
)

echo.
echo [OK] Build succeeded.
echo [OK] Output: %OUTPUT_FILE%
exit /b 0

:clean
echo ========================================
echo Cleaning ArkPilot Agent build artifacts
echo ========================================

set "NODE_HOME=%DEVECO_NODE_HOME%"

call "%DEVECO_HVIGOR_CMD%" --stop-daemon >nul 2>&1

if exist "%PROJECT_DIR%\.hvigor" rmdir /s /q "%PROJECT_DIR%\.hvigor"
if exist "%PROJECT_DIR%\entry\build" rmdir /s /q "%PROJECT_DIR%\entry\build"
if exist "%PROJECT_DIR%\entry\.cxx" rmdir /s /q "%PROJECT_DIR%\entry\.cxx"
if exist "%PROJECT_DIR%\.cargo-target" rmdir /s /q "%PROJECT_DIR%\.cargo-target"

echo [OK] Clean complete.
exit /b 0

:help
echo Usage:
echo   build.bat [debug^|clean]
echo.
echo Examples:
echo   build.bat
echo   build.bat debug
echo   build.bat clean
echo.
echo This script builds an unsigned debug HAP.
echo Signed packages and IDE-run signing are intentionally left to local DevEco configuration.
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
