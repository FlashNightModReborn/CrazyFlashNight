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
$diagnosticsRoot = if ($env:CF7_BOOTSTRAP_DIAGNOSTICS_DIR) {
    [IO.Path]::GetFullPath([string]$env:CF7_BOOTSTRAP_DIAGNOSTICS_DIR)
} else {
    Join-Path $ProjectRoot 'tmp\runtime-bootstrap-diagnostics'
}
$script:Cf7VisualStudioSetupStartedUtc = $null
if (-not $VerifyOnly) { New-Item -ItemType Directory -Force -Path $diagnosticsRoot | Out-Null }

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
    # Enumerate every instance. A clean machine may have VS without the C++ workload,
    # and VS 2026 exposes the locked v143 compatibility toolset as a versioned component.
    $json = (& $vswhere -all -prerelease -products '*' -format json -utf8) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
    # Windows PowerShell 5.1 preserves a top-level JSON array as one Object[]
    # when it is returned directly from a function. Callers would then see one
    # synthetic instance whose installationPath is both paths joined by a space.
    # Emit each registered instance explicitly so side-by-side installs remain
    # independently discoverable in the same process that completed setup.
    $parsedInstances = ConvertFrom-Json $json
    foreach ($parsedInstance in $parsedInstances) {
        Write-Output $parsedInstance
    }
}

function Write-Cf7VisualStudioInventory {
    $instances = @(Get-Cf7VsInstances)
    if ($instances.Count -eq 0) {
        Write-Host '[RuntimeBootstrap] Visual Studio inventory: no registered instances.' -ForegroundColor Yellow
    }
    foreach ($instance in $instances) {
        $path = [string]$instance.installationPath
        Write-Host ("[RuntimeBootstrap] Visual Studio instance product={0} version={1} path={2}" -f `
            [string]$instance.productId, [string]$instance.installationVersion, $path) -ForegroundColor Cyan
        $msvcRoot = Join-Path $path 'VC\Tools\MSVC'
        foreach ($tools in @(Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $cl = Join-Path $tools.FullName 'bin\Hostx64\x64\cl.exe'
            $link = Join-Path $tools.FullName 'bin\Hostx64\x64\link.exe'
            if ((Test-Path -LiteralPath $cl -PathType Leaf) -and (Test-Path -LiteralPath $link -PathType Leaf)) {
                $clVersion = [string](Get-Item -LiteralPath $cl).VersionInfo.FileVersion
                $linkVersion = [string](Get-Item -LiteralPath $link).VersionInfo.FileVersion
                $clHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cl).Hash.ToUpperInvariant()
                $linkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $link).Hash.ToUpperInvariant()
                Write-Host "[RuntimeBootstrap]   MSVC tools=$($tools.Name) cl=$clVersion sha256=$clHash"
                Write-Host "[RuntimeBootstrap]   MSVC tools=$($tools.Name) link=$linkVersion sha256=$linkHash"
            }
        }
    }
    $sdkBin = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Windows Kits\10\bin'
    $sdkVersions = @(Get-ChildItem -LiteralPath $sdkBin -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    Write-Host "[RuntimeBootstrap] Windows SDK inventory: $([string]::Join(', ', [string[]]@($sdkVersions.Name)))"
    foreach ($sdk in $sdkVersions) {
        $rc = Join-Path $sdk.FullName 'x64\rc.exe'
        if (Test-Path -LiteralPath $rc -PathType Leaf) {
            Write-Host "[RuntimeBootstrap]   SDK=$($sdk.Name) rcSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $rc).Hash.ToUpperInvariant())"
        }
    }
    $systemDrive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($env:SystemRoot).TrimEnd(':\')) -ErrorAction SilentlyContinue
    if ($systemDrive) { Write-Host "[RuntimeBootstrap] System drive free bytes: $([Int64]$systemDrive.Free)" }
}

function Copy-Cf7VisualStudioSetupDiagnostics([datetime]$SinceUtc) {
    if ($VerifyOnly -or -not $env:TEMP -or -not (Test-Path -LiteralPath $env:TEMP -PathType Container)) { return }
    $destination = Join-Path $diagnosticsRoot 'visual-studio-setup'
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    $total = 0L
    $copied = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $env:TEMP -File -Filter 'dd_*' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $SinceUtc.AddMinutes(-1) } |
            Sort-Object LastWriteTimeUtc -Descending)) {
        if ($file.Length -gt 4MB -or ($total + $file.Length) -gt 16MB) { continue }
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $destination $file.Name) -Force
        $total += $file.Length
        $copied++
    }
    if ($copied -gt 0) {
        Write-Host "[RuntimeBootstrap] Preserved $copied Visual Studio setup log(s) in $destination" -ForegroundColor Yellow
    }
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
    if ($isAdmin) {
        Write-Host '[RuntimeBootstrap] Starting unattended Visual Studio setup.' -ForegroundColor Yellow
    } else {
        Write-Host '[RuntimeBootstrap] Visual Studio setup needs one UAC approval; the remaining install is unattended.' -ForegroundColor Yellow
    }
    $script:Cf7VisualStudioSetupStartedUtc = [DateTime]::UtcNow
    $start = @{ FilePath = $Bootstrapper; ArgumentList = $Arguments; Wait = $true; PassThru = $true }
    if (-not $isAdmin) { $start.Verb = 'RunAs' }
    try { $process = Start-Process @start }
    catch {
        Copy-Cf7VisualStudioSetupDiagnostics -SinceUtc $script:Cf7VisualStudioSetupStartedUtc
        throw "Visual Studio installer was not elevated or could not start: $($_.Exception.Message)"
    }
    if (@(0, 1641, 3010) -notcontains $process.ExitCode) {
        Copy-Cf7VisualStudioSetupDiagnostics -SinceUtc $script:Cf7VisualStudioSetupStartedUtc
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
    Write-Cf7VisualStudioInventory
    $vs = $lock.provisioning.visualStudio
    $componentArgs = @($vs.components | ForEach-Object { "--add `"$([string]$_)`"" }) -join ' '
    $modifyTarget = $null
    if ($matchingInstance) {
        # An exact v143 toolset in VS 2026 is acceptable. In that case setup is
        # used only to add the locked SDK; the final byte gate still rechecks all tools.
        $modifyTarget = $matchingInstance
    }
    if ($modifyTarget) {
        $setup = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\Installer\setup.exe'
        if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'The installed Visual Studio setup engine is missing.' }
        # `modify` is the supported operation for adding components. `update`
        # refreshes an installation but does not establish the missing-component contract.
        $arguments = "modify --installPath `"$modifyTarget`" $componentArgs --quiet --norestart"
        Write-Host "[RuntimeBootstrap] Adding locked components to the compatible Visual Studio instance: $modifyTarget" -ForegroundColor Yellow
        Invoke-Cf7VisualStudioInstaller $setup $arguments
    } else {
        # Do not `modify` an arbitrary older VS 2022 instance. Its installed channel
        # may keep serving an older component payload (for example 17.14.33 / cl
        # 19.44.35227) even when the requested component ID is identical. That makes
        # the locked 17.14.36 / cl 19.44.35228 byte gate impossible to satisfy.
        # Use the pinned bootstrapper and dedicated install path so provisioning and
        # the final executable hashes refer to the same immutable baseline.
        $bootstrapper = Get-Cf7PinnedDownload ("vs_BuildTools_" + [string]$vs.release + '.exe') ([string]$vs.bootstrapperUrl) ([string]$vs.bootstrapperSha256)
        if ([string](Get-Item -LiteralPath $bootstrapper).VersionInfo.FileVersion -ne [string]$vs.installerVersion) {
            throw 'Visual Studio bootstrapper file version does not match the lock.'
        }
        $installPath = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) ([string]$vs.preferredInstallPath)
        # VS Setup rejects overly long product roots before installing any payload.
        # Keep a conservative project-owned bound so a bad lock fails before UAC.
        $maxInstallRootLength = 64
        if ($installPath.Length -gt $maxInstallRootLength) {
            throw "The pinned Visual Studio install root is too long ($($installPath.Length) > $maxInstallRootLength): $installPath"
        }
        # Nickname is cosmetic and some VS Setup builds reject otherwise harmless
        # punctuation/localized values. Keep provisioning identity solely in the lock.
        $arguments = "--installPath `"$installPath`" $componentArgs --quiet --wait --norestart"
        Write-Host "[RuntimeBootstrap] Installing side-by-side pinned Build Tools: $installPath" -ForegroundColor Yellow
        Invoke-Cf7VisualStudioInstaller $bootstrapper $arguments
    }
    if (-not (Find-Cf7MatchingMsvc) -or -not (Test-Cf7WindowsSdk)) {
        Write-Cf7VisualStudioInventory
        if ($script:Cf7VisualStudioSetupStartedUtc) {
            Copy-Cf7VisualStudioSetupDiagnostics -SinceUtc $script:Cf7VisualStudioSetupStartedUtc
        }
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
