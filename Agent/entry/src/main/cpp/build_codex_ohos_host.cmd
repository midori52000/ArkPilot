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
set "OHOS_NDK_HOME=%OHOS_NATIVE%"
set "OHOS_SDK_NATIVE=%OHOS_NATIVE%"
set "SDK_NATIVE=%OHOS_NATIVE%"
set "CARGO_CMD="

if defined CARGO (
  set "CARGO_CMD=%CARGO%"
)

if not defined CARGO_CMD if defined CARGO_HOME (
  if exist "%CARGO_HOME%\bin\cargo.exe" (
    set "CARGO_CMD=%CARGO_HOME%\bin\cargo.exe"
  )
)

if not defined CARGO_CMD if exist "%USERPROFILE%\.cargo\bin\cargo.exe" (
  set "CARGO_CMD=%USERPROFILE%\.cargo\bin\cargo.exe"
)

if not defined CARGO_CMD (
  for /f "delims=" %%I in ('where cargo 2^>nul') do if not defined CARGO_CMD set "CARGO_CMD=%%I"
)

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
set "CC="
set "TARGET_CC="
set "AR="
set "TARGET_AR="
set "RANLIB="

if not defined CARGO_CMD (
  echo cargo.exe was not found. Set CARGO, CARGO_HOME, or add cargo to PATH.
  exit /b 1
)

if not exist "%CARGO_CMD%" (
  echo cargo.exe does not exist: %CARGO_CMD%
  exit /b 1
)

if /I "%RUST_TARGET_TRIPLE%"=="aarch64-unknown-linux-ohos" (
  set "CC_aarch64_unknown_linux_ohos=%OHOS_CC%"
  set "AR_aarch64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ar.exe"
  set "RANLIB_aarch64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ranlib.exe"
  set "CMAKE_GENERATOR_aarch64_unknown_linux_ohos=Ninja"
  set "CMAKE_MAKE_PROGRAM_aarch64_unknown_linux_ohos=%OHOS_CMAKE_BIN%\ninja.exe"
  set "CMAKE_TOOLCHAIN_FILE_aarch64_unknown_linux_ohos=%OHOS_TOOLCHAIN_FILE%"
) else if /I "%RUST_TARGET_TRIPLE%"=="x86_64-unknown-linux-ohos" (
  set "CC_x86_64_unknown_linux_ohos=%OHOS_CC%"
  set "AR_x86_64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ar.exe"
  set "RANLIB_x86_64_unknown_linux_ohos=%OHOS_LLVM_BIN%\llvm-ranlib.exe"
  set "CMAKE_GENERATOR_x86_64_unknown_linux_ohos=Ninja"
  set "CMAKE_MAKE_PROGRAM_x86_64_unknown_linux_ohos=%OHOS_CMAKE_BIN%\ninja.exe"
  set "CMAKE_TOOLCHAIN_FILE_x86_64_unknown_linux_ohos=%OHOS_TOOLCHAIN_FILE%"
)

cd /D "%RUST_WORKSPACE_DIR%" || exit /b 1

if /I "%RUST_PROFILE%"=="release" (
  "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE% --release
) else (
  "%CARGO_CMD%" build --package codex-ohos-host --target %RUST_TARGET_TRIPLE%
)

exit /b %ERRORLEVEL%
