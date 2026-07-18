param(
    [string]$ProjectRoot,
    [ValidateSet('Validate','RuntimePublish')][string]$Mode = 'RuntimePublish'
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$lockPath = Join-Path $ProjectRoot 'config\build\runtime-toolchain.lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:Cf7RuntimeBuildErrors = @()

# 不允许调用者注入编译器/链接器参数。正式构建需要唯一、可审计的输入环境。
foreach ($name in @(
    'CL', '_CL_', 'LINK', '_LINK_', 'INCLUDE', 'LIB', 'LIBPATH',
    'RUSTFLAGS', 'RUSTDOCFLAGS', 'CARGO_ENCODED_RUSTFLAGS',
    'CARGO_ENCODED_RUSTDOCFLAGS', 'CARGO_BUILD_RUSTC', 'CARGO_BUILD_RUSTC_WRAPPER',
    'CARGO_BUILD_RUSTFLAGS', 'CARGO_BUILD_TARGET', 'CARGO_TARGET_DIR', 'RUSTC',
    'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER',
    'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER', 'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS',
    'MSBuildSDKsPath', 'MSBUILD_EXE_PATH', 'DOTNET_HOST_PATH', 'DOTNET_ROLL_FORWARD',
    'DOTNET_ROLL_FORWARD_TO_PRERELEASE', 'DOTNET_MULTILEVEL_LOOKUP'
)) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
$buildTempParent = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$defaultBuildTempRoot = Join-Path $buildTempParent 'CF7\runtime-build-temp'
$buildTempRoot = if ($env:CF7_RUNTIME_JOB_TEMP) {
    [IO.Path]::GetFullPath($env:CF7_RUNTIME_JOB_TEMP)
} else {
    $defaultBuildTempRoot
}
if (-not (Test-Path -LiteralPath $buildTempRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $buildTempRoot -Force | Out-Null
}
$env:TMP = $buildTempRoot
$env:TEMP = $buildTempRoot
$env:TZ = 'UTC'
$env:VSLANG = '1033'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
foreach ($entry in [Environment]::GetEnvironmentVariables('Process').Keys) {
    if ([string]$entry -like 'CARGO_PROFILE_RELEASE_*') { [Environment]::SetEnvironmentVariable([string]$entry, $null, 'Process') }
}

function Add-Mismatch([string]$message) { $script:Cf7RuntimeBuildErrors += $message }
function Assert-Equal([string]$label, [string]$expected, [string]$actual) {
    if ($expected -ne $actual) { Add-Mismatch "$label expected=$expected actual=$actual" }
}
function Assert-Hash([string]$label, [string]$path, [string]$expected) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Mismatch "$label missing=$path"; return }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    Assert-Equal "$label SHA256" $expected.ToUpperInvariant() $actual
}

# .NET SDK：只选择同时具备精确 SDK 且 host 字节匹配的安装，不依赖机器 PATH 顺序。
$pathDotnet = Get-Command dotnet -ErrorAction SilentlyContinue
$dotnetCandidates = @()
if ($env:DOTNET_ROOT_X64) { $dotnetCandidates += Join-Path $env:DOTNET_ROOT_X64 'dotnet.exe' }
if ($env:DOTNET_ROOT) { $dotnetCandidates += Join-Path $env:DOTNET_ROOT 'dotnet.exe' }
$dotnetCandidates += Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
$dotnetCandidates += Join-Path $env:USERPROFILE '.dotnet\dotnet.exe'
$dotnetCandidates += Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
$dotnetCandidates += Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'dotnet\dotnet.exe'
if ($pathDotnet) { $dotnetCandidates += $pathDotnet.Source }
$dotnet = $null
foreach ($candidate in @($dotnetCandidates | Where-Object { $_ } | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToUpperInvariant()
    if ($candidateHash -ne ([string]$lock.dotnet.executableSha256).ToUpperInvariant()) { continue }
    $dotnet = $candidate
    break
}
if (-not $dotnet) { throw "No dotnet host matches the pinned SDK/host bytes in $lockPath" }
$oldLocation = Get-Location
try {
    Set-Location -LiteralPath $ProjectRoot
    $dotnetVersion = (& $dotnet --version 2>&1 | Select-Object -First 1).Trim()
} finally { Set-Location -LiteralPath $oldLocation }
Assert-Equal '.NET SDK' ([string]$lock.dotnet.sdkVersion) $dotnetVersion
Assert-Hash 'dotnet.exe' $dotnet ([string]$lock.dotnet.executableSha256)
$sdkDir = Join-Path (Split-Path -Parent $dotnet) ("sdk\" + [string]$lock.dotnet.sdkVersion)
Assert-Hash 'Roslyn csc.dll' (Join-Path $sdkDir 'Roslyn\bincore\csc.dll') ([string]$lock.dotnet.cscSha256)
Assert-Hash 'MSBuild.dll' (Join-Path $sdkDir 'MSBuild.dll') ([string]$lock.dotnet.msbuildSha256)
$globalJson = Get-Content -LiteralPath (Join-Path $ProjectRoot 'global.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 'global.json sdk.version' ([string]$lock.dotnet.sdkVersion) ([string]$globalJson.sdk.version)
Assert-Equal 'global.json rollForward' ([string]$lock.dotnet.rollForward) ([string]$globalJson.sdk.rollForward)

# MSVC：允许 VS 安装根不同，但 toolset 目录与实际 executable 字节必须相同。
$vsRoot = $null
$vcToolsDir = $null
$vswhere = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere -PathType Leaf) { $env:CF7_VSWHERE_DIR = Split-Path -Parent $vswhere }
if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
    foreach ($candidate in @(& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)) {
        $candidateTools = Join-Path $candidate ("VC\Tools\MSVC\" + [string]$lock.msvc.toolsVersion)
        if (-not (Test-Path -LiteralPath $candidateTools)) { continue }
        $candidateCl = Join-Path $candidateTools 'bin\Hostx64\x64\cl.exe'
        $candidateLink = Join-Path $candidateTools 'bin\Hostx64\x64\link.exe'
        if (-not (Test-Path -LiteralPath $candidateCl -PathType Leaf) `
                -or -not (Test-Path -LiteralPath $candidateLink -PathType Leaf)) { continue }
        $candidateClHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateCl).Hash.ToUpperInvariant()
        $candidateLinkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateLink).Hash.ToUpperInvariant()
        $candidateClVersion = [string](Get-Item -LiteralPath $candidateCl).VersionInfo.FileVersion
        $candidateLinkVersion = [string](Get-Item -LiteralPath $candidateLink).VersionInfo.FileVersion
        if ($candidateClHash -eq ([string]$lock.msvc.clSha256).ToUpperInvariant() `
                -and $candidateLinkHash -eq ([string]$lock.msvc.linkSha256).ToUpperInvariant() `
                -and $candidateClVersion -eq [string]$lock.msvc.compilerFileVersion `
                -and $candidateLinkVersion -eq [string]$lock.msvc.linkerFileVersion) {
            $vsRoot = $candidate
            $vcToolsDir = $candidateTools
            break
        }
    }
}
if (-not $vcToolsDir) {
    Add-Mismatch "MSVC exact toolset bytes missing toolsVersion=$($lock.msvc.toolsVersion) compiler=$($lock.msvc.compilerFileVersion)"
} else {
    $cl = Join-Path $vcToolsDir 'bin\Hostx64\x64\cl.exe'
    $link = Join-Path $vcToolsDir 'bin\Hostx64\x64\link.exe'
    Assert-Hash 'cl.exe' $cl ([string]$lock.msvc.clSha256)
    Assert-Hash 'link.exe' $link ([string]$lock.msvc.linkSha256)
    if (Test-Path -LiteralPath $cl) { Assert-Equal 'cl.exe version' ([string]$lock.msvc.compilerFileVersion) ([string](Get-Item -LiteralPath $cl).VersionInfo.FileVersion) }
    if (Test-Path -LiteralPath $link) { Assert-Equal 'link.exe version' ([string]$lock.msvc.linkerFileVersion) ([string](Get-Item -LiteralPath $link).VersionInfo.FileVersion) }
    $env:CF7_VCVARS64 = Join-Path $vsRoot 'VC\Auxiliary\Build\vcvars64.bat'
    $env:CF7_MSVC_TOOLS_VERSION = [string]$lock.msvc.toolsVersion
    $env:CF7_CL_EXE = $cl
    $env:CF7_LINK_EXE = $link
}

$sdkRoot = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) ("Windows Kits\10\bin\" + [string]$lock.windowsSdk.version + '\x64')
$rc = Join-Path $sdkRoot 'rc.exe'
Assert-Hash 'rc.exe' $rc ([string]$lock.windowsSdk.rcSha256)
$env:CF7_WINDOWS_SDK_VERSION = ([string]$lock.windowsSdk.version).TrimEnd('\')
$env:CF7_RC_EXE = $rc

# Rust：rust-toolchain.toml 固定 channel；发布时进一步检查真实 rustc/cargo，而不是 rustup proxy。
$rustupHome = $env:RUSTUP_HOME
if ([string]::IsNullOrWhiteSpace($rustupHome)) { $rustupHome = Join-Path $env:USERPROFILE '.rustup' }
$rustToolchain = [string]$lock.rust.toolchain
$rustBin = Join-Path $rustupHome ("toolchains\$rustToolchain\bin")
$rustc = Join-Path $rustBin 'rustc.exe'
$cargo = Join-Path $rustBin 'cargo.exe'
Assert-Hash 'rustc.exe' $rustc ([string]$lock.rust.rustcSha256)
Assert-Hash 'cargo.exe' $cargo ([string]$lock.rust.cargoSha256)
if (Test-Path -LiteralPath $rustc) {
    $rustVerbose = (& $rustc -Vv 2>&1) -join "`n"
    $release = [regex]::Match($rustVerbose, '(?m)^release:\s*(.+)$').Groups[1].Value.Trim()
    $commit = [regex]::Match($rustVerbose, '(?m)^commit-hash:\s*(.+)$').Groups[1].Value.Trim()
    Assert-Equal 'rustc release' ([string]$lock.rust.rustcVersion) $release
    Assert-Equal 'rustc commit' ([string]$lock.rust.rustcCommit) $commit
}
if (Test-Path -LiteralPath $cargo) {
    $cargoText = (& $cargo -V 2>&1 | Select-Object -First 1)
    $cargoVersion = ([regex]::Match($cargoText, '^cargo\s+([^\s]+)')).Groups[1].Value
    Assert-Equal 'cargo version' ([string]$lock.rust.cargoVersion) $cargoVersion
}
$env:CF7_RUST_TOOLCHAIN = $rustToolchain
$env:CF7_RUSTC_EXE = $rustc
$env:CF7_CARGO_EXE = $cargo
$env:RUSTC = $rustc
$env:CARGO_INCREMENTAL = '0'
$rustFlags = @(
    "--remap-path-prefix=$ProjectRoot=/_/",
    "--remap-path-prefix=$env:USERPROFILE=/_user",
    '-C', 'link-arg=/Brepro'
)
if ($env:CARGO_HOME) { $rustFlags += "--remap-path-prefix=$env:CARGO_HOME=/_cargo" }
if ($env:RUSTUP_HOME) { $rustFlags += "--remap-path-prefix=$env:RUSTUP_HOME=/_rustup" }
$env:CARGO_ENCODED_RUSTFLAGS = [string]::Join([char]0x1f, [string[]]$rustFlags)

if ($script:Cf7RuntimeBuildErrors.Count -gt 0) {
    foreach ($message in $script:Cf7RuntimeBuildErrors) { Write-Host "[RuntimeBuildEnv] MISMATCH $message" -ForegroundColor Yellow }
    if ($Mode -eq 'RuntimePublish') {
        Write-Host "[RuntimeBuildEnv] FAIL baseline=$($lock.baseline) — formal runtime build refused." -ForegroundColor Red
        exit 2
    }
    Write-Host "[RuntimeBuildEnv] WARN baseline=$($lock.baseline) — validation-only mode; runtime publication is forbidden." -ForegroundColor Yellow
    return
}

$env:CF7_DOTNET_EXE = $dotnet
$env:CF7_RUNTIME_BASELINE = [string]$lock.baseline
Write-Host "[RuntimeBuildEnv] OK baseline=$($lock.baseline) dotnet=$dotnetVersion msvc=$($lock.msvc.compilerFileVersion) rustc=$($lock.rust.rustcVersion)/$($lock.rust.rustcCommit.Substring(0,9)) sdk=$($lock.windowsSdk.version)" -ForegroundColor Green
