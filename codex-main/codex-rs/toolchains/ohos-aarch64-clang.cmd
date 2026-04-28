@echo off
setlocal
set "OHOS_NATIVE=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native"
"%OHOS_NATIVE%\llvm\bin\clang.exe" -target aarch64-linux-ohos --sysroot="%OHOS_NATIVE%\sysroot" -D__MUSL__ %*
