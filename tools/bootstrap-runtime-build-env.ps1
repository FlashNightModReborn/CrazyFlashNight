param(
    [string]$ProjectRoot,
    [switch]$VerifyOnly,
    [switch]$NoElevation
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$lockPath = Join-Path $ProjectRoot 'config\build\runtime-toolchain.lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $lock.provisioning -or -not $lock.provisioning.visualStudio) {
    throw "Runtime toolchain lock has no provisioning contract: $lockPath"
}

$cacheRoot = Join-Path $env:LOCALAPPDATA ("CF7\toolchain-cache\" + [string]$lock.baseline)
if (-not $VerifyOnly) { New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null }

function Test-Cf7Hash([string]$Path, [string]$Expected) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() -eq $Expected.ToUpperInvariant()
}

function Get-Cf7PinnedDownload([string]$Name, [string]$Url, [string]$Sha256) {
    $path = Join-Path $cacheRoot $Name
    if (Test-Cf7Hash $path $Sha256) { return $path }
    if ($VerifyOnly) { throw "Pinned installer is not cached: $Name" }
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    Write-Host "[RuntimeBootstrap] Downloading $Name" -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $path
    if (-not (Test-Cf7Hash $path $Sha256)) {
        Remove-Item -LiteralPath $path -Force
        throw "Pinned installer SHA256 mismatch: $Name"
    }
    return $path
}

function Get-Cf7DotnetCandidates {
    $candidates = @()
    if ($env:DOTNET_ROOT_X64) { $candidates += Join-Path $env:DOTNET_ROOT_X64 'dotnet.exe' }
    if ($env:DOTNET_ROOT) { $candidates += Join-Path $env:DOTNET_ROOT 'dotnet.exe' }
    $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
    $candidates += Join-Path $env:USERPROFILE '.dotnet\dotnet.exe'
    $candidates += Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
    $candidates += Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'dotnet\dotnet.exe'
    $pathDotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($pathDotnet) { $candidates += $pathDotnet.Source }
    return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

function Test-Cf7Dotnet([string]$Dotnet) {
    if (-not (Test-Cf7Hash $Dotnet ([string]$lock.dotnet.executableSha256))) { return $false }
    $sdkDir = Join-Path (Split-Path -Parent $Dotnet) ("sdk\" + [string]$lock.dotnet.sdkVersion)
    return (Test-Cf7Hash (Join-Path $sdkDir 'Roslyn\bincore\csc.dll') ([string]$lock.dotnet.cscSha256)) -and
        (Test-Cf7Hash (Join-Path $sdkDir 'MSBuild.dll') ([string]$lock.dotnet.msbuildSha256))
}

function Ensure-Cf7Dotnet {
    foreach ($candidate in Get-Cf7DotnetCandidates) {
        if (Test-Cf7Dotnet $candidate) {
            Write-Host "[RuntimeBootstrap] .NET SDK already matches: $candidate" -ForegroundColor Green
            return
        }
    }
    if ($VerifyOnly) { throw ".NET SDK does not match baseline $($lock.baseline)" }
    $installer = Get-Cf7PinnedDownload 'dotnet-install.ps1' ([string]$lock.provisioning.dotnetInstallScriptUrl) ([string]$lock.provisioning.dotnetInstallScriptSha256)
    $installDir = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'
    Write-Host "[RuntimeBootstrap] Installing .NET SDK $($lock.dotnet.sdkVersion) per-user" -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Version ([string]$lock.dotnet.sdkVersion) -Architecture x64 -InstallDir $installDir -NoPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Cf7Dotnet (Join-Path $installDir 'dotnet.exe'))) {
        throw "Pinned .NET SDK installation failed."
    }
}

function Get-Cf7RustPaths {
    $rustupHome = $env:RUSTUP_HOME
    if ([string]::IsNullOrWhiteSpace($rustupHome)) { $rustupHome = Join-Path $env:USERPROFILE '.rustup' }
    $bin = Join-Path $rustupHome ("toolchains\" + [string]$lock.rust.toolchain + '\bin')
    return @{ Rustc = Join-Path $bin 'rustc.exe'; Cargo = Join-Path $bin 'cargo.exe' }
}

function Test-Cf7Rust {
    $paths = Get-Cf7RustPaths
    return (Test-Cf7Hash $paths.Rustc ([string]$lock.rust.rustcSha256)) -and
        (Test-Cf7Hash $paths.Cargo ([string]$lock.rust.cargoSha256))
}

function Ensure-Cf7Rust {
    if (Test-Cf7Rust) {
        Write-Host "[RuntimeBootstrap] Rust already matches: $($lock.rust.toolchain)" -ForegroundColor Green
        return
    }
    if ($VerifyOnly) { throw "Rust does not match baseline $($lock.baseline)" }
    $rustup = Get-Command rustup -ErrorAction SilentlyContinue
    if (-not $rustup) {
        $rustupInit = Get-Cf7PinnedDownload 'rustup-init.exe' ([string]$lock.provisioning.rustupInitUrl) ([string]$lock.provisioning.rustupInitSha256)
        Write-Host '[RuntimeBootstrap] Installing rustup per-user' -ForegroundColor Yellow
        & $rustupInit -y --no-modify-path --profile minimal --default-toolchain none
        if ($LASTEXITCODE -ne 0) { throw 'rustup installation failed.' }
        $rustupPath = Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'
    } else {
        $rustupPath = $rustup.Source
    }
    Write-Host "[RuntimeBootstrap] Installing Rust $($lock.rust.toolchain)" -ForegroundColor Yellow
    & $rustupPath toolchain install ([string]$lock.rust.toolchain) --profile minimal
    if ($LASTEXITCODE -ne 0 -or -not (Test-Cf7Rust)) { throw 'Pinned Rust installation failed.' }
}

function Get-Cf7VsInstances {
    $vswhere = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { return @() }
    $json = (& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json -utf8) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
    return @(ConvertFrom-Json $json)
}

function Find-Cf7MatchingMsvc {
    foreach ($instance in Get-Cf7VsInstances) {
        $tools = Join-Path ([string]$instance.installationPath) ("VC\Tools\MSVC\" + [string]$lock.msvc.toolsVersion)
        $cl = Join-Path $tools 'bin\Hostx64\x64\cl.exe'
        $link = Join-Path $tools 'bin\Hostx64\x64\link.exe'
        if ((Test-Cf7Hash $cl ([string]$lock.msvc.clSha256)) -and
                (Test-Cf7Hash $link ([string]$lock.msvc.linkSha256)) -and
                [string](Get-Item -LiteralPath $cl).VersionInfo.FileVersion -eq [string]$lock.msvc.compilerFileVersion -and
                [string](Get-Item -LiteralPath $link).VersionInfo.FileVersion -eq [string]$lock.msvc.linkerFileVersion) {
            return [string]$instance.installationPath
        }
    }
    return $null
}

function Test-Cf7WindowsSdk {
    $rc = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) `
        ("Windows Kits\10\bin\" + [string]$lock.windowsSdk.version + '\x64\rc.exe')
    return Test-Cf7Hash $rc ([string]$lock.windowsSdk.rcSha256)
}

function Invoke-Cf7VisualStudioInstaller([string]$Bootstrapper, [string]$Arguments) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin -and $NoElevation) {
        throw "Visual Studio provisioning requires elevation. Re-run without -NoElevation or from an elevated shell."
    }
    Write-Host '[RuntimeBootstrap] Visual Studio setup needs one UAC approval; the remaining install is unattended.' -ForegroundColor Yellow
    $start = @{ FilePath = $Bootstrapper; ArgumentList = $Arguments; Wait = $true; PassThru = $true }
    if (-not $isAdmin) { $start.Verb = 'RunAs' }
    try { $process = Start-Process @start }
    catch { throw "Visual Studio installer was not elevated or could not start: $($_.Exception.Message)" }
    if (@(0, 1641, 3010) -notcontains $process.ExitCode) {
        throw "Visual Studio installer failed with exit code $($process.ExitCode)."
    }
}

function Ensure-Cf7Msvc {
    $matchingInstance = Find-Cf7MatchingMsvc
    if ($matchingInstance -and (Test-Cf7WindowsSdk)) {
        Write-Host "[RuntimeBootstrap] MSVC and Windows SDK already match: $matchingInstance" -ForegroundColor Green
        return
    }
    if ($VerifyOnly) { throw "MSVC/Windows SDK do not match baseline $($lock.baseline)" }
    $vs = $lock.provisioning.visualStudio
    $bootstrapper = Get-Cf7PinnedDownload ("vs_BuildTools_" + [string]$vs.release + '.exe') ([string]$vs.bootstrapperUrl) ([string]$vs.bootstrapperSha256)
    if ([string](Get-Item -LiteralPath $bootstrapper).VersionInfo.FileVersion -ne [string]$vs.installerVersion) {
        throw 'Visual Studio bootstrapper file version does not match the lock.'
    }
    $componentArgs = @($vs.components | ForEach-Object { "--add `"$([string]$_)`"" }) -join ' '
    $instances = Get-Cf7VsInstances
    $updateTarget = $null
    foreach ($instance in $instances) {
        $tools = Join-Path ([string]$instance.installationPath) ("VC\Tools\MSVC\" + [string]$lock.msvc.toolsVersion)
        if (Test-Path -LiteralPath $tools -PathType Container) {
            try {
                if ([version]$instance.installationVersion -le [version]$vs.installerVersion) { $updateTarget = [string]$instance.installationPath; break }
            } catch {}
        }
    }
    if ($matchingInstance) { $updateTarget = $matchingInstance }
    if ($updateTarget) {
        $arguments = "update --installPath `"$updateTarget`" $componentArgs --quiet --wait --norestart"
        Write-Host "[RuntimeBootstrap] Updating pinned Build Tools instance: $updateTarget" -ForegroundColor Yellow
    } else {
        $installPath = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) ([string]$vs.preferredInstallPath)
        $arguments = "--installPath `"$installPath`" --nickname `"CF7 Runtime $([string]$vs.release)`" $componentArgs --quiet --wait --norestart"
        Write-Host "[RuntimeBootstrap] Installing side-by-side pinned Build Tools: $installPath" -ForegroundColor Yellow
    }
    Invoke-Cf7VisualStudioInstaller $bootstrapper $arguments
    if (-not (Find-Cf7MatchingMsvc) -or -not (Test-Cf7WindowsSdk)) {
        throw 'Visual Studio setup completed but the pinned MSVC/Windows SDK bytes are still unavailable.'
    }
}

try {
    Ensure-Cf7Dotnet
    Ensure-Cf7Rust
    Ensure-Cf7Msvc
} catch {
    Write-Host "[RuntimeBootstrap] FAIL $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

Write-Host '[RuntimeBootstrap] Running the formal byte-for-byte environment gate...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'tools\check-runtime-build-env.ps1') -ProjectRoot $ProjectRoot -Mode RuntimePublish
exit $LASTEXITCODE
