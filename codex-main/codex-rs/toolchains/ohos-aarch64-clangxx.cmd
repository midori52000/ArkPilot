@echo off
setlocal
call :resolve_ohos_native
if errorlevel 1 exit /b 1
"%OHOS_NATIVE_ROOT%\llvm\bin\clang++.exe" -target aarch64-linux-ohos --sysroot="%OHOS_NATIVE_ROOT%\sysroot" -D__MUSL__ %*
exit /b %ERRORLEVEL%

:resolve_ohos_native
set "OHOS_NATIVE_ROOT="
if defined OHOS_NATIVE set "OHOS_NATIVE_ROOT=%OHOS_NATIVE%"
if not defined OHOS_NATIVE_ROOT if defined OHOS_SDK_NATIVE set "OHOS_NATIVE_ROOT=%OHOS_SDK_NATIVE%"
if not defined OHOS_NATIVE_ROOT if defined OHOS_NDK_HOME set "OHOS_NATIVE_ROOT=%OHOS_NDK_HOME%"
if not defined OHOS_NATIVE_ROOT if defined SDK_NATIVE set "OHOS_NATIVE_ROOT=%SDK_NATIVE%"
if not defined OHOS_NATIVE_ROOT if defined DEVECO_SDK_HOME set "OHOS_NATIVE_ROOT=%DEVECO_SDK_HOME%\default\openharmony\native"
if not defined OHOS_NATIVE_ROOT set "OHOS_NATIVE_ROOT=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native"
if not exist "%OHOS_NATIVE_ROOT%\llvm\bin\clang++.exe" (
  echo [ERROR] OHOS clang++ not found:
  echo         %OHOS_NATIVE_ROOT%
  exit /b 1
)
exit /b 0
