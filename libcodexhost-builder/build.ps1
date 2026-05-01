param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug',

    [ValidateSet('x86_64', 'arm64-v8a')]
    [string]$Abi = 'x86_64',

    [switch]$NoInstall,

    [string]$PrebuiltRustSharedLib = $env:PREBUILT_RUST_SHARED_LIB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ErrorAndExit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [int]$Code = 1
    )

    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit $Code
}

function Resolve-SdkRoot {
    $candidates = @()

    if ($env:DEVECO_SDK_HOME) {
        $candidates += $env:DEVECO_SDK_HOME
    }

    $candidates += @(
        'C:\Program Files\Huawei\DevEco Studio\sdk',
        'D:\develop\deveco\DevEco Studio\sdk',
        'D:\DevEco Studio\sdk'
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $nativeDir = Join-Path $candidate 'default\openharmony\native'
        if (Test-Path $nativeDir) {
            return (Resolve-Path $candidate).Path
        }
    }

    Write-ErrorAndExit 'DevEco SDK not found. Set DEVECO_SDK_HOME to your DevEco Studio sdk directory.'
}

function Resolve-Cargo {
    $candidates = @()

    if ($env:CARGO -and (Test-Path $env:CARGO)) {
        $candidates += $env:CARGO
    }

    if ($env:CARGO_HOME) {
        $cargoHomeCmd = Join-Path $env:CARGO_HOME 'bin\cargo.exe'
        if (Test-Path $cargoHomeCmd) {
            $candidates += $cargoHomeCmd
        }
    }

    $userCargoCmd = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
    if (Test-Path $userCargoCmd) {
        $candidates += $userCargoCmd
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    $cargoFromPath = Get-Command cargo -ErrorAction SilentlyContinue
    if ($cargoFromPath) {
        return $cargoFromPath.Source
    }

    Write-ErrorAndExit 'Cargo not found. Checked CARGO, CARGO_HOME, %USERPROFILE%\.cargo\bin, and PATH.'
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [hashtable]$Environment
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    $previousValues = @{}

    try {
        if ($Environment) {
            foreach ($key in $Environment.Keys) {
                $previousValues[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
                [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
            }
        }

        Write-Host "> $FilePath $($Arguments -join ' ')"
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorAndExit "Command failed with exit code ${LASTEXITCODE}: $FilePath"
        }
    }
    finally {
        if ($Environment) {
            foreach ($key in $Environment.Keys) {
                [Environment]::SetEnvironmentVariable($key, $previousValues[$key], 'Process')
            }
        }

        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$builderDir = (Resolve-Path $scriptDir).Path
$repoRoot = (Resolve-Path (Join-Path $builderDir '..')).Path

$rustTargetTriple = switch ($Abi) {
    'arm64-v8a' { 'aarch64-unknown-linux-ohos' }
    'x86_64' { 'x86_64-unknown-linux-ohos' }
    default { Write-ErrorAndExit "Unsupported ABI: $Abi" }
}

$targetEnvSuffix = switch ($Abi) {
    'arm64-v8a' { 'aarch64_unknown_linux_ohos' }
    'x86_64' { 'x86_64_unknown_linux_ohos' }
    default { Write-ErrorAndExit "Unsupported ABI: $Abi" }
}

$targetLinkerVar = switch ($Abi) {
    'arm64-v8a' { 'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER' }
    'x86_64' { 'CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER' }
    default { Write-ErrorAndExit "Unsupported ABI: $Abi" }
}

$rustWorkspace = Join-Path $repoRoot 'codex-main\codex-rs'
if (-not (Test-Path (Join-Path $rustWorkspace 'Cargo.toml'))) {
    Write-ErrorAndExit "Rust workspace not found: $rustWorkspace`nExpected sibling directory: ..\codex-main\codex-rs"
}

$sdkRoot = Resolve-SdkRoot
$env:DEVECO_SDK_HOME = $sdkRoot
$ohosNative = Join-Path $sdkRoot 'default\openharmony\native'
$ohosCmakeBin = Join-Path $ohosNative 'build-tools\cmake\bin'
$ohosLlvmBin = Join-Path $ohosNative 'llvm\bin'
$cargoCmd = Resolve-Cargo

if (-not (Test-Path (Join-Path $ohosLlvmBin 'clang.exe'))) {
    Write-ErrorAndExit "OHOS clang not found: $(Join-Path $ohosLlvmBin 'clang.exe')"
}

$rustTargetDir = Join-Path $builderDir 'out\rust-target'
$rustOutputFile = Join-Path $rustTargetDir (Join-Path $rustTargetTriple (Join-Path $Mode 'libcodex_ohos_host.so'))
$installDir = Join-Path $repoRoot (Join-Path 'Agent\entry\libs' $Abi)
$installFile = Join-Path $installDir 'libcodex_ohos_host.so'

$ohosCc = switch ($Abi) {
    'arm64-v8a' { Join-Path $rustWorkspace 'toolchains\ohos-aarch64-clang.cmd' }
    'x86_64' { Join-Path $rustWorkspace 'toolchains\ohos-x86_64-clang.cmd' }
}
$ohosCxx = switch ($Abi) {
    'arm64-v8a' { Join-Path $rustWorkspace 'toolchains\ohos-aarch64-clangxx.cmd' }
    'x86_64' { Join-Path $rustWorkspace 'toolchains\ohos-x86_64-clangxx.cmd' }
}

if (-not [string]::IsNullOrWhiteSpace($PrebuiltRustSharedLib)) {
    $PrebuiltRustSharedLib = (Resolve-Path $PrebuiltRustSharedLib).Path
    if (-not (Test-Path $PrebuiltRustSharedLib)) {
        Write-ErrorAndExit "Prebuilt Rust shared lib does not exist: $PrebuiltRustSharedLib"
    }
}
else {
    if (-not (Test-Path $ohosCc)) {
        Write-ErrorAndExit "Missing OHOS linker wrapper: $ohosCc"
    }
    if (-not (Test-Path $ohosCxx)) {
        Write-ErrorAndExit "Missing OHOS linker wrapper: $ohosCxx"
    }
}

New-Item -ItemType Directory -Force -Path $rustTargetDir | Out-Null

Write-Host '========================================'
Write-Host 'libcodexhost standalone build'
Write-Host '========================================'
Write-Host "Builder: $builderDir"
Write-Host "Rust workspace: $rustWorkspace"
Write-Host "SDK root: $sdkRoot"
Write-Host "ABI: $Abi"
Write-Host "Mode: $Mode"
Write-Host "Cargo: $cargoCmd"
if (-not [string]::IsNullOrWhiteSpace($PrebuiltRustSharedLib)) {
    Write-Host "Prebuilt Rust shared lib: $PrebuiltRustSharedLib"
}
else {
    Write-Host "Rust output: $rustOutputFile"
}
if ($NoInstall) {
    Write-Host 'Install target: disabled'
}
else {
    Write-Host "Install target: $installFile"
}
Write-Host ''

$effectiveRustSharedLib = $PrebuiltRustSharedLib

if ([string]::IsNullOrWhiteSpace($effectiveRustSharedLib)) {
    $cargoEnvironment = @{
        'DEVECO_SDK_HOME' = $sdkRoot
        'OHOS_NATIVE' = $ohosNative
        'OHOS_SDK_NATIVE' = $ohosNative
        'OHOS_NDK_HOME' = $ohosNative
        'SDK_NATIVE' = $ohosNative
        'CARGO_TARGET_DIR' = $rustTargetDir
        'PATH' = "$ohosCmakeBin;$([Environment]::GetEnvironmentVariable('PATH', 'Process'))"
        'CC' = ''
        'CXX' = ''
        'TARGET_CC' = ''
        'TARGET_CXX' = ''
        'AR' = ''
        'TARGET_AR' = ''
        'RANLIB' = ''
    }

    $cargoEnvironment[$targetLinkerVar] = $ohosCc
    $cargoEnvironment["CC_$targetEnvSuffix"] = $ohosCc
    $cargoEnvironment["CXX_$targetEnvSuffix"] = $ohosCxx
    $cargoEnvironment["AR_$targetEnvSuffix"] = (Join-Path $ohosLlvmBin 'llvm-ar.exe')
    $cargoEnvironment["RANLIB_$targetEnvSuffix"] = (Join-Path $ohosLlvmBin 'llvm-ranlib.exe')
    $cargoEnvironment["CMAKE_GENERATOR_$rustTargetTriple"] = 'Ninja'
    $cargoEnvironment["CMAKE_MAKE_PROGRAM_$rustTargetTriple"] = (Join-Path $ohosCmakeBin 'ninja.exe')
    $cargoEnvironment["CMAKE_TOOLCHAIN_FILE_$rustTargetTriple"] = (Join-Path $ohosNative 'build\cmake\ohos.toolchain.cmake')
    $cargoEnvironment["CMAKE_GENERATOR_$targetEnvSuffix"] = 'Ninja'
    $cargoEnvironment["CMAKE_MAKE_PROGRAM_$targetEnvSuffix"] = (Join-Path $ohosCmakeBin 'ninja.exe')
    $cargoEnvironment["CMAKE_TOOLCHAIN_FILE_$targetEnvSuffix"] = (Join-Path $ohosNative 'build\cmake\ohos.toolchain.cmake')
    $cargoEnvironment['CMAKE'] = (Join-Path $ohosCmakeBin 'cmake.exe')
    $cargoEnvironment['CMAKE_GENERATOR'] = 'Ninja'
    $cargoEnvironment['CMAKE_MAKE_PROGRAM'] = (Join-Path $ohosCmakeBin 'ninja.exe')

    $cargoArgs = @('build', '--package', 'codex-ohos-host', '--target', $rustTargetTriple)
    if ($Mode -eq 'release') {
        $cargoArgs += '--release'
    }

    Invoke-External -FilePath $cargoCmd -Arguments $cargoArgs -WorkingDirectory $rustWorkspace -Environment $cargoEnvironment

    if (-not (Test-Path $rustOutputFile)) {
        Write-ErrorAndExit "Rust build finished but output file was not found: $rustOutputFile"
    }

    $effectiveRustSharedLib = $rustOutputFile
}

if (-not $NoInstall) {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item -Path $effectiveRustSharedLib -Destination $installFile -Force
    Write-Host "[OK] Installed: $installFile" -ForegroundColor Green
}

Write-Host "[OK] Built: $effectiveRustSharedLib" -ForegroundColor Green
