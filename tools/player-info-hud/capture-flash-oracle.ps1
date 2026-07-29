[CmdletBinding(DefaultParameterSetName = 'Capture')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Validate')]
    [Alias('SelfTest')]
    [switch]$ValidateOnly,

    [Parameter(ParameterSetName = 'Capture')]
    [ValidateRange(30, 3600)]
    [int]$CompileTimeoutSeconds = 240,

    [Parameter(ParameterSetName = 'Capture')]
    [ValidateRange(30, 1800)]
    [int]$CaptureTimeoutSeconds = 600,

    [Parameter(ParameterSetName = 'Capture')]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedUiSwfSha256 =
        '450B1F9A8B445EE3E28C63682EA00124A191F56D05D759B8590210FC0066A615',

    [Parameter(ParameterSetName = 'Capture')]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedPlayerSha256 =
        '9CDD2F9F880641CED00C2ADE8156E1A5476DB258D6B5D2A4A411E6AADDD3139D'
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectDir = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$scriptsDir = Join-Path $projectDir 'scripts'
$templatePath = Join-Path $projectDir `
    'scripts\test-runners\player-info-oracle\TestLoader.as.template'
$protocolHelperPath = Join-Path $PSScriptRoot 'flash-oracle-protocol.ps1'
$captureRunnerRelativePath =
    'tools/player-info-hud/capture-flash-oracle.ps1'
$protocolHelperRelativePath =
    'tools/player-info-hud/flash-oracle-protocol.ps1'
$scratchHelperPath = Join-Path $projectDir `
    'scripts\test-runners\testloader-scratch-transaction.ps1'
$scratchRunnerPath = Join-Path $scriptsDir 'TestLoader.as'
$compilePath = Join-Path $scriptsDir 'compile_test.ps1'
$loaderSwfPath = Join-Path $scriptsDir 'TestLoader.swf'
$publishProfilePath = Join-Path $scriptsDir 'TestLoader\PublishSettings.xml'
$compileOutputPath = Join-Path $scriptsDir 'compile_output.txt'
$compilerErrorsPath = Join-Path $scriptsDir 'compiler_errors.txt'
$uiSwfRelativePath = 'flashswf/UI/玩家信息界面.swf'
$uiSwfPath = Join-Path $projectDir 'flashswf\UI\玩家信息界面.swf'
$mainSwfRelativePath = 'CRAZYFLASHER7MercenaryEmpire.swf'
$mainSwfPath = Join-Path $projectDir 'CRAZYFLASHER7MercenaryEmpire.swf'
$playerLogicalPath =
    'FlashCS6Task/Players/Debug/FlashPlayerDebugger.exe'
$playerPath = $null
$formulaRelativePath = 'scripts/展现/UI交互/UI交互_fs_玩家信息界面.as'
$formulaPath = Join-Path $projectDir `
    'scripts\展现\UI交互\UI交互_fs_玩家信息界面.as'
$closureRelativePath = 'tools/player-info-hud/evidence/b0-01/closure.json'
$chainRelativePath = 'tools/player-info-hud/evidence/b0-01/source-binary-chain.json'
$closurePath = Join-Path $projectDir `
    'tools\player-info-hud\evidence\b0-01\closure.json'
$chainPath = Join-Path $projectDir `
    'tools\player-info-hud\evidence\b0-01\source-binary-chain.json'
$scratchMarker = Join-Path $scriptsDir 'testloader_scratch_inflight.marker'
$uncertainMarker = Join-Path $scriptsDir 'compile_state_uncertain.marker'
$globalFlashLog = Join-Path $env:APPDATA `
    'Macromedia\Flash Player\Logs\flashlog.txt'
$tmpRoot = Join-Path $projectDir 'tmp\player-info-hud\oracle'
$naturalExitTimeoutMilliseconds = 15000
$stabilityPollMilliseconds = 250
$requiredStablePolls = 4
$stabilityTimeoutSeconds = 8

. $protocolHelperPath
. $scratchHelperPath

function Test-Utf8Bom {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
}

function Get-PathSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Read-SharedBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ,[byte[]]@()
    }
    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $bytes = [byte[]]::new($stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) {
                throw "Unexpected EOF while reading shared file: $Path"
            }
            $offset += $read
        }
        return ,$bytes
    } finally {
        $stream.Dispose()
    }
}

function Get-FileIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            exists = $false
            length = 0
            sha256 = $null
            lastWriteUtc = $null
        }
    }
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        exists = $true
        length = [long]$item.Length
        sha256 = Get-PathSha256 -Path $Path
        lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
    }
}

function New-FrozenFileInput {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $before = Get-FileIdentity -Path $Path
    if (-not $before.exists) {
        throw "Required frozen input is missing: $Label"
    }
    $bytes = Read-SharedBytes -Path $Path
    $after = Get-FileIdentity -Path $Path
    $bytesHash = Get-PlayerInfoOracleBytesSha256 -Bytes $bytes
    if ($before.length -ne $after.length -or
        $before.sha256 -cne $after.sha256 -or
        $before.lastWriteUtc -cne $after.lastWriteUtc -or
        $bytes.Length -ne $after.length -or
        $bytesHash -cne $after.sha256) {
        throw "Frozen input changed while being read: $Label"
    }
    return [pscustomobject]@{
        label = $Label
        path = [System.IO.Path]::GetFullPath($Path)
        bytes = $bytes
        length = [long]$bytes.Length
        sha256 = $bytesHash
        lastWriteUtc = [string]$after.lastWriteUtc
    }
}

function Assert-FrozenFileInputCurrent {
    param([Parameter(Mandatory = $true)]$Frozen)

    $current = Get-FileIdentity -Path $Frozen.path
    if (-not $current.exists -or
        $current.length -ne $Frozen.length -or
        $current.sha256 -cne $Frozen.sha256 -or
        $current.lastWriteUtc -cne $Frozen.lastWriteUtc) {
        throw "Immutable capture input drifted: $($Frozen.label)"
    }
}

function Write-AtomicBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $temporary = $Path + '.tmp-' + [System.Guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllBytes($temporary, $Bytes)
    if ((Get-PathSha256 -Path $temporary) -cne
        (Get-PlayerInfoOracleBytesSha256 -Bytes $Bytes)) {
        throw "Atomic candidate write hash mismatch: $Path"
    }
    $replaceBackup = $null
    if (Test-Path -LiteralPath $Path) {
        $replaceBackup = $Path + '.replace-backup-' +
            [System.Guid]::NewGuid().ToString('N')
        [System.IO.File]::Replace(
            $temporary, $Path, $replaceBackup, $true)
    } else {
        Move-Item -LiteralPath $temporary -Destination $Path
    }
    if ((Get-PathSha256 -Path $Path) -cne
        (Get-PlayerInfoOracleBytesSha256 -Bytes $Bytes)) {
        throw "Atomic destination hash mismatch: $Path"
    }
    if ($replaceBackup -and (Test-Path -LiteralPath $replaceBackup)) {
        Remove-Item -LiteralPath $replaceBackup -Force
    }
}

function Write-AtomicUtf8Json {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 40
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
    Write-AtomicBytes -Path $Path -Bytes $bytes
}

function New-CandidateSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    if ($Name -match '[/\\]' -or [string]::IsNullOrWhiteSpace($Name)) {
        throw "Snapshot name must be one file leaf: $Name"
    }
    $path = Join-Path $EvidenceDirectory $Name
    Write-AtomicBytes -Path $path -Bytes $Bytes
    return [ordered]@{
        path = 'evidence/' + $Name
        bytes = $Bytes.Length
        sha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $Bytes
    }
}

function Assert-CandidateSnapshotSet {
    param(
        [Parameter(Mandatory = $true)][string]$WorkDirectory,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Snapshots
    )

    foreach ($entry in $Snapshots.GetEnumerator()) {
        $snapshot = $entry.Value
        $relative = [string]$snapshot.path
        if ($relative -notmatch '^evidence/[A-Za-z0-9._-]+$') {
            throw "Unsafe candidate snapshot path for '$($entry.Key)': $relative"
        }
        $absolute = Join-Path $WorkDirectory ($relative.Replace('/', '\'))
        $identity = Get-FileIdentity -Path $absolute
        if (-not $identity.exists -or
            $identity.length -ne [int64]$snapshot.bytes -or
            $identity.sha256 -cne [string]$snapshot.sha256) {
            throw "Candidate snapshot drifted before promotion: $($entry.Key)"
        }
    }
}

function Assert-PlayerInfoCaptureToolingBindings {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Snapshots,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$FrozenInputs,
        [Parameter(Mandatory = $true)]$StrictTooling,
        $Manifest = $null
    )

    if ([string]$StrictTooling.status -cne 'strict') {
        throw 'Candidate capture tooling is not strict Git provenance.'
    }
    $bindings = @(
        [pscustomobject]@{
            role = 'capture_runner'
            path = $captureRunnerRelativePath
            snapshot = $Snapshots.captureRunner
            frozen = $FrozenInputs.captureRunner
            identity = $StrictTooling.runner
        },
        [pscustomobject]@{
            role = 'protocol_helper'
            path = $protocolHelperRelativePath
            snapshot = $Snapshots.protocolHelper
            frozen = $FrozenInputs.protocolHelper
            identity = $StrictTooling.protocol
        }
    )
    foreach ($binding in $bindings) {
        if ([string]$binding.identity.status -cne 'strict' -or
            -not [bool]$binding.identity.headIndexCleanFilterEqual -or
            [string]$binding.identity.path -cne [string]$binding.path -or
            [string]$binding.snapshot.sha256 -cne
                [string]$binding.frozen.sha256 -or
            [int64]$binding.snapshot.bytes -ne
                [int64]$binding.frozen.length -or
            [string]$binding.identity.sha256 -cne
                [string]$binding.frozen.sha256 -or
            [int64]$binding.identity.bytes -ne
                [int64]$binding.frozen.length -or
            [string]$binding.identity.gitBlobOid -notmatch
                '^[0-9a-f]{40}$' -or
            [string]$binding.identity.gitBlobSha256 -notmatch
                '^[0-9A-F]{64}$' -or
            [int64]$binding.identity.gitBlobBytes -le 0) {
            throw "Capture-tool snapshot/Git binding drifted: $($binding.role)"
        }
        if ($null -ne $Manifest) {
            $manifestMatches = @($Manifest.captureTooling.files |
                Where-Object { [string]$_.role -ceq $binding.role })
            if ($manifestMatches.Count -ne 1) {
                throw "Manifest captureTooling role is not unique: $($binding.role)"
            }
            $manifestBinding = $manifestMatches[0]
            if ([string]$manifestBinding.path -cne $binding.path -or
                [string]$manifestBinding.sha256 -cne
                    [string]$binding.frozen.sha256 -or
                [int64]$manifestBinding.bytes -ne
                    [int64]$binding.frozen.length -or
                [string]$manifestBinding.gitBlobOid -cne
                    [string]$binding.identity.gitBlobOid -or
                [int64]$manifestBinding.gitBlobBytes -ne
                    [int64]$binding.identity.gitBlobBytes -or
                [string]$manifestBinding.gitBlobSha256 -cne
                    [string]$binding.identity.gitBlobSha256 -or
                [string]$manifestBinding.snapshot.sha256 -cne
                    [string]$binding.snapshot.sha256 -or
                [string]$manifestBinding.snapshot.path -cne
                    [string]$binding.snapshot.path) {
                throw "Manifest captureTooling cross-binding drifted: $($binding.role)"
            }
        }
    }
}

function Assert-PlayerInfoDerivedSourceMarker {
    param([Parameter(Mandatory = $true)]$Transaction)

    if (-not (Test-Path -LiteralPath $Transaction.SourceMarkerPath) -or
        [System.IO.File]::ReadAllText(
            $Transaction.SourceMarkerPath,
            [System.Text.Encoding]::UTF8) -cne
            $Transaction.SourceMarkerBody) {
        throw 'Source scratch marker changed during the derived-SWF transaction.'
    }
}

function Set-PlayerInfoDerivedSwfSidecar {
    param([Parameter(Mandatory = $true)]$Transaction)

    $body = $Transaction.Record | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($body)
    Write-AtomicBytes -Path $Transaction.SidecarPath -Bytes $bytes
    if ([System.IO.File]::ReadAllText(
            $Transaction.SidecarPath,
            [System.Text.Encoding]::UTF8) -cne $body) {
        throw 'Derived-SWF recovery sidecar was not written byte-exactly.'
    }
    $Transaction.SidecarBody = $body
}

function Assert-PlayerInfoDerivedSwfSidecar {
    param([Parameter(Mandatory = $true)]$Transaction)

    Assert-PlayerInfoDerivedSourceMarker -Transaction $Transaction
    if (-not (Test-Path -LiteralPath $Transaction.SidecarPath) -or
        [System.IO.File]::ReadAllText(
            $Transaction.SidecarPath,
            [System.Text.Encoding]::UTF8) -cne
            $Transaction.SidecarBody) {
        throw 'Derived-SWF recovery sidecar changed or disappeared.'
    }
}

function New-PlayerInfoDerivedSwfTransaction {
    param(
        [Parameter(Mandatory = $true)]$SourceTransaction,
        [Parameter(Mandatory = $true)][string]$SwfPath
    )

    if (-not (Test-Path -LiteralPath $SourceTransaction.MarkerPath) -or
        [System.IO.File]::ReadAllText(
            $SourceTransaction.MarkerPath,
            [System.Text.Encoding]::UTF8) -cne
            $SourceTransaction.MarkerBody) {
        throw 'Derived-SWF transaction requires the source scratch marker first.'
    }
    $absoluteSwfPath = [System.IO.Path]::GetFullPath($SwfPath)
    $recoveryDirectory = Join-Path (
        Split-Path -Parent $SourceTransaction.MarkerPath) `
        '.testloader-scratch-recovery'
    if (-not (Test-Path -LiteralPath $recoveryDirectory)) {
        [void](New-Item -ItemType Directory -Path $recoveryDirectory)
    }
    $token = [System.Guid]::NewGuid().ToString('N')
    $sidecarPath = Join-Path $recoveryDirectory (
        $token + '.TestLoader.swf.sidecar.json')
    $backupPath = Join-Path $recoveryDirectory (
        $token + '.TestLoader.swf.backup.bin')
    if ((Test-Path -LiteralPath $sidecarPath) -or
        (Test-Path -LiteralPath $backupPath)) {
        throw 'Derived-SWF recovery token unexpectedly collided.'
    }

    $originalIdentity = Get-FileIdentity -Path $absoluteSwfPath
    if ($originalIdentity.exists) {
        $originalFrozen = New-FrozenFileInput `
            -Path $absoluteSwfPath -Label 'original scripts/TestLoader.swf'
        $originalBytes = $originalFrozen.bytes
        $originalIdentity = [pscustomobject]@{
            exists = $true
            length = [long]$originalFrozen.length
            sha256 = [string]$originalFrozen.sha256
            lastWriteUtc = [string]$originalFrozen.lastWriteUtc
        }
        Write-AtomicBytes -Path $backupPath -Bytes $originalBytes
        if ((Get-FileIdentity -Path $backupPath).sha256 -cne
            $originalIdentity.sha256) {
            throw 'Persistent TestLoader.swf recovery backup hash mismatch.'
        }
    } else {
        if ((Get-FileIdentity -Path $absoluteSwfPath).exists) {
            throw 'TestLoader.swf appeared while its absent identity was captured.'
        }
        $backupPath = $null
    }
    $sourceMarkerHash = Get-PlayerInfoOracleBytesSha256 -Bytes (
        [System.Text.UTF8Encoding]::new($false).GetBytes(
            $SourceTransaction.MarkerBody))
    $record = [ordered]@{
        schema = 'cf7.player_info.derived_swf_transaction.v1'
        token = $token
        phase = 'prepared'
        createdUtc = [System.DateTime]::UtcNow.ToString('o')
        sourceMarkerPath = [System.IO.Path]::GetFullPath(
            $SourceTransaction.MarkerPath)
        sourceMarkerSha256 = $sourceMarkerHash
        swfPath = $absoluteSwfPath
        original = [ordered]@{
            exists = [bool]$originalIdentity.exists
            bytes = [long]$originalIdentity.length
            sha256 = [string]$originalIdentity.sha256
            lastWriteUtc = [string]$originalIdentity.lastWriteUtc
            backupPath = $backupPath
        }
        compiled = $null
        restored = $null
    }
    $transaction = [pscustomobject]@{
        SourceMarkerPath = $SourceTransaction.MarkerPath
        SourceMarkerBody = $SourceTransaction.MarkerBody
        SwfPath = $absoluteSwfPath
        RecoveryDirectory = $recoveryDirectory
        SidecarPath = $sidecarPath
        SidecarBody = $null
        BackupPath = $backupPath
        Record = $record
        CompiledBytes = $null
    }
    Set-PlayerInfoDerivedSwfSidecar -Transaction $transaction
    return $transaction
}

function Freeze-PlayerInfoDerivedSwfCompiledIdentity {
    param([Parameter(Mandatory = $true)]$Transaction)

    Assert-PlayerInfoDerivedSwfSidecar -Transaction $Transaction
    if ([string]$Transaction.Record.phase -cne 'prepared') {
        throw 'Derived-SWF transaction was not in prepared phase at compile freeze.'
    }
    $frozen = New-FrozenFileInput `
        -Path $Transaction.SwfPath -Label 'compiled scripts/TestLoader.swf'
    $Transaction.CompiledBytes = $frozen.bytes
    $Transaction.Record['compiled'] = [ordered]@{
        exists = $true
        bytes = [long]$frozen.length
        sha256 = [string]$frozen.sha256
        lastWriteUtc = [string]$frozen.lastWriteUtc
        frozenUtc = [System.DateTime]::UtcNow.ToString('o')
    }
    $Transaction.Record['phase'] = 'compiled_frozen'
    Set-PlayerInfoDerivedSwfSidecar -Transaction $Transaction
    return $frozen
}

function Assert-PlayerInfoDerivedSwfCompiledCurrent {
    param([Parameter(Mandatory = $true)]$Transaction)

    Assert-PlayerInfoDerivedSwfSidecar -Transaction $Transaction
    if ([string]$Transaction.Record.phase -cne 'compiled_frozen' -or
        $null -eq $Transaction.CompiledBytes) {
        throw 'Derived-SWF compiled identity has not been frozen.'
    }
    $identity = Get-FileIdentity -Path $Transaction.SwfPath
    if (-not $identity.exists -or
        $identity.length -ne [int64]$Transaction.Record.compiled.bytes -or
        $identity.sha256 -cne [string]$Transaction.Record.compiled.sha256 -or
        $identity.lastWriteUtc -cne
            [string]$Transaction.Record.compiled.lastWriteUtc -or
        (Get-PlayerInfoOracleBytesSha256 `
            -Bytes $Transaction.CompiledBytes) -cne $identity.sha256) {
        throw 'TestLoader.swf no longer matches the frozen compiled launch identity.'
    }
}

function Restore-PlayerInfoDerivedSwfTransaction {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [string]$UncertainMarkerPath = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($UncertainMarkerPath) -and
        (Test-Path -LiteralPath $UncertainMarkerPath)) {
        throw 'Compile-state marker appeared before derived-SWF recovery.'
    }
    Assert-PlayerInfoDerivedSwfCompiledCurrent -Transaction $Transaction
    $original = $Transaction.Record.original
    if ([bool]$original.exists) {
        if ([string]::IsNullOrWhiteSpace([string]$Transaction.BackupPath) -or
            -not (Test-Path -LiteralPath $Transaction.BackupPath)) {
            throw 'Persistent TestLoader.swf recovery backup is missing.'
        }
        $backupIdentity = Get-FileIdentity -Path $Transaction.BackupPath
        if ($backupIdentity.length -ne [int64]$original.bytes -or
            $backupIdentity.sha256 -cne [string]$original.sha256) {
            throw 'Persistent TestLoader.swf recovery backup drifted.'
        }
        Write-AtomicBytes `
            -Path $Transaction.SwfPath `
            -Bytes (Read-SharedBytes -Path $Transaction.BackupPath)
        [System.IO.File]::SetLastWriteTimeUtc(
            $Transaction.SwfPath,
            [datetime]$original.lastWriteUtc)
        $restored = Get-FileIdentity -Path $Transaction.SwfPath
        if (-not $restored.exists -or
            $restored.length -ne [int64]$original.bytes -or
            $restored.sha256 -cne [string]$original.sha256 -or
            $restored.lastWriteUtc -cne [string]$original.lastWriteUtc) {
            throw 'Restored TestLoader.swf does not match its original identity.'
        }
    } else {
        Remove-Item -LiteralPath $Transaction.SwfPath -Force
        $restored = Get-FileIdentity -Path $Transaction.SwfPath
        if ($restored.exists) {
            throw 'Newly-created TestLoader.swf still exists after recovery.'
        }
    }
    $Transaction.Record['restored'] = [ordered]@{
        exists = [bool]$restored.exists
        bytes = [long]$restored.length
        sha256 = [string]$restored.sha256
        lastWriteUtc = [string]$restored.lastWriteUtc
        verifiedUtc = [System.DateTime]::UtcNow.ToString('o')
    }
    $Transaction.Record['phase'] = 'restored'
    Set-PlayerInfoDerivedSwfSidecar -Transaction $Transaction
}

function Restore-PlayerInfoPreparedDerivedSwfTransaction {
    param([Parameter(Mandatory = $true)]$Transaction)

    Assert-PlayerInfoDerivedSwfSidecar -Transaction $Transaction
    if ([string]$Transaction.Record.phase -cne 'prepared') {
        throw 'Only an uncompiled prepared derived-SWF transaction can be cancelled.'
    }
    $original = $Transaction.Record.original
    $current = Get-FileIdentity -Path $Transaction.SwfPath
    if ($current.exists -ne [bool]$original.exists -or
        $current.length -ne [int64]$original.bytes -or
        [string]$current.sha256 -cne [string]$original.sha256 -or
        [string]$current.lastWriteUtc -cne [string]$original.lastWriteUtc) {
        throw 'Uncompiled TestLoader.swf changed after its prepared snapshot.'
    }
    $Transaction.Record['restored'] = [ordered]@{
        exists = [bool]$current.exists
        bytes = [long]$current.length
        sha256 = [string]$current.sha256
        lastWriteUtc = [string]$current.lastWriteUtc
        verifiedUtc = [System.DateTime]::UtcNow.ToString('o')
    }
    $Transaction.Record['phase'] = 'restored'
    Set-PlayerInfoDerivedSwfSidecar -Transaction $Transaction
}

function Complete-PlayerInfoUninstalledSourceScratchCleanup {
    param([Parameter(Mandatory = $true)]$Transaction)

    if (-not (Test-Path -LiteralPath $Transaction.MarkerPath) -or
        [System.IO.File]::ReadAllText(
            $Transaction.MarkerPath,
            [System.Text.Encoding]::UTF8) -cne
            $Transaction.MarkerBody) {
        throw 'Uninstalled source scratch marker changed before cancellation.'
    }
    if ($Transaction.HadRunner) {
        if (-not (Test-Path -LiteralPath $Transaction.RunnerPath) -or
            (Get-PathSha256 -Path $Transaction.RunnerPath) -cne
            [string]$Transaction.OriginalHash -or
            -not (Test-Path -LiteralPath $Transaction.BackupPath) -or
            (Get-PathSha256 -Path $Transaction.BackupPath) -cne
            [string]$Transaction.OriginalHash) {
            throw 'Uninstalled source scratch no longer matches its original bytes.'
        }
    } elseif (Test-Path -LiteralPath $Transaction.RunnerPath) {
        throw 'Source scratch appeared before installation completed.'
    }
    Remove-Item -LiteralPath $Transaction.MarkerPath -Force
    if ($Transaction.BackupPath -and
        (Test-Path -LiteralPath $Transaction.BackupPath)) {
        Remove-Item -LiteralPath $Transaction.BackupPath -Force
    }
}

function Assert-PlayerInfoRestoredSwfIdentity {
    param([Parameter(Mandatory = $true)]$Transaction)

    if ([string]$Transaction.Record.phase -cne 'restored' -or
        $null -eq $Transaction.Record.restored) {
        throw 'Derived-SWF transaction has no verified restored identity.'
    }
    $restored = Get-FileIdentity -Path $Transaction.SwfPath
    if ($restored.exists -ne [bool]$Transaction.Record.restored.exists -or
        $restored.length -ne [int64]$Transaction.Record.restored.bytes -or
        [string]$restored.sha256 -cne
        [string]$Transaction.Record.restored.sha256 -or
        [string]$restored.lastWriteUtc -cne
        [string]$Transaction.Record.restored.lastWriteUtc) {
        throw 'TestLoader.swf drifted after verified restoration.'
    }
    return $restored
}

function Complete-PlayerInfoDerivedSwfCleanup {
    param([Parameter(Mandatory = $true)]$Transaction)

    if (Test-Path -LiteralPath $Transaction.SourceMarkerPath) {
        throw 'Cannot clear derived-SWF recovery material before source recovery.'
    }
    if (-not (Test-Path -LiteralPath $Transaction.SidecarPath) -or
        [System.IO.File]::ReadAllText(
            $Transaction.SidecarPath,
            [System.Text.Encoding]::UTF8) -cne
            $Transaction.SidecarBody -or
        [string]$Transaction.Record.phase -cne 'restored') {
        throw 'Derived-SWF sidecar is not in its verified restored phase.'
    }
    [void](Assert-PlayerInfoRestoredSwfIdentity -Transaction $Transaction)
    if ($Transaction.BackupPath -and
        (Test-Path -LiteralPath $Transaction.BackupPath)) {
        $backup = Get-FileIdentity -Path $Transaction.BackupPath
        if ($backup.length -ne [int64]$Transaction.Record.original.bytes -or
            $backup.sha256 -cne [string]$Transaction.Record.original.sha256) {
            throw 'Derived-SWF backup drifted before cleanup.'
        }
        Remove-Item -LiteralPath $Transaction.BackupPath -Force
    }
    Remove-Item -LiteralPath $Transaction.SidecarPath -Force
    if ((Test-Path -LiteralPath $Transaction.SidecarPath) -or
        ($Transaction.BackupPath -and
         (Test-Path -LiteralPath $Transaction.BackupPath))) {
        throw 'Derived-SWF recovery artifacts remain after cleanup.'
    }
    if ((Test-Path -LiteralPath $Transaction.RecoveryDirectory) -and
        @(Get-ChildItem -LiteralPath $Transaction.RecoveryDirectory -Force).
            Count -eq 0) {
        Remove-Item -LiteralPath $Transaction.RecoveryDirectory -Force
    }
}

function Assert-OracleTemplate {
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Oracle TestLoader template is missing: $templatePath"
    }
    if (-not (Test-Utf8Bom -Path $templatePath)) {
        throw 'Oracle TestLoader template must be UTF-8 with BOM.'
    }
    $source = [System.IO.File]::ReadAllText(
        $templatePath, [System.Text.Encoding]::UTF8)
    if ([regex]::Matches(
            $source, '__PLAYER_INFO_ORACLE_RUN_ID__').Count -ne 1) {
        throw 'Oracle template must contain exactly one runId placeholder.'
    }
    $required = @(
        'var __pioRuntimeUrl:String = "../flashswf/UI/玩家信息界面.swf"',
        'var __pioCanvasHeight:Number = 576',
        'var __pioMainPlacementY:Number = 512',
        'var __pioPartChars:Number = 720',
        '#include "展现/UI交互/UI交互_fs_玩家信息界面.as"',
        '_root._quality = "MEDIUM"',
        'Stage.align = "TL"',
        '"|stageAlign=" + String(Stage.align)',
        '_root.控制目标 = "oracleHero"',
        '_root.gameworld.oracleHero',
        'MovieClipLoader',
        'onLoadInit',
        'target._url',
        'escapedUrl=',
        'runtimeUrlEscaped=',
        'new BitmapData(',
        '0x00000000',
        'bitmap.draw(',
        '__pioUi,',
        'new Matrix(1, 0, 0, 1, 0, __pioMainPlacementY)',
        'placementProfile=main_rsl_exported_symbol_equivalent',
        'referencePlacementProfile=main_rsl_exported_symbol',
        'extractionMode=loaded_child_exported_symbol_instance',
        'mainParticipatesInCapture=0',
        'mainBinaryRole=identity_chain_reference_only',
        'childDocumentWrapperApplied=0',
        'exportedSymbolRootTy=0',
        '"PART"',
        '"CLEAR"',
        '|partCount=',
        '|b64=',
        'partsPerRow=8',
        'partRecordMaxChars=1000',
        'zeroRowRecord=CLEAR',
        'zeroRowArgb=00000000',
        'HP当前值',
        'MP数据显示',
        '网格动画',
        '血槽内动画',
        '血槽光效',
        'outOfScopeHidden'
    )
    foreach ($literal in $required) {
        if ($source.IndexOf($literal, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Oracle template is missing required literal: $literal"
        }
    }
    if ($source -match '\bCHUNK\b' -or
        $source -match 'childUrlMatched' -or
        $source -match 'indexOf\("玩家信息界面\.swf"\)' -or
        $source -match 'bitmap\.draw\(__pioHolder') {
        throw (
            'Oracle template retains an obsolete CHUNK, filename-substring ' +
            'binding, or standalone document-wrapper draw.')
    }
    $expectedTemplateCases = @(
        [pscustomobject]@{ caseId = 'empty'; hp = 0; mp = 0 },
        [pscustomobject]@{ caseId = 'min_step'; hp = 100; mp = 100 },
        [pscustomobject]@{ caseId = 'p25'; hp = 3200; mp = 2500 },
        [pscustomobject]@{ caseId = 'p50'; hp = 6400; mp = 5000 },
        [pscustomobject]@{ caseId = 'p75'; hp = 9600; mp = 7500 },
        [pscustomobject]@{ caseId = 'p99'; hp = 12672; mp = 9900 },
        [pscustomobject]@{ caseId = 'full'; hp = 12800; mp = 10000 },
        [pscustomobject]@{ caseId = 'mp_vf34'; hp = 8576; mp = 6700 },
        [pscustomobject]@{ caseId = 'mp_vf35'; hp = 8448; mp = 6600 },
        [pscustomobject]@{ caseId = 'mp_vf70'; hp = 3968; mp = 3100 },
        [pscustomobject]@{ caseId = 'mp_vf91'; hp = 1280; mp = 1000 }
    )
    foreach ($expectedCase in $expectedTemplateCases) {
        $caseId = [string]$expectedCase.caseId
        if ([regex]::Matches(
                $source, 'caseId:"' + [regex]::Escape($caseId) + '"').Count -ne 1) {
            throw "Oracle template must define case exactly once: $caseId"
        }
        $literal = (
            '{caseId:"' + $caseId +
            '", hp:' + [string]$expectedCase.hp +
            ', mp:' + [string]$expectedCase.mp + '}')
        if ([regex]::Matches(
                $source, [regex]::Escape($literal)).Count -ne 1) {
            throw "Oracle template case values drifted: $caseId"
        }
    }
    if ([regex]::Matches($source, 'caseId:"').Count -ne 11) {
        throw 'Oracle template defines a case outside the fixed eleven-case corpus.'
    }
    foreach ($pair in @(@('{', '}'), @('(', ')'), @('[', ']'))) {
        $openCount = [regex]::Matches(
            $source, [regex]::Escape($pair[0])).Count
        $closeCount = [regex]::Matches(
            $source, [regex]::Escape($pair[1])).Count
        if ($openCount -ne $closeCount) {
            throw "Oracle template delimiter count is unbalanced: $($pair -join ' ')."
        }
    }
    foreach ($pattern in @(
        '\bSharedObject\b',
        '\bSaveManager\b',
        '\bServerManager\b',
        '\bAgentControl\b',
        '/console',
        '\bloadVariables(?:Num)?\b',
        '\bXMLSocket\b',
        '\bgetURL\s*\('
    )) {
        if ($source -match $pattern) {
            throw "Oracle template contains forbidden surface: $pattern"
        }
    }
    if ($source -match 'TargetCacheManager\s*\.\s*findHero\s*=' -or
        $source -match 'StringUtils\s*\.\s*padStart\s*=') {
        throw 'Oracle template monkey-patches a production helper.'
    }
    $worstPartLine = (
        'PLAYER_INFO_ORACLE|PART|runId=' + ('f' * 32) +
        '|caseId=min_step|row=575|part=7|partCount=8|b64=' + ('A' * 720))
    if ($worstPartLine.Length -gt 1000 -or
        $worstPartLine -match '[^\x00-\x7F]') {
        throw 'Static PART boundary proof exceeds 1000 ASCII characters.'
    }
    return [pscustomobject]@{
        source = $source
        sha256 = Get-PathSha256 -Path $templatePath
        staticWorstPartChars = $worstPartLine.Length
    }
}

function Assert-RunnerStaticContract {
    if (-not (Test-Utf8Bom -Path $PSCommandPath) -or
        -not (Test-Utf8Bom -Path $protocolHelperPath)) {
        throw 'Runner and protocol helper must be UTF-8 with BOM.'
    }
    $source = [System.IO.File]::ReadAllText(
        $PSCommandPath, [System.Text.Encoding]::UTF8)
    foreach ($literal in @(
        "Local\CF7_FlashCompile_",
        'New-Cf7TestLoaderScratchTransaction',
        'New-PlayerInfoDerivedSwfTransaction',
        'Freeze-PlayerInfoDerivedSwfCompiledIdentity',
        'Get-PlayerInfoCompileRecoveryDecision',
        'Get-ExactFlashCs6TaskRegistration',
        'Cf7PlayerInfoFlashProcessPathNativeMethodsR10',
        'PROCESS_QUERY_LIMITED_INFORMATION = 0x1000',
        'QueryFullProcessImageNameW',
        'Get-Cf7PlayerInfoFlashProcessImagePathLimited',
        'Assert-Cf7PlayerInfoFlashAuthoringPath',
        'Get-RegisteredFlashDebugPlayerIdentity',
        'Assert-RegisteredFlashDebugPlayerCurrent',
        'Get-PlayerInfoStandaloneLaunchPlan',
        'Players\Debug\FlashPlayerDebugger.exe',
        'Get-StrictCaptureToolingSet',
        'Assert-StrictCaptureToolingCurrent',
        'Assert-PlayerInfoCaptureToolingBindings',
        'Restore-PlayerInfoDerivedSwfTransaction',
        'Assert-PlayerInfoRestoredSwfIdentity',
        'Complete-PlayerInfoDerivedSwfCleanup',
        'Restore-Cf7TestLoaderScratchTransaction',
        'CF7_FLASH_COMPILE_LEASE',
        '-Target test',
        '-PublishOnly',
        "-VerifySwf 'scripts/TestLoader.swf'",
        'Start-Process',
        '-PassThru',
        'WaitForExit',
        'requiredStablePolls = 4',
        'Get-StableFinalFlashLog',
        'Test-PlayerInfoOracleTrace',
        'Stop-OwnedPlayerFailClosed',
        "'.incomplete-'",
        'loader-TestLoader.swf',
        'flashlog-fresh.bin',
        'oracle-run-block.txt',
        'oracle-run-summary.canonical.txt',
        'canonicalRunSummary',
        'captureTooling',
        'strictToolIdentity',
        'cf7.player_info.flash_oracle_manifest.v2',
        'cf7.player_info.flash_oracle_candidate_receipt.v2',
        'main-identity-reference.swf',
        'identity_chain_reference_only',
        'main_rsl_exported_symbol_equivalent',
        'Test-PlayerInfoOracleContractMember',
        'Assert-PlayerInfoOracleV2ManifestContract',
        'Assert-PlayerInfoOracleV2ReceiptContract',
        'Invoke-PlayerInfoOracleV2ArtifactContractSelfTest',
        'restoredSwfIdentityVerifiedUnderMutex',
        'Assert-CandidateSnapshotSet',
        'compile-output.txt',
        'compiler-errors.txt',
        'Restore-Cf7TestLoaderScratchTransaction',
        'Move-Item -LiteralPath $workDir -Destination $finalRunDir'
    )) {
        if ($source.IndexOf($literal, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Capture runner is missing static contract literal: $literal"
        }
    }
    if ([regex]::Matches(
            $source, '(?m)^\s*\$ownedPlayer\s*=\s*Start-Process\b').Count -ne 1) {
        throw 'Capture runner must start exactly one owned player process.'
    }
    if ($source -match 'flash_oracle_manifest\.v1' -or
        $source -match 'flash_oracle_candidate_receipt\.v1') {
        throw 'Capture runner retains a historical v1 manifest or receipt schema.'
    }
    $authoringDefinition =
        (Get-Command Get-FlashAuthoringIdentity -ErrorAction Stop).Definition
    if ($authoringDefinition.IndexOf(
            'Get-Cf7PlayerInfoFlashProcessImagePathLimited',
            [System.StringComparison]::Ordinal) -lt 0 -or
        $authoringDefinition -match '(?i)\.MainModule\b' -or
        $authoringDefinition -match '(?i)\$_\.Path\b') {
        throw (
            'Flash authoring identity must use only the limited-information ' +
            'process-image-path helper.')
    }
    $argumentListLinePattern =
        '(?m)^[ \t]*-ArgumentList[ \t]+\$playerLaunchPlan\.argumentToken[ \t]*`[ \t]*\r?$'
    $workingDirectoryLinePattern =
        '(?m)^[ \t]*-WorkingDirectory[ \t]+\$scriptsDir[ \t]*`[ \t]*\r?$'
    if ([regex]::Matches(
            $source, '(?m)^[ \t]*-ArgumentList\b').Count -ne 1 -or
        [regex]::Matches(
            $source, $argumentListLinePattern).Count -ne 1 -or
        [regex]::Matches(
            $source, '(?m)^[ \t]*-WorkingDirectory\b').Count -ne 1 -or
        [regex]::Matches(
            $source, $workingDirectoryLinePattern).Count -ne 1) {
        throw (
            'Owned player launch must use only the unquoted TestLoader.swf token ' +
            'from the scripts working directory.')
    }
    if ($source -notmatch (
            '(?m)^\s*captureRunner\s*=\s*New-FrozenFileInput\b') -or
        $source -notmatch (
            '(?m)^\s*protocolHelper\s*=\s*New-FrozenFileInput\b')) {
        throw 'Runner/protocol tooling must be part of immutable frozenInputs.'
    }
    if ([regex]::Matches($source, '\.Kill\(\)').Count -ne 1 -or
        $source -match '\bCloseMainWindow\b' -or
        $source -match '(?im)^\s*Stop-Process\b' -or
        $source -match 'Get-Process\s+-Name\s+[^F\r\n]*Player') {
        throw 'Capture runner may kill only its exact owned PID and may not close by name.'
    }
    $releaseIndex = $source.LastIndexOf(
        '$compileMutex.ReleaseMutex()',
        [System.StringComparison]::Ordinal)
    $strictToolIndex = $source.LastIndexOf(
        '$strictCaptureTooling = Get-StrictCaptureToolingSet',
        [System.StringComparison]::Ordinal)
    $mutexCreateIndex = $source.LastIndexOf(
        '$compileMutex = [System.Threading.Mutex]::new',
        [System.StringComparison]::Ordinal)
    $promotionIndex = $source.LastIndexOf(
        'Move-Item -LiteralPath $workDir -Destination $finalRunDir',
        [System.StringComparison]::Ordinal)
    if ($strictToolIndex -lt 0 -or
        $mutexCreateIndex -le $strictToolIndex -or
        $source.Substring(
            $strictToolIndex,
            $mutexCreateIndex - $strictToolIndex).IndexOf(
                '-RequireStrict',
                [System.StringComparison]::Ordinal) -lt 0) {
        throw 'True capture must establish strict tool identity before its mutex.'
    }
    if ($releaseIndex -lt 0 -or $promotionIndex -le $releaseIndex) {
        throw 'Candidate promotion must occur after mutex release and scratch cleanup.'
    }
    $sourceCreateIndex = $source.LastIndexOf(
        '$scratchTransaction = New-Cf7TestLoaderScratchTransaction',
        [System.StringComparison]::Ordinal)
    $swfCreateIndex = $source.LastIndexOf(
        '$derivedSwfTransaction = New-PlayerInfoDerivedSwfTransaction',
        [System.StringComparison]::Ordinal)
    $swfRestoreIndex = $source.LastIndexOf(
        'Restore-PlayerInfoDerivedSwfTransaction',
        [System.StringComparison]::Ordinal)
    $sourceRestoreIndex = $source.LastIndexOf(
        'Restore-Cf7TestLoaderScratchTransaction',
        [System.StringComparison]::Ordinal)
    $derivedCleanupIndex = $source.LastIndexOf(
        'Complete-PlayerInfoDerivedSwfCleanup',
        [System.StringComparison]::Ordinal)
    $underMutexIdentityIndex = $source.LastIndexOf(
        '$restoredIdentityVerifiedUnderMutex = $true',
        [System.StringComparison]::Ordinal)
    if ($sourceCreateIndex -lt 0 -or
        $swfCreateIndex -le $sourceCreateIndex -or
        $swfRestoreIndex -lt 0 -or
        $sourceRestoreIndex -le $swfRestoreIndex -or
        $underMutexIdentityIndex -le $sourceRestoreIndex -or
        $derivedCleanupIndex -le $underMutexIdentityIndex -or
        $derivedCleanupIndex -le $sourceRestoreIndex -or
        $releaseIndex -le $derivedCleanupIndex) {
        throw (
            'Source/SWF transaction order must be marker-first, SWF-first restore, ' +
            'source restore, sidecar cleanup, then mutex release.')
    }
    $postReleaseSegment = $source.Substring(
        $releaseIndex, $promotionIndex - $releaseIndex)
    if ($postReleaseSegment -match '\$loaderSwfPath\b' -or
        $postReleaseSegment -match '\bAssert-FrozenFileInputCurrent\b' -or
        $postReleaseSegment -match '\bGet-FileIdentity\b') {
        throw (
            'Post-release finalization may verify only immutable candidate ' +
            'snapshots and manifest/receipt files.')
    }
    $obsoleteEvidenceTokens = @(
        ('redacted' + 'RunBlock'),
        ('oracle-run-block.' + 'redacted'),
        ('ConvertTo-PlayerInfoOracle' + 'RedactedBlock')
    )
    foreach ($obsolete in $obsoleteEvidenceTokens) {
        if ($source.IndexOf(
                $obsolete,
                [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw 'Runner retains obsolete mixed-block redaction evidence.'
        }
    }
}

function Get-GitCanonicalIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$AbsolutePath
    )

    $oidOutput = @(& git -C $projectDir hash-object `
        "--path=$RelativePath" -- $AbsolutePath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git hash-object --path failed for $RelativePath`: $($oidOutput -join ' ')"
    }
    $oid = (($oidOutput -join '').Trim()).ToLowerInvariant()
    if ($oid -notmatch '^[0-9a-f]{40}$') {
        throw "git hash-object returned an invalid OID for $RelativePath."
    }
    $gitPath = (Get-Command git -ErrorAction Stop).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gitPath
    $startInfo.WorkingDirectory = $projectDir
    $startInfo.Arguments = "cat-file blob $oid"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $memory = [System.IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) {
            throw "Could not start git cat-file for $RelativePath."
        }
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git cat-file failed for $RelativePath`: $stderr"
        }
        $bytes = $memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
    return [pscustomobject]@{
        oid = $oid
        bytes = $bytes.Length
        sha256 = (
            Get-PlayerInfoOracleBytesSha256 -Bytes $bytes).ToLowerInvariant()
    }
}

function Get-GitRevisionPathOid {
    param(
        [Parameter(Mandatory = $true)][string]$Spec,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $output = @(& git -C $projectDir rev-parse --verify $Spec 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git rev-parse failed for $Label`: $($output -join ' ')"
    }
    $oid = (($output -join '').Trim()).ToLowerInvariant()
    if ($oid -notmatch '^[0-9a-f]{40}$') {
        throw "git rev-parse returned an invalid blob OID for $Label."
    }
    return $oid
}

function Get-StrictCaptureToolIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)]$Frozen,
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string]$HeadCommit,
        [switch]$RequireStrict
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('..') -or
        $RelativePath -match '\\') {
        throw "Capture-tool path is not a safe repo-relative Git path: $RelativePath"
    }
    Assert-FrozenFileInputCurrent -Frozen $Frozen
    $headOid = Get-GitRevisionPathOid `
        -Spec ($HeadCommit + ':' + $RelativePath) `
        -Label ('HEAD ' + $RelativePath)
    $indexOid = Get-GitRevisionPathOid `
        -Spec (':' + $RelativePath) `
        -Label ('index ' + $RelativePath)
    $cleanOutput = @(& git -C $projectDir hash-object `
        "--path=$RelativePath" -- $Frozen.path 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (
            "git hash-object --path failed for $RelativePath`: " +
            ($cleanOutput -join ' '))
    }
    $cleanOid = (($cleanOutput -join '').Trim()).ToLowerInvariant()
    if ($cleanOid -notmatch '^[0-9a-f]{40}$') {
        throw "git hash-object returned an invalid OID for $RelativePath."
    }
    Assert-FrozenFileInputCurrent -Frozen $Frozen
    $strict = $headOid -ceq $indexOid -and $headOid -ceq $cleanOid
    $canonical = $null
    if ($strict) {
        $canonical = Get-GitCanonicalIdentity `
            -RelativePath $RelativePath `
            -AbsolutePath $Frozen.path
        Assert-FrozenFileInputCurrent -Frozen $Frozen
        if ($canonical.oid -cne $headOid) {
            throw "Strict capture-tool blob changed during verification: $RelativePath"
        }
    }
    if ($RequireStrict -and -not $strict) {
        throw (
            'True capture requires HEAD/index/clean-filter blob identity equality: ' +
            "$RelativePath; HEAD=$headOid; index=$indexOid; clean=$cleanOid")
    }
    return [pscustomobject]@{
        status = if ($strict) { 'strict' } else { 'pending' }
        path = $RelativePath
        sha256 = [string]$Frozen.sha256
        bytes = [long]$Frozen.length
        gitBlobOid = if ($strict) { $headOid } else { $null }
        gitBlobBytes = if ($strict) { [long]$canonical.bytes } else { $null }
        gitBlobSha256 = if ($strict) {
            ([string]$canonical.sha256).ToUpperInvariant()
        } else {
            $null
        }
        headBlobOid = $headOid
        indexBlobOid = $indexOid
        cleanFilterBlobOid = $cleanOid
        headIndexCleanFilterEqual = $strict
    }
}

function Get-StrictCaptureToolingSet {
    param(
        [Parameter(Mandatory = $true)]$RunnerFrozen,
        [Parameter(Mandatory = $true)]$ProtocolFrozen,
        [switch]$RequireStrict
    )

    $headOutput = @(& git -C $projectDir rev-parse --verify HEAD 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not resolve capture-tool HEAD: $($headOutput -join ' ')"
    }
    $headCommit = (($headOutput -join '').Trim()).ToLowerInvariant()
    if ($headCommit -notmatch '^[0-9a-f]{40}$') {
        throw 'Capture-tool HEAD is not a full commit OID.'
    }
    $runner = Get-StrictCaptureToolIdentity `
        -RelativePath $captureRunnerRelativePath `
        -Frozen $RunnerFrozen `
        -HeadCommit $headCommit `
        -RequireStrict:$RequireStrict
    $protocol = Get-StrictCaptureToolIdentity `
        -RelativePath $protocolHelperRelativePath `
        -Frozen $ProtocolFrozen `
        -HeadCommit $headCommit `
        -RequireStrict:$RequireStrict
    $headAfter = @(& git -C $projectDir rev-parse --verify HEAD 2>&1)
    if ($LASTEXITCODE -ne 0 -or
        (($headAfter -join '').Trim()).ToLowerInvariant() -cne $headCommit) {
        throw 'Capture-tool HEAD changed during strict identity verification.'
    }
    return [pscustomobject]@{
        status = if (
            $runner.status -ceq 'strict' -and
            $protocol.status -ceq 'strict') {
            'strict'
        } else {
            'pending'
        }
        headCommit = $headCommit
        runner = $runner
        protocol = $protocol
    }
}

function Assert-StrictCaptureToolingCurrent {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$RunnerFrozen,
        [Parameter(Mandatory = $true)]$ProtocolFrozen
    )

    $current = Get-StrictCaptureToolingSet `
        -RunnerFrozen $RunnerFrozen `
        -ProtocolFrozen $ProtocolFrozen `
        -RequireStrict
    if ([string]$current.headCommit -cne [string]$Expected.headCommit -or
        [string]$current.runner.gitBlobOid -cne
            [string]$Expected.runner.gitBlobOid -or
        [string]$current.protocol.gitBlobOid -cne
            [string]$Expected.protocol.gitBlobOid -or
        [string]$current.runner.sha256 -cne
            [string]$Expected.runner.sha256 -or
        [string]$current.protocol.sha256 -cne
            [string]$Expected.protocol.sha256) {
        throw 'Strict capture tooling changed during the mutex-held capture.'
    }
}

function Assert-ExactNumberArray {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Actual.Count -ne $Expected.Count) {
        throw "$Label length mismatch."
    }
    for ($index = 0; $index -lt $Actual.Count; $index++) {
        if ([math]::Abs(
                [double]($Actual[$index]) -
                [double]($Expected[$index])) -gt 0.000000000001) {
            throw "$Label differs at index $index."
        }
    }
}

function Assert-B001CaptureEvidence {
    $closure = [System.IO.File]::ReadAllText(
        $closurePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $chain = [System.IO.File]::ReadAllText(
        $chainPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$closure.format -cne 'cf7.player-info-hud.placement-closure' -or
        [int]$closure.formatVersion -ne 2 -or
        [string]$closure.evidenceRevision -cne 'b0-01a-r4' -or
        [string]$closure.status -cne 'placement_closure_frozen') {
        throw 'B0-01A closure evidence is not the frozen r4 contract.'
    }
    $files = @($closure.files)
    if ($files.Count -ne 16 -or [int]$closure.scope.fileCount -ne 16) {
        throw 'B0-01A closure evidence no longer contains exactly 16 files.'
    }
    $cardinality = $closure.scope.placementCardinality
    if ([int]$cardinality.authoredDefinitionEdges -ne 17 -or
        [int]$cardinality.pathExpandedRuntimeEdges -ne 18 -or
        [int]$cardinality.stageEdges -ne 1 -or
        [int]$cardinality.hpBranchEdges -ne 12 -or
        [int]$cardinality.mpBranchEdges -ne 5 -or
        [int]$cardinality.sharedDefinitionEdgesExpandedTwice -ne 1) {
        throw 'B0-01A placement cardinality is not the reviewed 17/18 contract.'
    }
    $hasGitCanonicalFields = @($files | Where-Object {
        $null -ne $_.gitBlobBytes -and
        -not [string]::IsNullOrWhiteSpace([string]$_.gitBlobSha256)
    }).Count -eq 16
    $digestLines = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        $relative = [string]$file.path
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [System.IO.Path]::IsPathRooted($relative) -or
            $relative.Contains('..')) {
            throw "Unsafe B0-01A closure path: $relative"
        }
        $absolute = Join-Path $projectDir $relative
        if (-not (Test-Path -LiteralPath $absolute)) {
            throw "B0-01A closure input is missing: $relative"
        }
        $identity = Get-GitCanonicalIdentity `
            -RelativePath $relative -AbsolutePath $absolute
        if ($identity.oid -cne ([string]$file.gitBlobOid).ToLowerInvariant()) {
            throw "B0-01A Git-canonical blob drifted: $relative"
        }
        if ($hasGitCanonicalFields) {
            if ($identity.bytes -ne [int64]$file.gitBlobBytes -or
                $identity.sha256 -cne
                ([string]$file.gitBlobSha256).ToLowerInvariant()) {
                throw "B0-01A Git-canonical bytes/SHA drifted: $relative"
            }
            $digestLines.Add(
                $relative + "`t" + $identity.sha256 + "`n")
        }
    }
    $reproducedDigest = $null
    if ($hasGitCanonicalFields) {
        $orderedLines = $digestLines.ToArray()
        [System.Array]::Sort($orderedLines, [System.StringComparer]::Ordinal)
        $reproducedDigest = (
            Get-PlayerInfoOracleBytesSha256 -Bytes (
                [System.Text.Encoding]::UTF8.GetBytes($orderedLines -join '')
            )).ToLowerInvariant()
        if ($reproducedDigest -cne
            ([string]$closure.closureDigest.value).ToLowerInvariant()) {
            throw 'B0-01A Git-canonical closure digest does not reproduce.'
        }
        if ($reproducedDigest -cne
            '6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368') {
            throw 'B0-01A Git-canonical closure digest is not the reviewed r4 digest.'
        }
    }

    $standaloneProfile =
        $closure.rootPlacementProfiles.standaloneChildDocumentWrapper
    $mainRslProfile = $closure.rootPlacementProfiles.mainRslExportedSymbol
    if ([string]$standaloneProfile.profileId -cne
            'standalone_child_document_wrapper' -or
        [bool]$standaloneProfile.mainRuntimeEquivalent -or
        [string]$mainRslProfile.profileId -cne
            'main_rsl_exported_symbol' -or
        -not [bool]$mainRslProfile.runtimeTruth -or
        [bool]$mainRslProfile.documentWrapperApplied) {
        throw 'B0-01A r4 placement-profile identities drifted.'
    }
    Assert-ExactNumberArray `
        -Actual @($standaloneProfile.rootMatrix) `
        -Expected @(1, 0, 0, 1, 0, 3) `
        -Label 'B0-01A standalone child wrapper matrix'
    Assert-ExactNumberArray `
        -Actual @($standaloneProfile.hpComposedMatrix) `
        -Expected @(0.847213745117188, 0, 0, 0.847213745117188, 37.75, 5.65) `
        -Label 'B0-01A standalone child HP matrix'
    Assert-ExactNumberArray `
        -Actual @($standaloneProfile.mpComposedMatrix) `
        -Expected @(1.0810546875, 0, 0, 1.0810546875, 90.1, -1.3) `
        -Label 'B0-01A standalone child MP matrix'
    Assert-ExactNumberArray `
        -Actual @($mainRslProfile.rootMatrix) `
        -Expected @(1, 0, 0, 1, 0, 0) `
        -Label 'B0-01A main RSL exported-symbol root matrix'
    Assert-ExactNumberArray `
        -Actual @($mainRslProfile.hpRelativeMatrix) `
        -Expected @(0.847213745117188, 0, 0, 0.847213745117188, 37.75, 2.65) `
        -Label 'B0-01A main RSL HP matrix'
    Assert-ExactNumberArray `
        -Actual @($mainRslProfile.mpRelativeMatrix) `
        -Expected @(1.0810546875, 0, 0, 1.0810546875, 90.1, -4.3) `
        -Label 'B0-01A main RSL MP matrix'

    if ([string]$chain.format -cne 'cf7.player-info-hud.source-binary-chain' -or
        [int]$chain.formatVersion -ne 2 -or
        [string]$chain.evidenceRevision -cne 'b0-01a-r4' -or
        [string]$chain.status -cne 'repository_ancestry_verified' -or
        -not [bool]$chain.reviewBaseline.
            relevantTrackedPathsMatchHeadInIndexAndAfterCleanFilter -or
        -not [bool]$chain.conclusions.repositoryAncestryVerified -or
        [bool]$chain.conclusions.reproducibleBuildReceiptPresent) {
        throw 'B0-01A source-binary chain is not the ancestry-only r4 contract.'
    }
    $captureLoader = $chain.runtimeRelationship.captureLoaderContract
    if ([string]$captureLoader.plannedLoaderPath -cne 'scripts/TestLoader.swf' -or
        [bool]$captureLoader.actualCaptureLoaderVerified -or
        [bool]$captureLoader.mainParticipatesInCapture -or
        [bool]$captureLoader.asLoaderParticipatesInCapture -or
        [string]$captureLoader.childPathToVerify -cne $uiSwfRelativePath -or
        [string]$captureLoader.capturePlacementProfile -cne
            'standalone_child_document_wrapper' -or
        [bool]$captureLoader.capturesMainRslPlacement -or
        [bool]$chain.conclusions.actualCaptureProcessLoadVerified -or
        -not [bool]$chain.conclusions.mainRslPlacementContractVerified -or
        [bool]$chain.conclusions.standaloneCaptureEquivalentToMainRsl -or
        [bool]$chain.conclusions.oracleFrozen -or
        [string]$chain.conclusions.allowedStatus -cne
            'placement_closure_frozen') {
        throw 'B0-01A r4 capture-loader handoff contract drifted.'
    }
    $chainStandalone =
        $chain.runtimeRelationship.placementProfiles.standaloneChildDocumentWrapper
    $chainMainRsl =
        $chain.runtimeRelationship.placementProfiles.mainRslExportedSymbol
    if ([string]$chainStandalone.profileId -cne
            [string]$standaloneProfile.profileId -or
        [bool]$chainStandalone.mainRuntimeEquivalent -or
        [string]$chainMainRsl.profileId -cne
            [string]$mainRslProfile.profileId -or
        -not [bool]$chainMainRsl.runtimeTruth -or
        [bool]$chainMainRsl.childDocumentWrapperApplied) {
        throw 'B0-01A closure/source-binary placement profiles disagree.'
    }
    Assert-ExactNumberArray `
        -Actual @($chainStandalone.documentWrapperMatrix) `
        -Expected @($standaloneProfile.rootMatrix) `
        -Label 'B0-01A chain standalone wrapper matrix'
    Assert-ExactNumberArray `
        -Actual @($chainStandalone.hpRelativeToLoadedChildStage) `
        -Expected @($standaloneProfile.hpComposedMatrix) `
        -Label 'B0-01A chain standalone HP matrix'
    Assert-ExactNumberArray `
        -Actual @($chainStandalone.mpRelativeToLoadedChildStage) `
        -Expected @($standaloneProfile.mpComposedMatrix) `
        -Label 'B0-01A chain standalone MP matrix'
    Assert-ExactNumberArray `
        -Actual @($chainMainRsl.exportedSymbolRootMatrixWithinMainInstance) `
        -Expected @($mainRslProfile.rootMatrix) `
        -Label 'B0-01A chain main RSL root matrix'
    Assert-ExactNumberArray `
        -Actual @($chainMainRsl.hpRelativeToMainInstance) `
        -Expected @($mainRslProfile.hpRelativeMatrix) `
        -Label 'B0-01A chain main RSL HP matrix'
    Assert-ExactNumberArray `
        -Actual @($chainMainRsl.mpRelativeToMainInstance) `
        -Expected @($mainRslProfile.mpRelativeMatrix) `
        -Label 'B0-01A chain main RSL MP matrix'
    $child = @($chain.binaries | Where-Object {
        [string]$_.role -ceq 'child' -and
        [string]$_.path -ceq $uiSwfRelativePath
    })
    if ($child.Count -ne 1 -or -not [bool]$child[0].identical) {
        throw 'B0-01A source-binary chain has no unique identical child entry.'
    }
    $chainUiHash = (
        [string]$child[0].reviewBaseline.sha256).ToUpperInvariant()
    if ($chainUiHash -cne (Get-PathSha256 -Path $uiSwfPath)) {
        throw 'Current child SWF does not match B0-01A source-binary ancestry.'
    }
    $main = @($chain.binaries | Where-Object {
        [string]$_.role -ceq 'main' -and
        [string]$_.path -ceq $mainSwfRelativePath
    })
    if ($main.Count -ne 1) {
        throw 'B0-01A source-binary chain has no unique main identity entry.'
    }
    $chainMainHash = (
        [string]$main[0].reviewBaseline.sha256).ToUpperInvariant()
    if ($chainMainHash -cne (Get-PathSha256 -Path $mainSwfPath)) {
        throw 'Current main SWF does not match B0-01A identity-chain evidence.'
    }
    $formula = @($chain.sourceLinkEvidence | Where-Object {
        [string]$_.path -ceq $formulaRelativePath
    })
    if ($formula.Count -ne 1) {
        throw 'B0-01A source-link evidence has no unique display formula.'
    }
    $formulaIdentity = Get-GitCanonicalIdentity `
        -RelativePath $formulaRelativePath -AbsolutePath $formulaPath
    $expectedFormulaOid = if ($formula[0].worktree.gitBlobOid) {
        [string]$formula[0].worktree.gitBlobOid
    } else {
        [string]$formula[0].reviewBaseline.gitBlobOid
    }
    if ($formulaIdentity.oid -cne $expectedFormulaOid.ToLowerInvariant()) {
        throw 'Current display formula does not match Git-canonical source-link evidence.'
    }
    return [pscustomobject]@{
        evidenceRevision = [string]$closure.evidenceRevision
        closureDigest = if ($reproducedDigest) {
            $reproducedDigest
        } else {
            [string]$closure.closureDigest.value
        }
        sourceBinaryRevision = [string]$chain.evidenceRevision
        chainUiSha256 = $chainUiHash
        gitCanonicalSchema = $hasGitCanonicalFields
        authoredDefinitionEdges = 17
        pathExpandedRuntimeEdges = 18
        capturePlacementProfile = 'main_rsl_exported_symbol_equivalent'
        captureReferencePlacementProfile = [string]$mainRslProfile.profileId
        captureMainRslPlacementEquivalent = $true
        captureExtractionMode = 'loaded_child_exported_symbol_instance'
        captureMainParticipates = $false
        captureMainBinaryRole = 'identity_chain_reference_only'
        captureChildDocumentWrapperApplied = $false
        captureExportedSymbolRootTy = 0
        captureMainPlacementY = 512
        captureCanvas = @(1024, 576)
        chainMainSha256 = $chainMainHash
        standaloneDocumentWrapperMatrix = @($standaloneProfile.rootMatrix)
        mainRslPlacementProfile = [string]$mainRslProfile.profileId
        mainRslExportedSymbolRootMatrix = @($mainRslProfile.rootMatrix)
        mainRslHpRelativeMatrix = @($mainRslProfile.hpRelativeMatrix)
        mainRslMpRelativeMatrix = @($mainRslProfile.mpRelativeMatrix)
    }
}

function Test-PlayerInfoOracleContractMember {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -is [System.Collections.IDictionary]) {
        return [bool]$Value.Contains($Name)
    }
    return $null -ne $Value.PSObject.Properties[$Name]
}

function Assert-PlayerInfoOracleV2ManifestContract {
    param([Parameter(Mandatory = $true)]$Manifest)

    if ([string]$Manifest.schema -cne
            'cf7.player_info.flash_oracle_manifest.v2' -or
        [string]$Manifest.status -cne 'candidate' -or
        -not [bool]$Manifest.requiresHumanReview) {
        throw 'Flash oracle manifest is not the current v2 candidate contract.'
    }
    $placement = $Manifest.source.placementClosure
    if ([string]$placement.capturedPlacementProfile -cne
            'main_rsl_exported_symbol_equivalent' -or
        [string]$placement.referencePlacementProfile -cne
            'main_rsl_exported_symbol' -or
        -not [bool]$placement.mainRslPlacementEquivalent -or
        [string]$placement.extractionMode -cne
            'loaded_child_exported_symbol_instance' -or
        [bool]$placement.mainParticipatesInCapture -or
        [string]$placement.mainBinaryRole -cne
            'identity_chain_reference_only' -or
        [bool]$placement.childDocumentWrapperApplied -or
        [int]$placement.exportedSymbolRootTy -ne 0 -or
        [int]$placement.mainPlacementY -ne 512 -or
        (Test-PlayerInfoOracleContractMember `
            -Value $placement -Name 'mainRuntimeEquivalent')) {
        throw 'Flash oracle manifest placement semantics drifted from v2.'
    }
    $loader = $Manifest.source.captureLoaderContract
    if (-not [bool]$loader.actualCaptureLoaderVerified -or
        [string]$loader.actualLoaderPath -cne 'scripts/TestLoader.swf' -or
        [string]$loader.childPathVerified -cne $uiSwfRelativePath -or
        [string]$loader.placementProfile -cne
            'main_rsl_exported_symbol_equivalent' -or
        [string]$loader.referencePlacementProfile -cne
            'main_rsl_exported_symbol' -or
        [string]$loader.extractionMode -cne
            'loaded_child_exported_symbol_instance' -or
        -not [bool]$loader.mainRslPlacementEquivalent -or
        [bool]$loader.mainParticipatesInCapture -or
        [string]$loader.mainBinaryRole -cne
            'identity_chain_reference_only' -or
        [bool]$loader.asLoaderParticipatesInCapture -or
        [bool]$loader.childDocumentWrapperApplied -or
        [int]$loader.exportedSymbolRootTy -ne 0 -or
        [int]$loader.mainPlacementY -ne 512) {
        throw 'Flash oracle manifest capture-loader semantics drifted from v2.'
    }
    $main = $Manifest.source.mainSwf
    if ([string]$main.path -cne $mainSwfRelativePath -or
        [string]$main.executionRole -cne
            'identity_chain_reference_only' -or
        [bool]$main.mainParticipatesInCapture -or
        [string]$main.sha256 -notmatch '^[0-9A-F]{64}$') {
        throw 'Flash oracle manifest main identity-only binding drifted.'
    }
    $canvas = $Manifest.capture.canvas
    if ([int]$canvas.width -ne 1024 -or
        [int]$canvas.height -ne 576 -or
        [string]$canvas.coordinateSpace -cne 'main_stage' -or
        [string]$canvas.source -cne
            'loaded_child_exported_symbol_instance' -or
        [bool]$canvas.childDocumentWrapperApplied -or
        [string]$canvas.pixelFormat -cne 'straight_argb32' -or
        [string]$canvas.background -cne 'transparent_argb_0') {
        throw 'Flash oracle manifest canvas semantics drifted from v2.'
    }
    Assert-ExactNumberArray `
        -Actual @($canvas.matrix) `
        -Expected @(1, 0, 0, 1, 0, 512) `
        -Label 'Flash oracle v2 main-space draw matrix'
    Assert-ExactNumberArray `
        -Actual @($canvas.contentViewport) `
        -Expected @(0, 0, 1024, 576) `
        -Label 'Flash oracle v2 main content viewport'
    Assert-ExactNumberArray `
        -Actual @($canvas.sourceDocumentInstanceMatrix) `
        -Expected @(1, 0, 0, 1, 0, 3) `
        -Label 'Flash oracle v2 source document instance matrix'
    if (@($Manifest.capture.cases).Count -ne 11) {
        throw 'Flash oracle v2 manifest must contain exactly eleven cases.'
    }
    foreach ($case in @($Manifest.capture.cases)) {
        if ([int]$case.raw.width -ne 1024 -or
            [int]$case.raw.height -ne 576 -or
            [int]$case.crop.rectangle.x -lt 0 -or
            [int]$case.crop.rectangle.y -lt 0 -or
            [int]$case.crop.rectangle.width -le 0 -or
            [int]$case.crop.rectangle.height -le 0 -or
            ([int]$case.crop.rectangle.x +
                [int]$case.crop.rectangle.width) -gt 1024 -or
            ([int]$case.crop.rectangle.y +
                [int]$case.crop.rectangle.height) -gt 576) {
            throw "Flash oracle v2 case geometry is invalid: $($case.caseId)"
        }
    }
}

function Assert-PlayerInfoOracleV2ReceiptContract {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ManifestSha256
    )

    if ([string]$Receipt.schema -cne
            'cf7.player_info.flash_oracle_candidate_receipt.v2' -or
        [string]$Receipt.status -cne 'candidate_ready_after_restore' -or
        [string]$Receipt.manifest.schema -cne
            'cf7.player_info.flash_oracle_manifest.v2' -or
        [string]$Receipt.manifest.sha256 -cne $ManifestSha256 -or
        [string]$Receipt.placement.placementProfile -cne
            'main_rsl_exported_symbol_equivalent' -or
        [string]$Receipt.placement.referencePlacementProfile -cne
            'main_rsl_exported_symbol' -or
        [string]$Receipt.placement.extractionMode -cne
            'loaded_child_exported_symbol_instance' -or
        -not [bool]$Receipt.placement.mainRslPlacementEquivalent -or
        [bool]$Receipt.placement.mainParticipatesInCapture -or
        [string]$Receipt.placement.mainBinaryRole -cne
            'identity_chain_reference_only' -or
        [bool]$Receipt.placement.childDocumentWrapperApplied -or
        [int]$Receipt.placement.exportedSymbolRootTy -ne 0 -or
        [int]$Receipt.placement.mainPlacementY -ne 512) {
        throw 'Flash oracle candidate receipt drifted from the v2 contract.'
    }
    Assert-ExactNumberArray `
        -Actual @($Receipt.placement.canvas) `
        -Expected @(1024, 576) `
        -Label 'Flash oracle v2 receipt canvas'
}

function Invoke-PlayerInfoOracleV2ArtifactContractSelfTest {
    $fixtureCases = @(
        Get-PlayerInfoOracleExpectedCases | ForEach-Object {
            [pscustomobject]@{
                caseId = [string]$_.caseId
                raw = [pscustomobject]@{
                    width = 1024
                    height = 576
                }
                crop = [pscustomobject]@{
                    rectangle = [pscustomobject]@{
                        x = 0
                        y = 474
                        width = 282
                        height = 81
                    }
                }
            }
        }
    )
    $manifest = [pscustomobject]@{
        schema = 'cf7.player_info.flash_oracle_manifest.v2'
        status = 'candidate'
        requiresHumanReview = $true
        source = [pscustomobject]@{
            placementClosure = [ordered]@{
                capturedPlacementProfile =
                    'main_rsl_exported_symbol_equivalent'
                referencePlacementProfile = 'main_rsl_exported_symbol'
                mainRslPlacementEquivalent = $true
                extractionMode = 'loaded_child_exported_symbol_instance'
                mainParticipatesInCapture = $false
                mainBinaryRole = 'identity_chain_reference_only'
                childDocumentWrapperApplied = $false
                exportedSymbolRootTy = 0
                mainPlacementY = 512
            }
            captureLoaderContract = [pscustomobject]@{
                actualCaptureLoaderVerified = $true
                actualLoaderPath = 'scripts/TestLoader.swf'
                childPathVerified = $uiSwfRelativePath
                placementProfile = 'main_rsl_exported_symbol_equivalent'
                referencePlacementProfile = 'main_rsl_exported_symbol'
                extractionMode = 'loaded_child_exported_symbol_instance'
                mainRslPlacementEquivalent = $true
                mainParticipatesInCapture = $false
                mainBinaryRole = 'identity_chain_reference_only'
                asLoaderParticipatesInCapture = $false
                childDocumentWrapperApplied = $false
                exportedSymbolRootTy = 0
                mainPlacementY = 512
            }
            mainSwf = [pscustomobject]@{
                path = $mainSwfRelativePath
                sha256 = ('A' * 64) -join ''
                executionRole = 'identity_chain_reference_only'
                mainParticipatesInCapture = $false
            }
        }
        capture = [pscustomobject]@{
            canvas = [pscustomobject]@{
                width = 1024
                height = 576
                matrix = @(1, 0, 0, 1, 0, 512)
                coordinateSpace = 'main_stage'
                contentViewport = @(0, 0, 1024, 576)
                source = 'loaded_child_exported_symbol_instance'
                sourceDocumentInstanceMatrix = @(1, 0, 0, 1, 0, 3)
                childDocumentWrapperApplied = $false
                pixelFormat = 'straight_argb32'
                background = 'transparent_argb_0'
            }
            cases = $fixtureCases
        }
    }
    Assert-PlayerInfoOracleV2ManifestContract -Manifest $manifest
    $manifestSha256 = ('B' * 64) -join ''
    $receipt = [pscustomobject]@{
        schema = 'cf7.player_info.flash_oracle_candidate_receipt.v2'
        status = 'candidate_ready_after_restore'
        manifest = [pscustomobject]@{
            schema = 'cf7.player_info.flash_oracle_manifest.v2'
            sha256 = $manifestSha256
        }
        placement = [pscustomobject]@{
            placementProfile = 'main_rsl_exported_symbol_equivalent'
            referencePlacementProfile = 'main_rsl_exported_symbol'
            extractionMode = 'loaded_child_exported_symbol_instance'
            mainRslPlacementEquivalent = $true
            mainParticipatesInCapture = $false
            mainBinaryRole = 'identity_chain_reference_only'
            childDocumentWrapperApplied = $false
            exportedSymbolRootTy = 0
            mainPlacementY = 512
            canvas = @(1024, 576)
        }
    }
    Assert-PlayerInfoOracleV2ReceiptContract `
        -Receipt $receipt -ManifestSha256 $manifestSha256

    $manifest.source.placementClosure['mainRuntimeEquivalent'] = $true
    $falseRuntimeClaimRejected = $false
    try {
        Assert-PlayerInfoOracleV2ManifestContract -Manifest $manifest
    } catch {
        $falseRuntimeClaimRejected = $true
    }
    if (-not $falseRuntimeClaimRejected) {
        throw (
            'Artifact-contract self-test accepted a false main-runtime ' +
            'equivalence claim.')
    }
    $manifest.source.placementClosure.Remove('mainRuntimeEquivalent')
    $manifest.schema = 'cf7.player_info.flash_oracle_manifest.' + 'v1'
    $v1ManifestRejected = $false
    try {
        Assert-PlayerInfoOracleV2ManifestContract -Manifest $manifest
    } catch {
        $v1ManifestRejected = $true
    }
    if (-not $v1ManifestRejected) {
        throw 'Artifact-contract self-test accepted a historical v1 manifest.'
    }
    $receipt.schema =
        'cf7.player_info.flash_oracle_candidate_receipt.' + 'v1'
    $v1ReceiptRejected = $false
    try {
        Assert-PlayerInfoOracleV2ReceiptContract `
            -Receipt $receipt -ManifestSha256 $manifestSha256
    } catch {
        $v1ReceiptRejected = $true
    }
    if (-not $v1ReceiptRejected) {
        throw 'Artifact-contract self-test accepted a historical v1 receipt.'
    }
    return [pscustomobject]@{
        manifestSchema = 'cf7.player_info.flash_oracle_manifest.v2'
        receiptSchema = 'cf7.player_info.flash_oracle_candidate_receipt.v2'
        cases = $fixtureCases.Count
        falseRuntimeClaimRejected = $true
        historicalV1Rejected = $true
    }
}

function Get-SystemDpiIdentity {
    if (-not ('Cf7PlayerInfoOracleNativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Cf7PlayerInfoOracleNativeMethods
{
    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();
}
'@
    }
    try {
        $dpi = [int][Cf7PlayerInfoOracleNativeMethods]::GetDpiForSystem()
    } catch {
        Add-Type -AssemblyName System.Drawing
        $graphics = [System.Drawing.Graphics]::FromHwnd([System.IntPtr]::Zero)
        try {
            $dpi = [int][Math]::Round($graphics.DpiX)
        } finally {
            $graphics.Dispose()
        }
    }
    if ($dpi -le 0) {
        throw 'Could not determine a positive Windows system DPI.'
    }
    return [pscustomobject]@{
        dpi = $dpi
        scalePercent = [int][Math]::Round(($dpi / 96.0) * 100)
        affectsLogicalBitmapDraw = $false
    }
}

function Get-ExactFlashCs6TaskRegistration {
    $tasks = @(Get-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop)
    if ($tasks.Count -ne 1 -or
        [string]$tasks[0].TaskName -cne 'FlashCS6Task' -or
        [string]$tasks[0].TaskPath -cne '\') {
        throw 'Expected exactly one root \\FlashCS6Task registration.'
    }
    $actions = @($tasks[0].Actions)
    if ($actions.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$actions[0].Execute)) {
        throw 'FlashCS6Task must expose exactly one executable action.'
    }
    $actionPath = [System.IO.Path]::GetFullPath(
        [string]$actions[0].Execute)
    if ([System.IO.Path]::GetFileName($actionPath) -ine 'Flash.exe' -or
        -not (Test-Path -LiteralPath $actionPath)) {
        throw 'FlashCS6Task action is not one existing Flash.exe.'
    }
    return [pscustomobject]@{
        taskName = 'FlashCS6Task'
        taskPath = '\'
        actionPath = $actionPath
    }
}

function Get-Cf7PlayerInfoFlashProcessImagePathLimited {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProcessId
    )

    if (-not ('Cf7PlayerInfoFlashProcessPathNativeMethodsR10' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class Cf7PlayerInfoFlashProcessPathNativeMethodsR10
{
    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint desiredAccess,
        bool inheritHandle,
        int processId);

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern bool QueryFullProcessImageNameW(
        IntPtr processHandle,
        uint flags,
        StringBuilder imagePath,
        ref uint imagePathCharacters);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public static string QueryFullImagePath(int processId)
    {
        IntPtr processHandle = OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION,
            false,
            processId);
        if (processHandle == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            uint imagePathCharacters = 32768;
            var imagePath = new StringBuilder((int)imagePathCharacters);
            if (!QueryFullProcessImageNameW(
                    processHandle,
                    0,
                    imagePath,
                    ref imagePathCharacters))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            if (imagePathCharacters == 0)
            {
                throw new InvalidOperationException(
                    "QueryFullProcessImageNameW returned an empty path.");
            }
            return imagePath.ToString(0, (int)imagePathCharacters);
        }
        finally
        {
            CloseHandle(processHandle);
        }
    }
}
'@
    }

    try {
        $path =
            [Cf7PlayerInfoFlashProcessPathNativeMethodsR10]::QueryFullImagePath(
                $ProcessId)
    } catch {
        throw [System.InvalidOperationException]::new(
            "Could not query limited-information image path for PID $ProcessId.",
            $_.Exception)
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Limited-information image path was empty for PID $ProcessId."
    }
    return [System.IO.Path]::GetFullPath($path)
}

function Assert-Cf7PlayerInfoFlashAuthoringPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessPath,

        [Parameter(Mandatory = $true)]
        $Registration
    )

    $path = [System.IO.Path]::GetFullPath($ProcessPath)
    if ([System.IO.Path]::GetFileName($path) -ine 'Flash.exe' -or
        -not (Test-Path -LiteralPath $path)) {
        throw 'Flash authoring process path is not one existing Flash.exe.'
    }
    if (-not [string]::Equals(
            [string]$Registration.actionPath,
            $path,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Running Flash.exe does not match the registered FlashCS6Task identity.'
    }
    return $path
}

function Get-FlashAuthoringIdentity {
    $processes = @(
        Get-Process -Name Flash -ErrorAction SilentlyContinue |
            Sort-Object -Property Id
    )
    if ($processes.Count -ne 1) {
        throw ("Expected exactly one Flash.exe process after compile; got {0}." -f
            $processes.Count)
    }
    $processPaths = @($processes | ForEach-Object {
        [pscustomobject]@{
            processId = [int]$_.Id
            path = Get-Cf7PlayerInfoFlashProcessImagePathLimited `
                -ProcessId ([int]$_.Id)
        }
    })
    $paths = @($processPaths.path | Sort-Object -Unique)
    if ($paths.Count -ne 1) {
        throw ("Expected exactly one Flash.exe image path after compile; got {0}." -f
            $paths.Count)
    }
    $registration = Get-ExactFlashCs6TaskRegistration
    $path = Assert-Cf7PlayerInfoFlashAuthoringPath `
        -ProcessPath $paths[0] -Registration $registration
    $before = Get-FileIdentity -Path $path
    if (-not $before.exists) {
        throw 'Registered Flash.exe disappeared during authoring identity capture.'
    }
    $item = Get-Item -LiteralPath $path
    $after = Get-FileIdentity -Path $path
    if (-not $after.exists -or
        $after.length -ne $before.length -or
        $after.sha256 -cne $before.sha256 -or
        $after.lastWriteUtc -cne $before.lastWriteUtc -or
        $item.Length -ne $before.length -or
        $item.LastWriteTimeUtc.ToString('o') -cne $before.lastWriteUtc) {
        throw 'Registered Flash.exe identity drifted while being read.'
    }
    return [pscustomobject]@{
        path = $path
        processIds = @($processPaths.processId)
        fileName = $item.Name
        fileVersion = $item.VersionInfo.FileVersion
        productVersion = $item.VersionInfo.ProductVersion
        length = [long]$before.length
        lastWriteUtc = [string]$before.lastWriteUtc
        sha256 = [string]$before.sha256
        registeredTaskMatched = $true
    }
}

function Get-RegisteredFlashDebugPlayerIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9A-Fa-f]{64}$')]
        [string]$ExpectedSha256
    )

    $registrationBefore = Get-ExactFlashCs6TaskRegistration
    $authoringRoot = [System.IO.Path]::GetDirectoryName(
        [string]$registrationBefore.actionPath)
    $debugRelativePath = 'Players\Debug\FlashPlayerDebugger.exe'
    $path = [System.IO.Path]::GetFullPath(
        (Join-Path $authoringRoot $debugRelativePath))
    $rootPrefix = $authoringRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith(
            $rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $path)) {
        throw 'Registered Flash CS6 debug standalone player is unavailable.'
    }

    $before = Get-FileIdentity -Path $path
    if (-not $before.exists) {
        throw 'Registered Flash CS6 debug player is unavailable.'
    }
    $item = Get-Item -LiteralPath $path
    $hash = [string]$before.sha256
    if ($hash -cne $ExpectedSha256.ToUpperInvariant()) {
        throw ("Registered Flash CS6 debug player identity drifted: " +
            "expected {0}, got {1}." -f
            $ExpectedSha256.ToUpperInvariant(), $hash)
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne
        [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate) {
        throw 'Registered Flash CS6 debug player signature is not valid.'
    }
    $after = Get-FileIdentity -Path $path
    $registrationAfter = Get-ExactFlashCs6TaskRegistration
    if (-not $after.exists -or
        $after.length -ne $before.length -or
        $after.sha256 -cne $before.sha256 -or
        $after.lastWriteUtc -cne $before.lastWriteUtc -or
        $item.Length -ne $before.length -or
        $item.LastWriteTimeUtc.ToString('o') -cne $before.lastWriteUtc -or
        $registrationAfter.taskPath -cne $registrationBefore.taskPath -or
        $registrationAfter.actionPath -ine $registrationBefore.actionPath) {
        throw 'Flash CS6 task/debug-player identity drifted during admission.'
    }

    return [pscustomobject]@{
        path = $path
        logicalPath = $playerLogicalPath
        registeredTask = 'FlashCS6Task'
        registeredTaskPath = [string]$registrationBefore.taskPath
        registeredTaskActionMatched = $true
        authoringActionPath = [string]$registrationBefore.actionPath
        relativeToAuthoringRoot =
            ($debugRelativePath -replace '\\', '/')
        length = [long]$item.Length
        lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
        sha256 = $hash
        fileVersion = $item.VersionInfo.FileVersion
        productVersion = $item.VersionInfo.ProductVersion
        authenticodeStatus = [string]$signature.Status
        signerThumbprint =
            [string]$signature.SignerCertificate.Thumbprint
    }
}

function Assert-RegisteredFlashDebugPlayerCurrent {
    param(
        [Parameter(Mandatory = $true)]
        $Expected
    )

    $registration = Get-ExactFlashCs6TaskRegistration
    $current = Get-FileIdentity -Path ([string]$Expected.path)
    if (-not $current.exists -or
        $registration.taskPath -cne [string]$Expected.registeredTaskPath -or
        $registration.actionPath -ine [string]$Expected.authoringActionPath -or
        $current.length -ne [long]$Expected.length -or
        $current.sha256 -cne [string]$Expected.sha256 -or
        $current.lastWriteUtc -cne [string]$Expected.lastWriteUtc) {
        throw 'Registered Flash CS6 debug player identity drifted during capture.'
    }
}

function Get-PlayerInfoStandaloneLaunchPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptsDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedLoaderSwfPath
    )

    $workingDirectory = [System.IO.Path]::GetFullPath($ScriptsDirectory)
    $argumentToken = 'TestLoader.swf'
    if ([System.IO.Path]::IsPathRooted($argumentToken) -or
        [System.IO.Path]::GetFileName($argumentToken) -cne $argumentToken -or
        $argumentToken -match '[\s"'']') {
        throw 'Standalone player argument must be one unquoted, space-free file token.'
    }

    $resolvedLoaderSwfPath = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine($workingDirectory, $argumentToken))
    $normalizedExpectedLoaderSwfPath = [System.IO.Path]::GetFullPath(
        $ExpectedLoaderSwfPath)
    if ($resolvedLoaderSwfPath -cne $normalizedExpectedLoaderSwfPath) {
        throw (
            'Standalone player relative argument does not reverse-resolve to ' +
            'the exact expected TestLoader.swf path.')
    }

    return [pscustomobject]@{
        workingDirectory = $workingDirectory
        argumentToken = $argumentToken
        resolvedLoaderSwfPath = $resolvedLoaderSwfPath
    }
}

function Get-FreshFlashLogFromFullBytes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$BeforeBytes,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$FullBytes,
        [Parameter(Mandatory = $true)][datetime]$StartedUtc
    )

    $hasPrefix = $FullBytes.Length -ge $BeforeBytes.Length
    if ($hasPrefix) {
        for ($index = 0; $index -lt $BeforeBytes.Length; $index++) {
            if ($FullBytes[$index] -ne $BeforeBytes[$index]) {
                $hasPrefix = $false
                break
            }
        }
    }
    if ($hasPrefix) {
        $fresh = [byte[]]::new($FullBytes.Length - $BeforeBytes.Length)
        if ($fresh.Length -gt 0) {
            [System.Buffer]::BlockCopy(
                $FullBytes, $BeforeBytes.Length, $fresh, 0, $fresh.Length)
        }
        $mode = 'exact_prefix_tail'
    } elseif (Test-Path -LiteralPath $globalFlashLog) {
        $item = Get-Item -LiteralPath $globalFlashLog
        if ($item.LastWriteTimeUtc -lt $StartedUtc.AddSeconds(-1)) {
            throw 'Flashlog changed shape without a fresh post-launch timestamp.'
        }
        $fresh = $FullBytes
        $mode = 'post_launch_rewrite'
    } else {
        $fresh = [byte[]]@()
        $mode = 'missing'
    }
    return [pscustomobject]@{
        mode = $mode
        bytes = $fresh
        text = [System.Text.Encoding]::UTF8.GetString($fresh)
        fullLength = $FullBytes.Length
        fullSha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $FullBytes
    }
}

function Get-CurrentFreshFlashLog {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$BeforeBytes,
        [Parameter(Mandatory = $true)][datetime]$StartedUtc
    )

    return Get-FreshFlashLogFromFullBytes `
        -BeforeBytes $BeforeBytes `
        -FullBytes (Read-SharedBytes -Path $globalFlashLog) `
        -StartedUtc $StartedUtc
}

function Get-ExactTerminalKind {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FreshText,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    $escapedRunId = [regex]::Escape($RunId)
    $matches = [regex]::Matches(
        $FreshText,
        "(?m)^PLAYER_INFO_ORACLE\|(COMPLETE|FAILURE)\|runId=$escapedRunId(?:\||\r?$)"
    )
    if ($matches.Count -eq 0) {
        return $null
    }
    return [string]$matches[$matches.Count - 1].Groups[1].Value
}

function Get-StableFinalFlashLog {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$BeforeBytes,
        [Parameter(Mandatory = $true)][datetime]$StartedUtc
    )

    $deadline = [System.DateTime]::UtcNow.AddSeconds($stabilityTimeoutSeconds)
    $previousIdentity = $null
    $stablePolls = 0
    $polls = 0
    $lastBytes = $null
    while ([System.DateTime]::UtcNow -lt $deadline) {
        $lastBytes = Read-SharedBytes -Path $globalFlashLog
        $identity = '{0}|{1}' -f $lastBytes.Length,
            (Get-PlayerInfoOracleBytesSha256 -Bytes $lastBytes)
        $polls++
        if ($identity -ceq $previousIdentity) {
            $stablePolls++
        } else {
            $previousIdentity = $identity
            $stablePolls = 1
        }
        if ($stablePolls -ge $requiredStablePolls) {
            $fresh = Get-FreshFlashLogFromFullBytes `
                -BeforeBytes $BeforeBytes `
                -FullBytes $lastBytes `
                -StartedUtc $StartedUtc
            return [pscustomobject]@{
                snapshot = $fresh
                totalPolls = $polls
                consecutiveStablePolls = $stablePolls
                pollMilliseconds = $stabilityPollMilliseconds
            }
        }
        [System.Threading.Thread]::Sleep($stabilityPollMilliseconds)
    }
    throw ("Flashlog length/hash did not remain stable for {0} consecutive polls " +
        "within {1} seconds." -f $requiredStablePolls, $stabilityTimeoutSeconds)
}

$script:playerInfoCompileUncertainWritten = $false
$script:playerInfoBehaviorFailureWritten = $false

function Set-CompileStateUncertain {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$MarkerPath = $uncertainMarker
    )

    $isGlobalMarker = [System.IO.Path]::GetFullPath($MarkerPath).Equals(
        [System.IO.Path]::GetFullPath($uncertainMarker),
        [System.StringComparison]::OrdinalIgnoreCase)
    if ($isGlobalMarker -and $script:playerInfoCompileUncertainWritten) {
        return
    }
    $prior = if (Test-Path -LiteralPath $MarkerPath) {
        [System.IO.File]::ReadAllText(
            $MarkerPath, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | player-info Flash oracle: {1}' -f
        [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $MarkerPath,
        $body,
        [System.Text.UTF8Encoding]::new($false)
    )
    if ($isGlobalMarker) {
        $script:playerInfoCompileUncertainWritten = $true
    }
}

function Get-PlayerInfoCompileRecoveryDecision {
    param(
        [Parameter(Mandatory = $true)][bool]$CompileInvoked,
        [Parameter(Mandatory = $true)][bool]$CompileReturned,
        [Parameter(Mandatory = $true)][bool]$TerminalSafeAfterReturn,
        [Parameter(Mandatory = $true)][bool]$CompiledIdentityFrozen,
        [Parameter(Mandatory = $true)][string]$UncertainMarkerPath
    )

    $markerExists = Test-Path -LiteralPath $UncertainMarkerPath
    $canFreeze = $CompileInvoked -and
        $CompileReturned -and
        $TerminalSafeAfterReturn -and
        -not $markerExists
    $canRestore = $canFreeze -and $CompiledIdentityFrozen
    return [pscustomobject]@{
        markerExists = $markerExists
        canFreeze = $canFreeze
        canRestore = $canRestore
        reason = if (-not $CompileInvoked) {
            'compile_not_invoked'
        } elseif (-not $CompileReturned) {
            'compile_did_not_return'
        } elseif (-not $TerminalSafeAfterReturn) {
            'compile_returned_nonterminal'
        } elseif ($markerExists) {
            'compile_state_marker_present'
        } elseif (-not $CompiledIdentityFrozen) {
            'compiled_identity_not_frozen'
        } else {
            'terminal_safe_frozen'
        }
    }
}

function Set-PlayerInfoRecoveryUncertainIfNeeded {
    param(
        [Parameter(Mandatory = $true)][bool]$HasDerivedTransaction,
        [Parameter(Mandatory = $true)][bool]$HasScratchTransaction,
        [Parameter(Mandatory = $true)][bool]$SwfRestored,
        [Parameter(Mandatory = $true)][bool]$SourceRestored,
        [Parameter(Mandatory = $true)][bool]$DerivedCleanupDone,
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ($HasDerivedTransaction -and -not $DerivedCleanupDone) {
        Set-CompileStateUncertain -MarkerPath $MarkerPath -Reason $Reason
        return $true
    }
    if (($HasScratchTransaction -and -not $SourceRestored) -or
        ($HasDerivedTransaction -and -not $SwfRestored)) {
        Set-CompileStateUncertain -MarkerPath $MarkerPath -Reason $Reason
        return $true
    }
    return $false
}

function Write-PlayerInfoOracleBehaviorFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [AllowEmptyString()][string]$RunId = ''
    )

    if ($script:playerInfoBehaviorFailureWritten) {
        return
    }
    try {
        $directory = Join-Path $tmpRoot '.behavior-failures'
        if (-not (Test-Path -LiteralPath $directory)) {
            [void](New-Item -ItemType Directory -Path $directory)
        }
        $leaf = '{0}-{1}.json' -f
            [System.DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'),
            [System.Guid]::NewGuid().ToString('N')
        Write-AtomicUtf8Json `
            -Path (Join-Path $directory $leaf) `
            -Value ([ordered]@{
                schema = 'cf7.player_info.flash_oracle_behavior_failure.v1'
                createdUtc = [System.DateTime]::UtcNow.ToString('o')
                runId = $RunId
                reason = $Reason
                compileStateMarkerWritten = $false
            })
        $script:playerInfoBehaviorFailureWritten = $true
    } catch {
        Write-Warning (
            'Could not write ignored player-info behavior failure receipt: ' +
            $_.Exception.Message)
    }
}

function Stop-OwnedPlayerFailClosed {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    Write-PlayerInfoOracleBehaviorFailure `
        -Reason $Reason -RunId $script:currentPlayerInfoOracleRunId
    $Process.Refresh()
    if (-not $Process.HasExited) {
        $Process.Kill()
        if (-not $Process.WaitForExit(5000)) {
            throw "Exact owned player PID $($Process.Id) did not terminate after kill."
        }
    }
}

function Wait-ForOwnedPlayerAndStableTrace {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$BeforeBytes,
        [Parameter(Mandatory = $true)][datetime]$StartedUtc,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][datetime]$DeadlineUtc
    )

    $terminalKind = $null
    while ([System.DateTime]::UtcNow -lt $DeadlineUtc) {
        $snapshot = Get-CurrentFreshFlashLog `
            -BeforeBytes $BeforeBytes -StartedUtc $StartedUtc
        $terminalKind = Get-ExactTerminalKind `
            -FreshText $snapshot.text -RunId $RunId
        $Process.Refresh()
        if ($terminalKind) {
            $remainingMs = [int][Math]::Max(
                0,
                [Math]::Min(
                    $naturalExitTimeoutMilliseconds,
                    ($DeadlineUtc - [System.DateTime]::UtcNow).TotalMilliseconds
                )
            )
            if ($remainingMs -le 0 -or -not $Process.WaitForExit($remainingMs)) {
                Stop-OwnedPlayerFailClosed `
                    -Process $Process `
                    -Reason (
                        "exact $terminalKind record observed but owned PID " +
                        "$($Process.Id) did not exit naturally; runId=$RunId")
                throw 'Owned player did not exit naturally after its terminal record.'
            }
            break
        }
        if ($Process.HasExited) {
            break
        }
        [System.Threading.Thread]::Sleep(200)
    }
    $Process.Refresh()
    if (-not $Process.HasExited) {
        Stop-OwnedPlayerFailClosed `
            -Process $Process `
            -Reason (
                "capture deadline elapsed before natural owned-PID exit; runId=$RunId")
        throw 'Player-info oracle capture timed out.'
    }
    try {
        $stable = Get-StableFinalFlashLog `
            -BeforeBytes $BeforeBytes -StartedUtc $StartedUtc
    } catch {
        Write-PlayerInfoOracleBehaviorFailure `
            -RunId $RunId `
            -Reason (
            "owned PID exited but final flashlog was not stable; runId=$RunId; " +
            "error=$($_.Exception.Message)")
        throw
    }
    $finalTerminal = Get-ExactTerminalKind `
        -FreshText $stable.snapshot.text -RunId $RunId
    return [pscustomobject]@{
        naturalExit = $true
        earlyTerminalKind = $terminalKind
        finalTerminalKind = $finalTerminal
        stability = $stable
    }
}

function Invoke-PlayerInfoDerivedSwfTransactionSelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) (
        'cf7-player-info-oracle-swf-selftest-' +
        [System.Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root)
    $scenarioDirectories = [System.Collections.Generic.List[string]]::new()

    $newScenario = {
        param([string]$Name)
        $directory = Join-Path $root $Name
        [void](New-Item -ItemType Directory -Path $directory)
        $scenarioDirectories.Add($directory)
        $marker = Join-Path $directory 'testloader_scratch_inflight.marker'
        $body = '{"schema":"synthetic-source-marker","name":"' + $Name + '"}'
        [System.IO.File]::WriteAllText(
            $marker, $body, [System.Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{
            directory = $directory
            marker = $marker
            body = $body
            source = [pscustomobject]@{
                MarkerPath = $marker
                MarkerBody = $body
            }
            swf = Join-Path $directory 'TestLoader.swf'
        }
    }

    $existing = & $newScenario 'existing'
    $existingOriginal = [byte[]](11, 22, 33, 44, 55)
    Write-AtomicBytes -Path $existing.swf -Bytes $existingOriginal
    [System.IO.File]::SetLastWriteTimeUtc(
        $existing.swf, [datetime]'2026-01-02T03:04:05Z')
    $existingTransaction = New-PlayerInfoDerivedSwfTransaction `
        -SourceTransaction $existing.source -SwfPath $existing.swf
    $existingCompiled = [byte[]](90, 91, 92, 93, 94, 95)
    Write-AtomicBytes -Path $existing.swf -Bytes $existingCompiled
    [void](Freeze-PlayerInfoDerivedSwfCompiledIdentity `
        -Transaction $existingTransaction)
    Assert-PlayerInfoDerivedSwfCompiledCurrent `
        -Transaction $existingTransaction
    Restore-PlayerInfoDerivedSwfTransaction `
        -Transaction $existingTransaction
    if (-not (Test-Path -LiteralPath $existing.marker)) {
        throw 'Derived-SWF self-test cleared the source marker too early.'
    }
    Remove-Item -LiteralPath $existing.marker -Force
    Complete-PlayerInfoDerivedSwfCleanup -Transaction $existingTransaction
    if ((Get-PathSha256 -Path $existing.swf) -cne
        (Get-PlayerInfoOracleBytesSha256 -Bytes $existingOriginal)) {
        throw 'Derived-SWF self-test did not restore existing bytes.'
    }
    Remove-Item -LiteralPath $existing.swf -Force

    $absent = & $newScenario 'absent'
    $absentTransaction = New-PlayerInfoDerivedSwfTransaction `
        -SourceTransaction $absent.source -SwfPath $absent.swf
    Write-AtomicBytes -Path $absent.swf -Bytes ([byte[]](1, 3, 5, 7))
    [void](Freeze-PlayerInfoDerivedSwfCompiledIdentity `
        -Transaction $absentTransaction)
    Restore-PlayerInfoDerivedSwfTransaction `
        -Transaction $absentTransaction
    if (Test-Path -LiteralPath $absent.swf) {
        throw 'Derived-SWF self-test did not remove a newly-created SWF.'
    }
    Remove-Item -LiteralPath $absent.marker -Force
    Complete-PlayerInfoDerivedSwfCleanup -Transaction $absentTransaction

    $late = & $newScenario 'late-write'
    $lateOriginal = [byte[]](2, 4, 6, 8)
    Write-AtomicBytes -Path $late.swf -Bytes $lateOriginal
    $lateTransaction = New-PlayerInfoDerivedSwfTransaction `
        -SourceTransaction $late.source -SwfPath $late.swf
    Write-AtomicBytes -Path $late.swf -Bytes ([byte[]](10, 12, 14, 16))
    [void](Freeze-PlayerInfoDerivedSwfCompiledIdentity `
        -Transaction $lateTransaction)
    Write-AtomicBytes -Path $late.swf -Bytes ([byte[]](99, 98, 97))
    $lateWriteRejected = $false
    try {
        Restore-PlayerInfoDerivedSwfTransaction `
            -Transaction $lateTransaction
    } catch {
        $lateWriteRejected = $true
    }
    if (-not $lateWriteRejected -or
        -not (Test-Path -LiteralPath $late.marker) -or
        -not (Test-Path -LiteralPath $lateTransaction.SidecarPath) -or
        -not (Test-Path -LiteralPath $lateTransaction.BackupPath)) {
        throw 'Derived-SWF late-write self-test did not retain recovery material.'
    }
    Write-AtomicBytes `
        -Path $late.swf `
        -Bytes (Read-SharedBytes -Path $lateTransaction.BackupPath)
    Remove-Item -LiteralPath $lateTransaction.SidecarPath -Force
    Remove-Item -LiteralPath $lateTransaction.BackupPath -Force
    Remove-Item -LiteralPath $late.marker -Force
    Remove-Item -LiteralPath $late.swf -Force
    if (Test-Path -LiteralPath $lateTransaction.RecoveryDirectory) {
        if (@(Get-ChildItem -LiteralPath (
                    $lateTransaction.RecoveryDirectory) -Force).Count -ne 0) {
            throw 'Derived-SWF self-test recovery directory is unexpectedly nonempty.'
        }
        Remove-Item -LiteralPath $lateTransaction.RecoveryDirectory -Force
    }

    $nonterminal = & $newScenario 'nonterminal-compile'
    $nonterminalOriginal = [byte[]](31, 32, 33, 34)
    Write-AtomicBytes `
        -Path $nonterminal.swf -Bytes $nonterminalOriginal
    $nonterminalTransaction = New-PlayerInfoDerivedSwfTransaction `
        -SourceTransaction $nonterminal.source `
        -SwfPath $nonterminal.swf
    $nonterminalChanged = [byte[]](41, 42, 43, 44, 45)
    Write-AtomicBytes `
        -Path $nonterminal.swf -Bytes $nonterminalChanged
    $nonterminalMarker = Join-Path $nonterminal.directory `
        'compile_state_uncertain.marker'
    Set-CompileStateUncertain `
        -MarkerPath $nonterminalMarker `
        -Reason 'synthetic nonterminal compile'
    $nonterminalDecision = Get-PlayerInfoCompileRecoveryDecision `
        -CompileInvoked $true `
        -CompileReturned $true `
        -TerminalSafeAfterReturn $false `
        -CompiledIdentityFrozen $false `
        -UncertainMarkerPath $nonterminalMarker
    $terminalSafeMarker = Join-Path $nonterminal.directory `
        'terminal-safe-absent.marker'
    $terminalCanFreeze = Get-PlayerInfoCompileRecoveryDecision `
        -CompileInvoked $true `
        -CompileReturned $true `
        -TerminalSafeAfterReturn $true `
        -CompiledIdentityFrozen $false `
        -UncertainMarkerPath $terminalSafeMarker
    $terminalCanRestore = Get-PlayerInfoCompileRecoveryDecision `
        -CompileInvoked $true `
        -CompileReturned $true `
        -TerminalSafeAfterReturn $true `
        -CompiledIdentityFrozen $true `
        -UncertainMarkerPath $terminalSafeMarker
    if ($nonterminalDecision.canFreeze -or
        $nonterminalDecision.canRestore -or
        -not $terminalCanFreeze.canFreeze -or
        $terminalCanFreeze.canRestore -or
        -not $terminalCanRestore.canRestore -or
        -not (Test-Path -LiteralPath $nonterminal.marker) -or
        -not (Test-Path -LiteralPath $nonterminalTransaction.SidecarPath) -or
        -not (Test-Path -LiteralPath $nonterminalTransaction.BackupPath) -or
        -not (Test-Path -LiteralPath $nonterminalMarker) -or
        (Get-PathSha256 -Path $nonterminal.swf) -cne
        (Get-PlayerInfoOracleBytesSha256 -Bytes $nonterminalChanged) -or
        [string]$nonterminalTransaction.Record.phase -cne 'prepared') {
        throw (
            'Nonterminal compile self-test did not deny freeze/recovery while ' +
            'retaining source marker, sidecar, backup, marker, and changed SWF.')
    }
    Write-AtomicBytes `
        -Path $nonterminal.swf `
        -Bytes (Read-SharedBytes -Path $nonterminalTransaction.BackupPath)
    Remove-Item -LiteralPath $nonterminalTransaction.SidecarPath -Force
    Remove-Item -LiteralPath $nonterminalTransaction.BackupPath -Force
    Remove-Item -LiteralPath $nonterminal.marker -Force
    Remove-Item -LiteralPath $nonterminalMarker -Force
    Remove-Item -LiteralPath $nonterminal.swf -Force
    Remove-Item `
        -LiteralPath $nonterminalTransaction.RecoveryDirectory -Force

    $restoreDrift = & $newScenario 'restore-drift'
    $restoreDriftOriginal = [byte[]](51, 52, 53, 54)
    Write-AtomicBytes `
        -Path $restoreDrift.swf -Bytes $restoreDriftOriginal
    $restoreDriftTransaction = New-PlayerInfoDerivedSwfTransaction `
        -SourceTransaction $restoreDrift.source `
        -SwfPath $restoreDrift.swf
    Write-AtomicBytes `
        -Path $restoreDrift.swf -Bytes ([byte[]](61, 62, 63, 64))
    [void](Freeze-PlayerInfoDerivedSwfCompiledIdentity `
        -Transaction $restoreDriftTransaction)
    Restore-PlayerInfoDerivedSwfTransaction `
        -Transaction $restoreDriftTransaction
    Remove-Item -LiteralPath $restoreDrift.marker -Force
    $restoreDriftChanged = [byte[]](71, 72, 73, 74, 75)
    Write-AtomicBytes `
        -Path $restoreDrift.swf -Bytes $restoreDriftChanged
    $restoreDriftMarker = Join-Path $restoreDrift.directory `
        'compile_state_uncertain.marker'
    $restoreDriftRejected = $false
    try {
        Complete-PlayerInfoDerivedSwfCleanup `
            -Transaction $restoreDriftTransaction
    } catch {
        $restoreDriftRejected = $true
        [void](Set-PlayerInfoRecoveryUncertainIfNeeded `
            -HasDerivedTransaction $true `
            -HasScratchTransaction $true `
            -SwfRestored $true `
            -SourceRestored $true `
            -DerivedCleanupDone $false `
            -MarkerPath $restoreDriftMarker `
            -Reason 'synthetic restored-SWF drift before cleanup')
    }
    if (-not $restoreDriftRejected -or
        -not (Test-Path -LiteralPath $restoreDriftMarker) -or
        -not (Test-Path -LiteralPath $restoreDriftTransaction.SidecarPath) -or
        -not (Test-Path -LiteralPath $restoreDriftTransaction.BackupPath) -or
        (Get-PathSha256 -Path $restoreDrift.swf) -cne
        (Get-PlayerInfoOracleBytesSha256 -Bytes $restoreDriftChanged)) {
        throw (
            'Restored-SWF drift self-test did not set uncertainty and retain ' +
            'sidecar/backup before cleanup.')
    }
    Write-AtomicBytes `
        -Path $restoreDrift.swf `
        -Bytes (Read-SharedBytes -Path $restoreDriftTransaction.BackupPath)
    Remove-Item -LiteralPath $restoreDriftTransaction.SidecarPath -Force
    Remove-Item -LiteralPath $restoreDriftTransaction.BackupPath -Force
    Remove-Item -LiteralPath $restoreDriftMarker -Force
    Remove-Item -LiteralPath $restoreDrift.swf -Force
    Remove-Item `
        -LiteralPath $restoreDriftTransaction.RecoveryDirectory -Force

    $bindingDirectory = Join-Path $root 'snapshot-binding'
    [void](New-Item -ItemType Directory -Path $bindingDirectory)
    $scenarioDirectories.Add($bindingDirectory)
    $bindingEvidence = Join-Path $bindingDirectory 'evidence'
    [void](New-Item -ItemType Directory -Path $bindingEvidence)
    $bindingBytes = [byte[]](21, 34, 55, 89)
    $bindingSnapshots = [ordered]@{
        loader = New-CandidateSnapshot `
            -EvidenceDirectory $bindingEvidence `
            -Name 'loader.bin' `
            -Bytes $bindingBytes
    }
    Write-AtomicBytes `
        -Path (Join-Path $bindingEvidence 'loader.bin') `
        -Bytes ([byte[]](1, 1, 2, 3, 5, 8))
    $snapshotTamperRejected = $false
    try {
        Assert-CandidateSnapshotSet `
            -WorkDirectory $bindingDirectory `
            -Snapshots $bindingSnapshots
    } catch {
        $snapshotTamperRejected = $true
    }
    if (-not $snapshotTamperRejected) {
        throw 'Candidate snapshot cross-binding self-test accepted tampered bytes.'
    }
    Write-AtomicBytes `
        -Path (Join-Path $bindingEvidence 'loader.bin') `
        -Bytes $bindingBytes
    Assert-CandidateSnapshotSet `
        -WorkDirectory $bindingDirectory `
        -Snapshots $bindingSnapshots
    Remove-Item -LiteralPath (Join-Path $bindingEvidence 'loader.bin') -Force
    Remove-Item -LiteralPath $bindingEvidence -Force

    foreach ($directory in $scenarioDirectories) {
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count -ne 0) {
            throw "Derived-SWF self-test left scenario artifacts: $directory"
        }
        Remove-Item -LiteralPath $directory -Force
    }
    if (@(Get-ChildItem -LiteralPath $root -Force).Count -ne 0) {
        throw 'Derived-SWF self-test root is unexpectedly nonempty.'
    }
    Remove-Item -LiteralPath $root -Force
    return [pscustomobject]@{
        recoveryScenarios = 3
        lateWriteRejected = $true
        nonterminalCompileRejected = $true
        restoreDriftRejected = $true
        recoveryAdmissionNegatives = 2
        sourceMarkerFirst = $true
        snapshotTamperRejected = $true
    }
}

function Invoke-ValidateOnly {
    $validateFlashPidsBefore = @(
        Get-Process -Name Flash -ErrorAction SilentlyContinue |
            Sort-Object -Property Id |
            ForEach-Object { [int]$_.Id }
    )
    if ($validateFlashPidsBefore.Count -ne 1) {
        throw 'Validate-only positive identity requires exactly one Flash process.'
    }
    $validateAuthoring = Get-FlashAuthoringIdentity
    if (@($validateAuthoring.processIds).Count -ne 1 -or
        [int]$validateAuthoring.processIds[0] -ne
            [int]$validateFlashPidsBefore[0]) {
        throw 'Validate-only Flash authoring positive identity PID set drifted.'
    }
    $invalidPidRejected = $false
    try {
        Get-Cf7PlayerInfoFlashProcessImagePathLimited `
            -ProcessId ([int]::MaxValue) | Out-Null
    } catch {
        $invalidPidRejected = $true
    }
    if (-not $invalidPidRejected) {
        throw 'Validate-only accepted a nonexistent process ID.'
    }
    $registration = Get-ExactFlashCs6TaskRegistration
    $wrongProcessPath =
        Get-Cf7PlayerInfoFlashProcessImagePathLimited -ProcessId $PID
    $wrongPathRejected = $false
    try {
        Assert-Cf7PlayerInfoFlashAuthoringPath `
            -ProcessPath $wrongProcessPath `
            -Registration $registration | Out-Null
    } catch {
        $wrongPathRejected = $true
    }
    if (-not $wrongPathRejected) {
        throw 'Validate-only accepted a non-Flash process image path.'
    }
    $validatePlayer = Get-RegisteredFlashDebugPlayerIdentity `
        -ExpectedSha256 $ExpectedPlayerSha256
    $validateLaunchPlan = Get-PlayerInfoStandaloneLaunchPlan `
        -ScriptsDirectory $scriptsDir `
        -ExpectedLoaderSwfPath $loaderSwfPath
    if ($validateLaunchPlan.workingDirectory -cne
            [System.IO.Path]::GetFullPath($scriptsDir) -or
        $validateLaunchPlan.argumentToken -cne 'TestLoader.swf' -or
        $validateLaunchPlan.argumentToken -match '[\s"'']' -or
        $validateLaunchPlan.resolvedLoaderSwfPath -cne
            [System.IO.Path]::GetFullPath($loaderSwfPath)) {
        throw 'Validate-only standalone player launch-plan regression failed.'
    }
    $watchedPaths = @(
        $PSCommandPath,
        $scratchRunnerPath,
        $loaderSwfPath,
        $uiSwfPath,
        $mainSwfPath,
        $compileOutputPath,
        $compilerErrorsPath,
        $templatePath,
        $protocolHelperPath,
        $closurePath,
        $chainPath,
        $scratchMarker,
        $uncertainMarker,
        $globalFlashLog,
        $validateAuthoring.path,
        $validatePlayer.path
    )
    $before = @{}
    foreach ($path in $watchedPaths) {
        $before[$path] = Get-FileIdentity -Path $path | ConvertTo-Json -Compress
    }
    $template = Assert-OracleTemplate
    Assert-RunnerStaticContract
    $validateRunnerFrozen = New-FrozenFileInput `
        -Path $PSCommandPath -Label $captureRunnerRelativePath
    $validateProtocolFrozen = New-FrozenFileInput `
        -Path $protocolHelperPath -Label $protocolHelperRelativePath
    $validateTooling = Get-StrictCaptureToolingSet `
        -RunnerFrozen $validateRunnerFrozen `
        -ProtocolFrozen $validateProtocolFrozen
    $evidence = $null
    if ((Test-Path -LiteralPath $closurePath) -and
        (Test-Path -LiteralPath $chainPath)) {
        $evidence = Assert-B001CaptureEvidence
    }
    $protocol = Invoke-PlayerInfoOracleProtocolSelfTest `
        -ExpectedChildPath $uiSwfPath
    $artifactContract =
        Invoke-PlayerInfoOracleV2ArtifactContractSelfTest
    $derivedTransaction =
        Invoke-PlayerInfoDerivedSwfTransactionSelfTest
    $dpi = Get-SystemDpiIdentity
    if ($dpi.dpi -le 0) {
        throw 'Validate-only DPI identity is invalid.'
    }
    $prefix = [System.Text.Encoding]::UTF8.GetBytes("old`n")
    $full = [System.Text.Encoding]::UTF8.GetBytes("old`nfresh`n")
    $freshProbe = Get-FreshFlashLogFromFullBytes `
        -BeforeBytes $prefix -FullBytes $full -StartedUtc ([datetime]::UtcNow)
    if ($freshProbe.mode -cne 'exact_prefix_tail' -or
        $freshProbe.text -cne "fresh`n") {
        throw 'Validate-only flashlog watermark slicing failed.'
    }
    $emptyBytes = [byte[]]@()
    $emptyProbe = Get-FreshFlashLogFromFullBytes `
        -BeforeBytes $emptyBytes `
        -FullBytes $emptyBytes `
        -StartedUtc ([datetime]::UtcNow)
    if ($emptyProbe.mode -cne 'exact_prefix_tail' -or
        $emptyProbe.bytes.Length -ne 0 -or
        $emptyProbe.fullSha256 -cne
            'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') {
        throw 'Validate-only empty flashlog watermark handling failed.'
    }
    $noTerminal = Get-ExactTerminalKind `
        -FreshText '' `
        -RunId '00000000000000000000000000000000'
    if ($null -ne $noTerminal) {
        throw 'Validate-only empty flashlog reported a terminal record.'
    }
    $terminalAttributes = (Get-Command Get-ExactTerminalKind).Parameters[
        'FreshText'].Attributes
    if (-not @($terminalAttributes | Where-Object {
        $_ -is [System.Management.Automation.AllowEmptyStringAttribute]
    }).Count) {
        throw 'Empty flashlog text binding is not admitted by the terminal scanner.'
    }
    foreach ($commandName in @(
        'Get-FreshFlashLogFromFullBytes',
        'Get-CurrentFreshFlashLog',
        'Get-StableFinalFlashLog',
        'Wait-ForOwnedPlayerAndStableTrace'
    )) {
        $attributes = (Get-Command $commandName).Parameters[
            'BeforeBytes'].Attributes
        if (-not @($attributes | Where-Object {
            $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute]
        }).Count) {
            throw "Empty flashlog watermark binding is not admitted: $commandName"
        }
    }
    foreach ($path in $watchedPaths) {
        $after = Get-FileIdentity -Path $path | ConvertTo-Json -Compress
        if ($after -cne $before[$path]) {
            throw "Validate-only mutated a watched path: $path"
        }
    }
    Assert-RegisteredFlashDebugPlayerCurrent -Expected $validatePlayer
    $validateFlashPidsAfter = @(
        Get-Process -Name Flash -ErrorAction SilentlyContinue |
            Sort-Object -Property Id |
            ForEach-Object { [int]$_.Id }
    )
    if ($validateFlashPidsAfter.Count -ne 1 -or
        [int]$validateFlashPidsAfter[0] -ne
            [int]$validateFlashPidsBefore[0]) {
        throw 'Validate-only changed the running Flash authoring PID set.'
    }
    $schemaStatus = if ($evidence -and $evidence.gitCanonicalSchema) {
        ('{0}/git-canonical/{1}-{2}' -f
            $evidence.evidenceRevision,
            $evidence.authoredDefinitionEdges,
            $evidence.pathExpandedRuntimeEdges)
    } elseif ($evidence) {
        'legacy-evidence-detected'
    } else {
        'B0-01A-evidence-absent'
    }
    Write-Host (
        '[OK] player-info oracle validate-only passed; ' +
        "PART records=$($protocol.partRecordCount), " +
        "CLEAR records=$($protocol.clearRecordCount), " +
        "maxPART=$($protocol.maxPartLineChars), " +
        "canonicalSummaryRecords=$($protocol.canonicalSummaryRecords), " +
        "PNG roundTrips=$($protocol.pngRoundTrips), " +
        "artifactSchemas=v2/v2, " +
        "artifactCases=$($artifactContract.cases), " +
        "falseRuntimeClaimRejected=$($artifactContract.falseRuntimeClaimRejected), " +
        "historicalV1Rejected=$($artifactContract.historicalV1Rejected), " +
        "SWF recovery=$($derivedTransaction.recoveryScenarios), " +
        "recovery negatives=$($derivedTransaction.recoveryAdmissionNegatives), " +
        "strictToolIdentity=$($validateTooling.status), " +
        "authoring=$($validateAuthoring.fileVersion)/limited-info, " +
        'authoring negatives=2, ' +
        "player=$($validatePlayer.fileVersion)/registered-debug, " +
        "templateStaticMax=$($template.staticWorstPartChars), " +
        "closure=$schemaStatus; Flash was not started.")
}

if ($ValidateOnly) {
    Invoke-ValidateOnly
    return
}

$template = Assert-OracleTemplate
Assert-RunnerStaticContract
$playerRegistration = Get-RegisteredFlashDebugPlayerIdentity `
    -ExpectedSha256 $ExpectedPlayerSha256
$playerPath = [string]$playerRegistration.path
$requiredCapturePaths = @(
    $protocolHelperPath,
    $scratchHelperPath,
    $compilePath,
    $publishProfilePath,
    $uiSwfPath,
    $mainSwfPath,
    $playerPath,
    $formulaPath,
    $closurePath,
    $chainPath
)
foreach ($path in $requiredCapturePaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required B0-01B capture input is missing: $path"
    }
}

$uiSwfHash = Get-PathSha256 -Path $uiSwfPath
if ($uiSwfHash -cne $ExpectedUiSwfSha256.ToUpperInvariant()) {
    throw ("UI child SWF identity drifted: expected {0}, got {1}." -f
        $ExpectedUiSwfSha256.ToUpperInvariant(), $uiSwfHash)
}
$playerHash = [string]$playerRegistration.sha256
$b001Evidence = Assert-B001CaptureEvidence
if (-not $b001Evidence.gitCanonicalSchema) {
    throw ('B0-01A evidence has not yet migrated to gitBlobBytes/gitBlobSha256; ' +
        'capture is fail-closed until the Git-canonical schema lands.')
}
$frozenInputs = [ordered]@{
    captureRunner = New-FrozenFileInput `
        -Path $PSCommandPath -Label $captureRunnerRelativePath
    protocolHelper = New-FrozenFileInput `
        -Path $protocolHelperPath -Label $protocolHelperRelativePath
    childSwf = New-FrozenFileInput `
        -Path $uiSwfPath -Label $uiSwfRelativePath
    mainSwf = New-FrozenFileInput `
        -Path $mainSwfPath -Label $mainSwfRelativePath
    template = New-FrozenFileInput `
        -Path $templatePath `
        -Label 'scripts/test-runners/player-info-oracle/TestLoader.as.template'
    displayFormula = New-FrozenFileInput `
        -Path $formulaPath -Label $formulaRelativePath
    placementClosure = New-FrozenFileInput `
        -Path $closurePath -Label $closureRelativePath
    sourceBinaryChain = New-FrozenFileInput `
        -Path $chainPath -Label $chainRelativePath
}
if ($frozenInputs.childSwf.sha256 -cne $uiSwfHash -or
    $frozenInputs.mainSwf.sha256 -cne $b001Evidence.chainMainSha256 -or
    $frozenInputs.template.sha256 -cne $template.sha256) {
    throw 'Prevalidated child/main/template identity changed before capture freeze.'
}
$strictCaptureTooling = Get-StrictCaptureToolingSet `
    -RunnerFrozen $frozenInputs.captureRunner `
    -ProtocolFrozen $frozenInputs.protocolHelper `
    -RequireStrict
if ($strictCaptureTooling.status -cne 'strict') {
    throw 'True capture tooling did not reach strict Git identity.'
}

$normalizedRoot = $projectDir.TrimEnd('\').ToUpperInvariant()
$repoHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHash = ([System.BitConverter]::ToString(
        $repoHasher.ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($normalizedRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $repoHasher.Dispose()
}

$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $repoHash)
$compileMutexAcquired = $false
$scratchTransaction = $null
$derivedSwfTransaction = $null
$installedHash = $null
$compileLease = $null
$compileInvoked = $false
$compileReturned = $false
$compileTerminalSafeAfterReturn = $false
$compiledIdentityFrozen = $false
$compiledLoaderFrozen = $null
$swfRestored = $false
$sourceRestored = $false
$derivedCleanupDone = $false
$restoredIdentityVerifiedUnderMutex = $false
$ownedPlayer = $null
$runId = [System.Guid]::NewGuid().ToString('N')
$script:currentPlayerInfoOracleRunId = $runId
$captureStartedUtc = [System.DateTime]::UtcNow
$workDir = $null
$finalRunDir = $null
$manifest = $null
$candidatePayloadReady = $false
$cleanupSucceeded = $false

try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Set-CompileStateUncertain `
            -Reason 'capture runner observed an abandoned repository compile mutex'
        throw 'A previous compile abandoned the repository mutex.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile owns this repository; capture refused.'
    }
    if (Test-Path -LiteralPath $uncertainMarker) {
        throw 'Compile state is uncertain; capture refused.'
    }
    $recoveryDirectory = Join-Path $scriptsDir '.testloader-scratch-recovery'
    if ((Test-Path -LiteralPath $recoveryDirectory) -and
        @(Get-ChildItem -LiteralPath $recoveryDirectory `
            -Filter '*.TestLoader.swf.sidecar.json' -Force).Count -ne 0) {
        throw 'A derived TestLoader.swf recovery sidecar blocks capture.'
    }
    foreach ($frozen in $frozenInputs.Values) {
        Assert-FrozenFileInputCurrent -Frozen $frozen
    }
    Assert-StrictCaptureToolingCurrent `
        -Expected $strictCaptureTooling `
        -RunnerFrozen $frozenInputs.captureRunner `
        -ProtocolFrozen $frozenInputs.protocolHelper
    $compileLease = 'v1:{0}:{1}:{2}' -f
        $repoHash, $PID, [System.Guid]::NewGuid().ToString('N')
    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $scratchMarker `
        -RunnerPath $scratchRunnerPath `
        -RepoHash $repoHash `
        -CompileLease $compileLease `
        -OwnerKind 'player-info-oracle'
    $derivedSwfTransaction = New-PlayerInfoDerivedSwfTransaction `
        -SourceTransaction $scratchTransaction `
        -SwfPath $loaderSwfPath
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    Write-AtomicBytes `
        -Path $scratchRunnerPath `
        -Bytes $frozenInputs.template.bytes
    $installedText = [System.IO.File]::ReadAllText(
        $scratchRunnerPath, [System.Text.Encoding]::UTF8)
    if ([regex]::Matches(
            $installedText, '__PLAYER_INFO_ORACLE_RUN_ID__').Count -ne 1) {
        throw 'Installed TestLoader template has an invalid runId placeholder count.'
    }
    $installedText = $installedText.Replace(
        '__PLAYER_INFO_ORACLE_RUN_ID__', $runId)
    [System.IO.File]::WriteAllText(
        $scratchRunnerPath,
        $installedText,
        [System.Text.UTF8Encoding]::new($true)
    )
    if (-not (Test-Utf8Bom -Path $scratchRunnerPath) -or
        $installedText -match '__PLAYER_INFO_ORACLE_RUN_ID__' -or
        [regex]::Matches($installedText, [regex]::Escape($runId)).Count -ne 1) {
        throw 'Installed TestLoader runner failed BOM/runId installation.'
    }
    $installedHash = Get-PathSha256 -Path $scratchRunnerPath

    $compileWatched = @($loaderSwfPath, $compileOutputPath, $compilerErrorsPath)
    $compileBefore = @{}
    foreach ($path in $compileWatched) {
        $compileBefore[$path] = Get-FileIdentity -Path $path | ConvertTo-Json -Compress
    }
    $compileStartedUtc = [System.DateTime]::UtcNow
    $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
    try {
        $env:CF7_FLASH_COMPILE_LEASE = $compileLease
        $compileInvoked = $true
        & powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File $compilePath `
            -Target test `
            -PublishOnly `
            -VerifySwf 'scripts/TestLoader.swf' `
            -TimeoutSeconds $CompileTimeoutSeconds
        $compileExitCode = $LASTEXITCODE
        $compileReturned = $true
    } finally {
        if ($null -eq $previousCompileLease) {
            Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
        } else {
            $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
        }
    }
    $compileTerminalSafeAfterReturn =
        -not (Test-Path -LiteralPath $uncertainMarker)
    $freezeDecision = Get-PlayerInfoCompileRecoveryDecision `
        -CompileInvoked $compileInvoked `
        -CompileReturned $compileReturned `
        -TerminalSafeAfterReturn $compileTerminalSafeAfterReturn `
        -CompiledIdentityFrozen $false `
        -UncertainMarkerPath $uncertainMarker
    if (-not $freezeDecision.canFreeze) {
        Set-CompileStateUncertain -Reason (
            'compile returned without terminal-safe admission; TestLoader.as/SWF ' +
            "recovery material retained; reason=$($freezeDecision.reason); " +
            "runId=$runId")
        throw (
            'Compile was not terminal-safe after return; refusing SWF identity ' +
            'freeze and all automatic recovery.')
    }
    $compiledLoaderFrozen = Freeze-PlayerInfoDerivedSwfCompiledIdentity `
        -Transaction $derivedSwfTransaction
    $compiledIdentityFrozen = $true
    $postFreezeDecision = Get-PlayerInfoCompileRecoveryDecision `
        -CompileInvoked $compileInvoked `
        -CompileReturned $compileReturned `
        -TerminalSafeAfterReturn $compileTerminalSafeAfterReturn `
        -CompiledIdentityFrozen $compiledIdentityFrozen `
        -UncertainMarkerPath $uncertainMarker
    if (-not $postFreezeDecision.canRestore) {
        Set-CompileStateUncertain -Reason (
            'compile state became nonterminal during SWF identity freeze; ' +
            "recovery material retained; reason=$($postFreezeDecision.reason); " +
            "runId=$runId")
        throw 'Compile state lost automatic-recovery admission after SWF freeze.'
    }
    if ($compileExitCode -ne 0) {
        throw "Player-info TestLoader publish-only compile exited $compileExitCode."
    }
    foreach ($path in $compileWatched) {
        $after = Get-FileIdentity -Path $path
        if (-not $after.exists -or
            ($after | ConvertTo-Json -Compress) -ceq $compileBefore[$path] -or
            ([datetime]$after.lastWriteUtc) -lt $compileStartedUtc.AddSeconds(-1)) {
            throw "Publish-only evidence was not freshly replaced: $path"
        }
    }
    $compilerErrors = [System.IO.File]::ReadAllText(
        $compilerErrorsPath, [System.Text.Encoding]::UTF8)
    if ($compilerErrors -notmatch
        '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
        throw 'Publish-only compiler diagnostics are not 0 errors / 0 warnings.'
    }
    $flashAuthoring = Get-FlashAuthoringIdentity
    $loaderSwfHash = [string]$compiledLoaderFrozen.sha256
    $postCompileInputs = [ordered]@{
        compileOutput = New-FrozenFileInput `
            -Path $compileOutputPath -Label 'scripts/compile_output.txt'
        compilerErrors = New-FrozenFileInput `
            -Path $compilerErrorsPath -Label 'scripts/compiler_errors.txt'
        publishProfile = New-FrozenFileInput `
            -Path $publishProfilePath `
            -Label 'scripts/TestLoader/PublishSettings.xml'
        compiledTestLoaderSource = New-FrozenFileInput `
            -Path $scratchRunnerPath -Label 'compiled scripts/TestLoader.as'
    }
    if ($postCompileInputs.compiledTestLoaderSource.sha256 -cne $installedHash) {
        throw 'Compiled TestLoader.as changed after scratch installation.'
    }
    foreach ($frozen in $frozenInputs.Values) {
        Assert-FrozenFileInputCurrent -Frozen $frozen
    }
    foreach ($frozen in $postCompileInputs.Values) {
        Assert-FrozenFileInputCurrent -Frozen $frozen
    }
    Assert-PlayerInfoDerivedSwfCompiledCurrent `
        -Transaction $derivedSwfTransaction
    $preLaunchDecision = Get-PlayerInfoCompileRecoveryDecision `
        -CompileInvoked $compileInvoked `
        -CompileReturned $compileReturned `
        -TerminalSafeAfterReturn $compileTerminalSafeAfterReturn `
        -CompiledIdentityFrozen $compiledIdentityFrozen `
        -UncertainMarkerPath $uncertainMarker
    if (-not $preLaunchDecision.canRestore) {
        Set-CompileStateUncertain -Reason (
            'compile state became nonterminal before player launch; recovery ' +
            "material retained; reason=$($preLaunchDecision.reason); runId=$runId")
        throw 'Compile state lost automatic-recovery admission before player launch.'
    }

    $flashlogBeforeBytes = Read-SharedBytes -Path $globalFlashLog
    $flashlogWatermark = Get-FileIdentity -Path $globalFlashLog
    $playerLaunchPlan = Get-PlayerInfoStandaloneLaunchPlan `
        -ScriptsDirectory $scriptsDir `
        -ExpectedLoaderSwfPath $loaderSwfPath
    $playerStartedUtc = [System.DateTime]::UtcNow
    Assert-RegisteredFlashDebugPlayerCurrent -Expected $playerRegistration
    $ownedPlayer = Start-Process `
        -FilePath $playerPath `
        -ArgumentList $playerLaunchPlan.argumentToken `
        -WorkingDirectory $scriptsDir `
        -PassThru
    if ($null -eq $ownedPlayer -or $ownedPlayer.Id -le 0) {
        throw 'Start-Process did not return an exact owned player PID.'
    }
    $ownedPlayer.Refresh()
    if ([System.IO.Path]::GetFullPath([string]$ownedPlayer.Path) -ine
        $playerPath) {
        throw 'Owned standalone player path did not match its frozen registration.'
    }
    Assert-RegisteredFlashDebugPlayerCurrent -Expected $playerRegistration
    $ownedPlayerId = $ownedPlayer.Id
    $terminalResult = Wait-ForOwnedPlayerAndStableTrace `
        -Process $ownedPlayer `
        -BeforeBytes $flashlogBeforeBytes `
        -StartedUtc $playerStartedUtc `
        -RunId $runId `
        -DeadlineUtc ([System.DateTime]::UtcNow.AddSeconds($CaptureTimeoutSeconds))
    $finalSnapshot = $terminalResult.stability.snapshot
    $parsed = Test-PlayerInfoOracleTrace `
        -FreshText $finalSnapshot.text `
        -RunId $runId `
        -ExpectedChildPath $uiSwfPath
    if (-not $terminalResult.naturalExit -or
        $terminalResult.finalTerminalKind -cne 'COMPLETE') {
        throw 'Final stable trace did not close with a natural exact COMPLETE.'
    }
    Assert-RegisteredFlashDebugPlayerCurrent -Expected $playerRegistration
    $ownedPlayer.Dispose()
    $ownedPlayer = $null

    if (-not (Test-Path -LiteralPath $tmpRoot)) {
        [void](New-Item -ItemType Directory -Path $tmpRoot)
    }
    $runName = '{0}-{1}' -f
        $captureStartedUtc.ToString('yyyyMMddTHHmmssZ'), $runId
    $workDir = Join-Path $tmpRoot ('.incomplete-' + $runName)
    $finalRunDir = Join-Path $tmpRoot $runName
    if ((Test-Path -LiteralPath $workDir) -or
        (Test-Path -LiteralPath $finalRunDir)) {
        throw 'Oracle candidate directory unexpectedly already exists.'
    }
    [void](New-Item -ItemType Directory -Path $workDir)
    $evidenceDir = Join-Path $workDir 'evidence'
    [void](New-Item -ItemType Directory -Path $evidenceDir)

    $snapshots = [ordered]@{}
    $snapshots.loaderSwf = New-CandidateSnapshot `
        -EvidenceDirectory $evidenceDir `
        -Name 'loader-TestLoader.swf' `
        -Bytes $compiledLoaderFrozen.bytes
    if ($snapshots.loaderSwf.sha256 -cne $loaderSwfHash) {
        throw 'Loader snapshot does not equal the actual frozen launch identity.'
    }
    $snapshots.childSwf = New-CandidateSnapshot `
        -EvidenceDirectory $evidenceDir `
        -Name 'player-info-child.swf' `
        -Bytes $frozenInputs.childSwf.bytes
    $snapshots.mainSwf = New-CandidateSnapshot `
        -EvidenceDirectory $evidenceDir `
        -Name 'main-identity-reference.swf' `
        -Bytes $frozenInputs.mainSwf.bytes
    $snapshots.freshFlashlog = New-CandidateSnapshot `
        -EvidenceDirectory $evidenceDir `
        -Name 'flashlog-fresh.bin' `
        -Bytes $finalSnapshot.bytes
    $snapshots.freshFlashlog['localOnlyDoNotPromote'] = $true
    $snapshots.freshFlashlog['mayContainEscapedAbsolutePath'] = $true
    $blockBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        $parsed.rawBlockText + "`n")
    $snapshots.oracleRunBlock = New-CandidateSnapshot `
        -EvidenceDirectory $evidenceDir `
        -Name 'oracle-run-block.txt' `
        -Bytes $blockBytes
    $snapshots.oracleRunBlock['localOnlyDoNotPromote'] = $true
    $snapshots.oracleRunBlock['mayContainEscapedAbsolutePath'] = $true
    $canonicalSummary = New-PlayerInfoOracleCanonicalSummary -Parsed $parsed
    $snapshots.canonicalRunSummary = New-CandidateSnapshot `
        -EvidenceDirectory $evidenceDir `
        -Name 'oracle-run-summary.canonical.txt' `
        -Bytes $canonicalSummary.bytes
    $snapshots.canonicalRunSummary['promotable'] = $true
    $snapshotInputSpecs = @(
        [pscustomobject]@{
            name = 'capture-flash-oracle.ps1'
            key = 'captureRunner'
            input = $frozenInputs.captureRunner
        },
        [pscustomobject]@{
            name = 'flash-oracle-protocol.ps1'
            key = 'protocolHelper'
            input = $frozenInputs.protocolHelper
        },
        [pscustomobject]@{
            name = 'compile-output.txt'
            key = 'compileOutput'
            input = $postCompileInputs.compileOutput
        },
        [pscustomobject]@{
            name = 'compiler-errors.txt'
            key = 'compilerErrors'
            input = $postCompileInputs.compilerErrors
        },
        [pscustomobject]@{
            name = 'TestLoader-PublishSettings.xml'
            key = 'publishProfile'
            input = $postCompileInputs.publishProfile
        },
        [pscustomobject]@{
            name = 'compiled-TestLoader.as'
            key = 'compiledTestLoaderSource'
            input = $postCompileInputs.compiledTestLoaderSource
        },
        [pscustomobject]@{
            name = 'TestLoader.as.template'
            key = 'template'
            input = $frozenInputs.template
        },
        [pscustomobject]@{
            name = 'player-info-formula.as'
            key = 'displayFormula'
            input = $frozenInputs.displayFormula
        },
        [pscustomobject]@{
            name = 'b0-01-closure.json'
            key = 'placementClosure'
            input = $frozenInputs.placementClosure
        },
        [pscustomobject]@{
            name = 'b0-01-source-binary-chain.json'
            key = 'sourceBinaryChain'
            input = $frozenInputs.sourceBinaryChain
        }
    )
    foreach ($snapshotSpec in $snapshotInputSpecs) {
        $snapshots[$snapshotSpec.key] = New-CandidateSnapshot `
            -EvidenceDirectory $evidenceDir `
            -Name $snapshotSpec.name `
            -Bytes $snapshotSpec.input.bytes
    }

    $manifestCases = [System.Collections.Generic.List[object]]::new()
    foreach ($case in $parsed.cases) {
        $caseId = [string]$case.expected.caseId
        $bounds = Get-PlayerInfoOracleAlphaBounds `
            -Argb $case.argb -Width 1024 -Height 576
        $rawPng = Convert-PlayerInfoOracleArgbToPngBytes `
            -Argb $case.argb -Width 1024 -Height 576
        $croppedArgb = Get-PlayerInfoOracleCroppedArgb `
            -Argb $case.argb -SourceWidth 1024 -Bounds $bounds
        $cropPng = Convert-PlayerInfoOracleArgbToPngBytes `
            -Argb $croppedArgb `
            -Width ([int]$bounds.width) `
            -Height ([int]$bounds.height)
        Assert-PlayerInfoOraclePngPixels `
            -PngBytes $rawPng `
            -ExpectedArgb $case.argb `
            -ExpectedWidth 1024 `
            -ExpectedHeight 576 `
            -Scenario "$caseId raw capture"
        Assert-PlayerInfoOraclePngPixels `
            -PngBytes $cropPng `
            -ExpectedArgb $croppedArgb `
            -ExpectedWidth ([int]$bounds.width) `
            -ExpectedHeight ([int]$bounds.height) `
            -Scenario "$caseId crop capture"
        $rawName = $caseId + '.raw.png'
        $cropName = $caseId + '.crop.png'
        Write-AtomicBytes -Path (Join-Path $workDir $rawName) -Bytes $rawPng
        Write-AtomicBytes -Path (Join-Path $workDir $cropName) -Bytes $cropPng
        $manifestCases.Add([ordered]@{
            caseId = $caseId
            state = $case.state
            rawArgbSha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $case.argb
            raw = [ordered]@{
                path = $rawName
                width = 1024
                height = 576
                sha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $rawPng
            }
            crop = [ordered]@{
                path = $cropName
                rectangle = [ordered]@{
                    x = [int]$bounds.x
                    y = [int]$bounds.y
                    width = [int]$bounds.width
                    height = [int]$bounds.height
                }
                sha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $cropPng
            }
        })
    }

    $dpi = Get-SystemDpiIdentity
    $manifest = [ordered]@{
        schema = 'cf7.player_info.flash_oracle_manifest.v2'
        status = 'candidate'
        runId = $runId
        capturedUtc = [System.DateTime]::UtcNow.ToString('o')
        requiresHumanReview = $true
        source = [ordered]@{
            placementClosure = [ordered]@{
                path = $closureRelativePath
                evidenceRevision = $b001Evidence.evidenceRevision
                closureDigest = $b001Evidence.closureDigest
                placementCardinality = [ordered]@{
                    authoredDefinitionEdges =
                        $b001Evidence.authoredDefinitionEdges
                    pathExpandedRuntimeEdges =
                        $b001Evidence.pathExpandedRuntimeEdges
                }
                capturedPlacementProfile =
                    $b001Evidence.capturePlacementProfile
                referencePlacementProfile =
                    $b001Evidence.captureReferencePlacementProfile
                mainRslPlacementEquivalent =
                    $b001Evidence.captureMainRslPlacementEquivalent
                extractionMode =
                    $b001Evidence.captureExtractionMode
                mainParticipatesInCapture =
                    $b001Evidence.captureMainParticipates
                mainBinaryRole =
                    $b001Evidence.captureMainBinaryRole
                childDocumentWrapperApplied =
                    $b001Evidence.captureChildDocumentWrapperApplied
                exportedSymbolRootTy =
                    $b001Evidence.captureExportedSymbolRootTy
                mainPlacementY =
                    $b001Evidence.captureMainPlacementY
                standaloneDocumentWrapperMatrix =
                    $b001Evidence.standaloneDocumentWrapperMatrix
                mainRslReference = [ordered]@{
                    placementProfile =
                        $b001Evidence.mainRslPlacementProfile
                    exportedSymbolRootMatrix =
                        $b001Evidence.mainRslExportedSymbolRootMatrix
                    hpRelativeMatrix =
                        $b001Evidence.mainRslHpRelativeMatrix
                    mpRelativeMatrix =
                        $b001Evidence.mainRslMpRelativeMatrix
                }
                snapshot = $snapshots.placementClosure
            }
            sourceBinaryChain = [ordered]@{
                path = $chainRelativePath
                evidenceRevision = $b001Evidence.sourceBinaryRevision
                childSha256 = $b001Evidence.chainUiSha256
                mainSha256 = $b001Evidence.chainMainSha256
                captureContractRole =
                    'historical_pre_v2_plan_and_identity_chain_only'
                snapshot = $snapshots.sourceBinaryChain
            }
            formula = [ordered]@{
                path = $formulaRelativePath
                snapshot = $snapshots.displayFormula
            }
            uiSwf = [ordered]@{
                path = $uiSwfRelativePath
                sha256 = $uiSwfHash
                executionRole = 'loaded_exported_symbol_source'
                snapshot = $snapshots.childSwf
            }
            mainSwf = [ordered]@{
                path = $mainSwfRelativePath
                sha256 = $b001Evidence.chainMainSha256
                executionRole = 'identity_chain_reference_only'
                mainParticipatesInCapture = $false
                snapshot = $snapshots.mainSwf
            }
            loaderSwf = [ordered]@{
                path = 'scripts/TestLoader.swf'
                sha256 = $loaderSwfHash
                snapshot = $snapshots.loaderSwf
            }
            childRuntimeBinding = [ordered]@{
                expectedRepoRelativePath = $uiSwfRelativePath
                exactCanonicalMatch = [bool]$parsed.childBinding.matched
                escapedUrlSha256 = $parsed.childBinding.escapedUrlSha256
                reportedUrlSha256 = $parsed.childBinding.reportedUrlSha256
                canonicalPathSha256 = $parsed.childBinding.canonicalPathSha256
            }
            captureLoaderContract = [ordered]@{
                actualCaptureLoaderVerified = $true
                actualLoaderPath = 'scripts/TestLoader.swf'
                childPathVerified = $uiSwfRelativePath
                placementProfile =
                    $b001Evidence.capturePlacementProfile
                referencePlacementProfile =
                    $b001Evidence.captureReferencePlacementProfile
                extractionMode =
                    $b001Evidence.captureExtractionMode
                mainRslPlacementEquivalent = $true
                mainParticipatesInCapture = $false
                mainBinaryRole = 'identity_chain_reference_only'
                asLoaderParticipatesInCapture = $false
                childDocumentWrapperApplied = $false
                exportedSymbolRootTy = 0
                mainPlacementY = 512
            }
            compile = [ordered]@{
                command = (
                    'scripts/compile_test.ps1 -Target test -PublishOnly ' +
                    '-VerifySwf scripts/TestLoader.swf')
                publishProfile = $snapshots.publishProfile
                compileOutput = $snapshots.compileOutput
                compilerErrors = $snapshots.compilerErrors
                compiledTestLoaderSource = $snapshots.compiledTestLoaderSource
                template = $snapshots.template
                flashAuthoring = [ordered]@{
                    fileName = $flashAuthoring.fileName
                    fileVersion = $flashAuthoring.fileVersion
                    productVersion = $flashAuthoring.productVersion
                    sha256 = $flashAuthoring.sha256
                    registeredTaskMatched = $true
                }
            }
        }
        captureTooling = [ordered]@{
            strictToolIdentity = 'head_index_clean_filter_equal'
            headCommit = [string]$strictCaptureTooling.headCommit
            files = @(
                [ordered]@{
                    role = 'capture_runner'
                    path = $captureRunnerRelativePath
                    bytes = [long]$frozenInputs.captureRunner.length
                    sha256 = [string]$frozenInputs.captureRunner.sha256
                    gitBlobOid =
                        [string]$strictCaptureTooling.runner.gitBlobOid
                    gitBlobBytes =
                        [long]$strictCaptureTooling.runner.gitBlobBytes
                    gitBlobSha256 =
                        [string]$strictCaptureTooling.runner.gitBlobSha256
                    snapshot = $snapshots.captureRunner
                },
                [ordered]@{
                    role = 'protocol_helper'
                    path = $protocolHelperRelativePath
                    bytes = [long]$frozenInputs.protocolHelper.length
                    sha256 = [string]$frozenInputs.protocolHelper.sha256
                    gitBlobOid =
                        [string]$strictCaptureTooling.protocol.gitBlobOid
                    gitBlobBytes =
                        [long]$strictCaptureTooling.protocol.gitBlobBytes
                    gitBlobSha256 =
                        [string]$strictCaptureTooling.protocol.gitBlobSha256
                    snapshot = $snapshots.protocolHelper
                }
            )
        }
        runtime = [ordered]@{
            player = [ordered]@{
                path = $playerLogicalPath
                pathKind = 'registered-task-relative'
                registeredTask = $playerRegistration.registeredTask
                registeredTaskPath =
                    $playerRegistration.registeredTaskPath
                registeredTaskActionMatched = $true
                relativeToAuthoringRoot =
                    $playerRegistration.relativeToAuthoringRoot
                fileVersion = $playerRegistration.fileVersion
                productVersion = $playerRegistration.productVersion
                bytes = [long]$playerRegistration.length
                sha256 = $playerHash
                authenticodeStatus =
                    $playerRegistration.authenticodeStatus
                signerThumbprint =
                    $playerRegistration.signerThumbprint
                ownedProcessId = $ownedPlayerId
                naturalExit = $true
            }
            windows = [ordered]@{
                version = [System.Environment]::OSVersion.VersionString
                architecture = $env:PROCESSOR_ARCHITECTURE
                systemDpi = [int]$dpi.dpi
                scalePercent = [int]$dpi.scalePercent
                affectsLogicalBitmapDraw = $false
            }
            flash = [ordered]@{
                quality = 'MEDIUM'
                stageScaleMode = 'noScale'
                stageAlignRequested = 'TL'
                stageAlignReported = 'LT'
                viewport = [ordered]@{ width = 500; height = 500 }
            }
            flashlog = [ordered]@{
                watermark = $flashlogWatermark
                consumptionMode = $finalSnapshot.mode
                finalFullLength = $finalSnapshot.fullLength
                finalFullSha256 = $finalSnapshot.fullSha256
                stablePolls =
                    [int]$terminalResult.stability.consecutiveStablePolls
                stabilityPollMilliseconds =
                    [int]$terminalResult.stability.pollMilliseconds
                freshSnapshot = $snapshots.freshFlashlog
                exactRunBlock = $snapshots.oracleRunBlock
                canonicalRunSummary = $snapshots.canonicalRunSummary
                canonicalRunSummaryRecordCount =
                    [int]$canonicalSummary.recordCount
                physicalRecordCount = $parsed.physicalRecordCount
            }
        }
        capture = [ordered]@{
            captureMethod = 'AVM1 BitmapData.draw'
            protocol = [ordered]@{
                rowBytes = 4096
                rowsPerCase = 576
                partPayloadChars = 720
                partsPerRow = 8
                zeroRowRecord = 'CLEAR'
                zeroRowValue = '00000000'
                observedPartRecords = [int]$parsed.partRecordCount
                observedClearRecords = [int]$parsed.clearRecordCount
                physicalRecordMaxChars = 1000
                caseOrder = @(
                    'empty', 'min_step', 'p25', 'p50', 'p75', 'p99', 'full',
                    'mp_vf34', 'mp_vf35', 'mp_vf70', 'mp_vf91')
            }
            canvas = [ordered]@{
                width = 1024
                height = 576
                matrix = @(1, 0, 0, 1, 0, 512)
                coordinateSpace = 'main_stage'
                contentViewport = @(0, 0, 1024, 576)
                source = 'loaded_child_exported_symbol_instance'
                sourceDocumentInstanceMatrix = @(1, 0, 0, 1, 0, 3)
                childDocumentWrapperApplied = $false
                pixelFormat = 'straight_argb32'
                background = 'transparent_argb_0'
                compositeBackgroundId = $null
            }
            cases = @($manifestCases)
        }
        transaction = [ordered]@{
            sourceScratch = [ordered]@{
                markerPath = 'scripts/testloader_scratch_inflight.marker'
                markerBodySha256 =
                    $derivedSwfTransaction.Record.sourceMarkerSha256
                originalExisted = [bool]$scratchTransaction.HadRunner
                originalSha256 = $scratchTransaction.OriginalHash
                installedSha256 = $installedHash
                restoredByteExact = $false
            }
            derivedSwf = [ordered]@{
                schema = [string]$derivedSwfTransaction.Record.schema
                token = [string]$derivedSwfTransaction.Record.token
                targetPath = 'scripts/TestLoader.swf'
                sourceMarkerSha256 =
                    [string]$derivedSwfTransaction.Record.sourceMarkerSha256
                original = [ordered]@{
                    exists =
                        [bool]$derivedSwfTransaction.Record.original.exists
                    bytes =
                        [long]$derivedSwfTransaction.Record.original.bytes
                    sha256 =
                        [string]$derivedSwfTransaction.Record.original.sha256
                    lastWriteUtc =
                        [string]$derivedSwfTransaction.Record.original.lastWriteUtc
                }
                compiled = [ordered]@{
                    exists = $true
                    bytes =
                        [long]$derivedSwfTransaction.Record.compiled.bytes
                    sha256 =
                        [string]$derivedSwfTransaction.Record.compiled.sha256
                    lastWriteUtc =
                        [string]$derivedSwfTransaction.Record.compiled.lastWriteUtc
                }
                restored = $null
                sidecarAndBackupClearedAfterSourceRestore = $false
            }
            scratchRestoredByteExact = $false
            restoredSwfIdentityVerifiedUnderMutex = $false
            compileMutexReleasedBeforeCandidatePromotion = $false
        }
        humanReview = [ordered]@{
            status = 'required'
            reviewer = $null
            checks = [ordered]@{
                stateCorrect = $null
                noOtherHudLayers = $null
                cropDoesNotEatEdges = $null
                visualAestheticsAccepted = $null
            }
            promotionBoundary = (
                'Only a human may promote reviewed PNG/manifest evidence from ignored ' +
                'tmp/. Raw flashlog/run-block snapshots are local-only because they ' +
                'contain an escaped local file URL; only the rebuilt compact canonical ' +
                'run summary is promotable protocol evidence.')
        }
    }
    Assert-PlayerInfoOracleV2ManifestContract -Manifest $manifest
    foreach ($frozen in $frozenInputs.Values) {
        Assert-FrozenFileInputCurrent -Frozen $frozen
    }
    foreach ($frozen in $postCompileInputs.Values) {
        Assert-FrozenFileInputCurrent -Frozen $frozen
    }
    Assert-PlayerInfoDerivedSwfCompiledCurrent `
        -Transaction $derivedSwfTransaction
    Assert-CandidateSnapshotSet `
        -WorkDirectory $workDir -Snapshots $snapshots
    Assert-PlayerInfoCaptureToolingBindings `
        -Snapshots $snapshots `
        -FrozenInputs $frozenInputs `
        -StrictTooling $strictCaptureTooling `
        -Manifest $manifest
    foreach ($caseManifest in $manifestCases) {
        foreach ($image in @($caseManifest.raw, $caseManifest.crop)) {
            $imagePath = Join-Path $workDir ([string]$image.path)
            if ((Get-PathSha256 -Path $imagePath) -cne [string]$image.sha256) {
                throw "Candidate PNG drifted before cleanup: $($image.path)"
            }
        }
    }
    $candidatePayloadReady = $true
} finally {
    try {
        if ($null -ne $ownedPlayer) {
            try {
                $ownedPlayer.Refresh()
                if (-not $ownedPlayer.HasExited) {
                    Stop-OwnedPlayerFailClosed `
                        -Process $ownedPlayer `
                        -Reason (
                            "capture failed while exact owned PID remained live; runId=$runId")
                }
            } catch {
                Write-PlayerInfoOracleBehaviorFailure `
                    -RunId $runId `
                    -Reason (
                    "exact owned PID cleanup failed; runId=$runId; " +
                    "error=$($_.Exception.Message)")
                throw
            } finally {
                $ownedPlayer.Dispose()
                $ownedPlayer = $null
            }
        }
    } finally {
        try {
            try {
                if ($derivedSwfTransaction) {
                    if ($compileInvoked) {
                        $restoreDecision =
                            Get-PlayerInfoCompileRecoveryDecision `
                                -CompileInvoked $compileInvoked `
                                -CompileReturned $compileReturned `
                                -TerminalSafeAfterReturn `
                                    $compileTerminalSafeAfterReturn `
                                -CompiledIdentityFrozen `
                                    $compiledIdentityFrozen `
                                -UncertainMarkerPath $uncertainMarker
                        if (-not $restoreDecision.canRestore) {
                            Set-CompileStateUncertain -Reason (
                                'automatic recovery denied by compile terminal-state ' +
                                "gate; reason=$($restoreDecision.reason); runId=$runId")
                            throw (
                                'Refusing automatic source/SWF recovery after a ' +
                                'nonterminal or marker-contaminated compile.')
                        }
                        Restore-PlayerInfoDerivedSwfTransaction `
                            -Transaction $derivedSwfTransaction `
                            -UncertainMarkerPath $uncertainMarker
                    } else {
                        Restore-PlayerInfoPreparedDerivedSwfTransaction `
                            -Transaction $derivedSwfTransaction
                    }
                    $swfRestored = $true
                } else {
                    $swfRestored = -not $compileInvoked
                }

                if ($scratchTransaction -and $swfRestored) {
                    if ($compileInvoked) {
                        $sourceRestoreDecision =
                            Get-PlayerInfoCompileRecoveryDecision `
                                -CompileInvoked $compileInvoked `
                                -CompileReturned $compileReturned `
                                -TerminalSafeAfterReturn `
                                    $compileTerminalSafeAfterReturn `
                                -CompiledIdentityFrozen `
                                    $compiledIdentityFrozen `
                                -UncertainMarkerPath $uncertainMarker
                        if (-not $sourceRestoreDecision.canRestore) {
                            throw (
                                'Compile-state marker appeared before source scratch ' +
                                'recovery; source marker and SWF recovery remain.')
                        }
                    }
                    if ($installedHash) {
                        Restore-Cf7TestLoaderScratchTransaction `
                            -Transaction $scratchTransaction `
                            -InstalledHash $installedHash
                    } else {
                        Complete-PlayerInfoUninstalledSourceScratchCleanup `
                            -Transaction $scratchTransaction
                    }
                    $sourceRestored = $true
                } elseif (-not $scratchTransaction) {
                    $sourceRestored = $true
                }

                if ($derivedSwfTransaction -and
                    $swfRestored -and $sourceRestored) {
                    if ($compileInvoked) {
                        $cleanupDecision =
                            Get-PlayerInfoCompileRecoveryDecision `
                                -CompileInvoked $compileInvoked `
                                -CompileReturned $compileReturned `
                                -TerminalSafeAfterReturn `
                                    $compileTerminalSafeAfterReturn `
                                -CompiledIdentityFrozen `
                                    $compiledIdentityFrozen `
                                -UncertainMarkerPath $uncertainMarker
                        if (-not $cleanupDecision.canRestore) {
                            throw (
                                'Compile-state marker appeared before recovery ' +
                                'sidecar cleanup; recovery material remains.')
                        }
                    }
                    [void](Assert-PlayerInfoRestoredSwfIdentity `
                        -Transaction $derivedSwfTransaction)
                    $restoredIdentityVerifiedUnderMutex = $true
                    Complete-PlayerInfoDerivedSwfCleanup `
                        -Transaction $derivedSwfTransaction
                    $derivedCleanupDone = $true
                } elseif (-not $derivedSwfTransaction) {
                    $derivedCleanupDone = $true
                }
                if ($candidatePayloadReady) {
                    foreach ($frozen in $frozenInputs.Values) {
                        Assert-FrozenFileInputCurrent -Frozen $frozen
                    }
                    Assert-RegisteredFlashDebugPlayerCurrent `
                        -Expected $playerRegistration
                    Assert-StrictCaptureToolingCurrent `
                        -Expected $strictCaptureTooling `
                        -RunnerFrozen $frozenInputs.captureRunner `
                        -ProtocolFrozen $frozenInputs.protocolHelper
                }
            } catch {
                [void](Set-PlayerInfoRecoveryUncertainIfNeeded `
                    -HasDerivedTransaction ($null -ne $derivedSwfTransaction) `
                    -HasScratchTransaction ($null -ne $scratchTransaction) `
                    -SwfRestored $swfRestored `
                    -SourceRestored $sourceRestored `
                    -DerivedCleanupDone $derivedCleanupDone `
                    -MarkerPath $uncertainMarker `
                    -Reason (
                        'TestLoader recovery did not reach verified sidecar cleanup; ' +
                        "recovery material retained; runId=$runId; " +
                        "error=$($_.Exception.Message)"))
                throw
            }
        } finally {
            if ($compileMutexAcquired) {
                $compileMutex.ReleaseMutex()
            }
            $compileMutex.Dispose()
            if ($scratchTransaction -and
                (Test-Path -LiteralPath $scratchTransaction.MarkerPath)) {
                Write-Warning (
                    'TestLoader scratch transaction remains fail-closed; recovery ' +
                    "backup: $($scratchTransaction.BackupPath)")
            } else {
                $cleanupSucceeded =
                    $swfRestored -and
                    $sourceRestored -and
                    $derivedCleanupDone
            }
        }
    }
}

if (-not $candidatePayloadReady -or -not $cleanupSucceeded -or
    -not $restoredIdentityVerifiedUnderMutex -or
    [string]::IsNullOrWhiteSpace($workDir) -or
    -not (Test-Path -LiteralPath $workDir)) {
    throw 'Capture payload did not reach post-restore candidate finalization.'
}
$manifest.transaction.scratchRestoredByteExact = $true
$manifest.transaction.sourceScratch.restoredByteExact = $true
$manifest.transaction.derivedSwf.restored =
    $derivedSwfTransaction.Record.restored
$manifest.transaction.derivedSwf.sidecarAndBackupClearedAfterSourceRestore =
    $true
$manifest.transaction.restoredSwfIdentityVerifiedUnderMutex =
    $restoredIdentityVerifiedUnderMutex
$manifest.transaction.compileMutexReleasedBeforeCandidatePromotion = $true
Assert-CandidateSnapshotSet `
    -WorkDirectory $workDir -Snapshots $snapshots
Assert-PlayerInfoCaptureToolingBindings `
    -Snapshots $snapshots `
    -FrozenInputs $frozenInputs `
    -StrictTooling $strictCaptureTooling `
    -Manifest $manifest
if ($snapshots.loaderSwf.sha256 -cne
        [string]$derivedSwfTransaction.Record.compiled.sha256 -or
    $snapshots.childSwf.sha256 -cne $frozenInputs.childSwf.sha256 -or
    $snapshots.mainSwf.sha256 -cne $frozenInputs.mainSwf.sha256 -or
    $snapshots.template.sha256 -cne $frozenInputs.template.sha256 -or
    $snapshots.displayFormula.sha256 -cne
        $frozenInputs.displayFormula.sha256 -or
    $snapshots.placementClosure.sha256 -cne
        $frozenInputs.placementClosure.sha256 -or
    $snapshots.sourceBinaryChain.sha256 -cne
        $frozenInputs.sourceBinaryChain.sha256) {
    throw 'Candidate snapshot closure no longer cross-binds its frozen inputs.'
}
$manifestPath = Join-Path $workDir 'oracle-manifest.json'
Write-AtomicUtf8Json -Path $manifestPath -Value $manifest
$receipt = [ordered]@{
    schema = 'cf7.player_info.flash_oracle_candidate_receipt.v2'
    status = 'candidate_ready_after_restore'
    runId = $runId
    placement = [ordered]@{
        placementProfile = 'main_rsl_exported_symbol_equivalent'
        referencePlacementProfile = 'main_rsl_exported_symbol'
        extractionMode = 'loaded_child_exported_symbol_instance'
        mainRslPlacementEquivalent = $true
        mainParticipatesInCapture = $false
        mainBinaryRole = 'identity_chain_reference_only'
        childDocumentWrapperApplied = $false
        exportedSymbolRootTy = 0
        mainPlacementY = 512
        canvas = @(1024, 576)
    }
    manifest = [ordered]@{
        path = 'oracle-manifest.json'
        schema = 'cf7.player_info.flash_oracle_manifest.v2'
        sha256 = Get-PathSha256 -Path $manifestPath
    }
    scratchRestoredByteExact = $true
    sourceScratch = [ordered]@{
        markerBodySha256 =
            [string]$derivedSwfTransaction.Record.sourceMarkerSha256
        originalSha256 = $scratchTransaction.OriginalHash
        installedSha256 = $installedHash
        restoredByteExact = $true
    }
    derivedSwf = [ordered]@{
        targetPath = 'scripts/TestLoader.swf'
        original = $manifest.transaction.derivedSwf.original
        compiled = $manifest.transaction.derivedSwf.compiled
        restored = $manifest.transaction.derivedSwf.restored
        recoveryArtifactsCleared = $true
    }
    canonicalRunSummary = $snapshots.canonicalRunSummary
    restoredSwfIdentityVerifiedUnderMutex =
        $restoredIdentityVerifiedUnderMutex
    compileMutexReleased = $true
    requiresHumanReview = $true
}
$manifestCandidateSha256 = Get-PathSha256 -Path $manifestPath
Assert-PlayerInfoOracleV2ReceiptContract `
    -Receipt $receipt `
    -ManifestSha256 $manifestCandidateSha256
$receiptPath = Join-Path $workDir 'candidate-receipt.json'
Write-AtomicUtf8Json -Path $receiptPath -Value $receipt
Assert-CandidateSnapshotSet `
    -WorkDirectory $workDir -Snapshots $snapshots
Assert-PlayerInfoCaptureToolingBindings `
    -Snapshots $snapshots `
    -FrozenInputs $frozenInputs `
    -StrictTooling $strictCaptureTooling `
    -Manifest $manifest
if ((Get-PathSha256 -Path $manifestPath) -cne
        [string]$receipt.manifest.sha256 -or
    -not (Test-Path -LiteralPath $receiptPath)) {
    throw 'Candidate manifest/receipt drifted before final move.'
}
Move-Item -LiteralPath $workDir -Destination $finalRunDir
Write-Host "[OK] Candidate Flash oracle captured under: $finalRunDir"
Write-Host (
    '[REVIEW REQUIRED] Candidate remains unaccepted until human state/layer/crop/' +
    'visual review and explicit repo-evidence promotion.')
