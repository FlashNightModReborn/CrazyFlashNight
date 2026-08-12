[CmdletBinding()]
param(
    [switch]$KeepBuildDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$testDirectory = $PSScriptRoot
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $testDirectory '..\..\..')).Path
$environmentCheck = Join-Path $projectRoot 'tools\check-runtime-build-env.ps1'
$sourcePath = Join-Path $testDirectory 'audio_bridge_v2_contract.c'
$nativeDirectory = (Resolve-Path -LiteralPath (Join-Path $testDirectory '..')).Path
$pinnedToolAssertion = Join-Path $nativeDirectory 'assert-pinned-tools.bat'
$miniaudioHeaderPath = Join-Path $nativeDirectory 'miniaudio.h'
$bridgeSourcePath = Join-Path $nativeDirectory 'miniaudio_bridge.c'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Audio ABI contract source is missing: $sourcePath"
}

foreach ($requiredSource in @($miniaudioHeaderPath, $bridgeSourcePath)) {
    if (-not (Test-Path -LiteralPath $requiredSource -PathType Leaf)) {
        throw "Audio device recovery contract source is missing: $requiredSource"
    }
}

function Assert-SourceContract([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Audio device recovery source contract failed: $Message"
    }
}

$miniaudioSource = [IO.File]::ReadAllText($miniaudioHeaderPath)
$bridgeSource = [IO.File]::ReadAllText($bridgeSourcePath)
$engineConfigDefinition = [regex]::Match(
    $miniaudioSource,
    '(?s)typedef struct\s*\{.*?ma_resampler_config pitchResampling;[^\r\n]*\r?\n#if !defined\(MA_NO_DEVICE_IO\)\s*struct\s*\{\s*ma_bool8 noAutoStreamRouting;[^\r\n]*\r?\n\s*\} wasapi;\s*#endif\s*\} ma_engine_config;')
Assert-SourceContract $engineConfigDefinition.Success `
    'ma_engine_config must append the conditional WASAPI routing field'

$engineConfigInitializer = [regex]::Match(
    $miniaudioSource,
    '(?s)MA_API ma_engine_config ma_engine_config_init\(void\)\s*\{(?<body>.*?)\r?\n\}')
Assert-SourceContract $engineConfigInitializer.Success `
    'ma_engine_config_init implementation is missing'
Assert-SourceContract `
    ($engineConfigInitializer.Groups['body'].Value -match 'MA_ZERO_OBJECT\(&config\);') `
    'ma_engine_config_init must preserve the zero/false default'

$forwardStatement =
    'deviceConfig.wasapi.noAutoStreamRouting = engineConfig.wasapi.noAutoStreamRouting;'
Assert-SourceContract `
    ([regex]::Matches(
        $miniaudioSource,
        [regex]::Escape($forwardStatement)).Count -eq 1) `
    'the engine field must transfer exactly once to its owned device config'
Assert-SourceContract `
    ([regex]::Matches(
        $bridgeSource,
        [regex]::Escape(
            'engineConfig.wasapi.noAutoStreamRouting = MA_TRUE;')).Count -eq 1) `
    'the CF7 bridge must disable miniaudio automatic routing exactly once'

$defaultDeviceCallback = [regex]::Match(
    $miniaudioSource,
    '(?s)static HRESULT STDMETHODCALLTYPE ma_IMMNotificationClient_OnDefaultDeviceChanged\(.*?\)\s*\{(?<body>.*?)\r?\n\}\s*\r?\nstatic HRESULT STDMETHODCALLTYPE ma_IMMNotificationClient_OnPropertyValueChanged')
Assert-SourceContract $defaultDeviceCallback.Success `
    'WASAPI default-device callback is missing'
$defaultDeviceBody = $defaultDeviceCallback.Groups['body'].Value
$flowGuardIndex = $defaultDeviceBody.IndexOf(
    'We only care about devices with the same data flow as the current device.',
    [StringComparison]::Ordinal)
$disabledRoutingIndex = $defaultDeviceBody.IndexOf(
    "Don't do automatic stream routing if we're not allowed.",
    [StringComparison]::Ordinal)
Assert-SourceContract `
    ($flowGuardIndex -ge 0 -and $disabledRoutingIndex -gt $flowGuardIndex) `
    'the data-flow guard must precede disabled-routing notification'
$disabledRoutingReturnIndex = $defaultDeviceBody.IndexOf(
    'return S_OK;',
    $disabledRoutingIndex,
    [StringComparison]::Ordinal)
Assert-SourceContract ($disabledRoutingReturnIndex -gt $disabledRoutingIndex) `
    'disabled-routing branch return is missing'
$disabledRoutingBody = $defaultDeviceBody.Substring(
    $disabledRoutingIndex,
    $disabledRoutingReturnIndex - $disabledRoutingIndex)
Assert-SourceContract `
    ($disabledRoutingBody -match 'if \(role == ma_eConsole &&\s*\(\(dataFlow == ma_eRender && pThis->pDevice->playback\.pID == NULL\) \|\|\s*\(dataFlow == ma_eCapture && pThis->pDevice->capture\.pID == NULL\)\)\)\s*\{\s*ma_device__on_notification_rerouted\(pThis->pDevice\);\s*\}') `
    'disabled routing must notify only for the eConsole role of a default-bound device'
Assert-SourceContract `
    ($disabledRoutingBody -notmatch 'ma_device_(?:stop|start|reroute__wasapi|reinit)\s*\(') `
    'disabled routing must not stop, start, or mutate the WASAPI device'

$deviceStateCallback = [regex]::Match(
    $miniaudioSource,
    '(?s)static HRESULT STDMETHODCALLTYPE ma_IMMNotificationClient_OnDeviceStateChanged\(.*?\)\s*\{(?<body>.*?)\r?\n\}\s*\r?\nstatic HRESULT STDMETHODCALLTYPE ma_IMMNotificationClient_OnDeviceAdded')
Assert-SourceContract $deviceStateCallback.Success `
    'WASAPI device-state callback is missing'
$deviceStateBody = $deviceStateCallback.Groups['body'].Value
$ownerStateCommentIndex = $deviceStateBody.IndexOf(
    'When automatic routing is disabled, report loss of the endpoint selected as',
    [StringComparison]::Ordinal)
$legacyStateCommentIndex = $deviceStateBody.IndexOf(
    'There have been reports of a hang when a playback device is disconnected.',
    [StringComparison]::Ordinal)
Assert-SourceContract `
    ($ownerStateCommentIndex -ge 0 -and
     $legacyStateCommentIndex -gt $ownerStateCommentIndex) `
    'owner-only inactive-device notification must precede legacy auto routing'
$ownerStateBody = $deviceStateBody.Substring(
    $ownerStateCommentIndex,
    $legacyStateCommentIndex - $ownerStateCommentIndex)
Assert-SourceContract `
    ($ownerStateBody -match 'pDeviceID != NULL' -and
     $ownerStateBody -match '\(dwNewState & MA_MM_DEVICE_STATE_ACTIVE\) == 0' -and
     $ownerStateBody -match 'type == ma_device_type_playback \|\|' -and
     $ownerStateBody -match 'type == ma_device_type_capture \|\|' -and
     ([regex]::Matches(
        $ownerStateBody,
        'type == ma_device_type_duplex').Count -eq 2) -and
     $ownerStateBody -match 'type == ma_device_type_loopback' -and
     $ownerStateBody -match 'playback\.pID == NULL' -and
     $ownerStateBody -match 'capture\.pID == NULL' -and
     $ownerStateBody -match 'ma_strcmp_WCHAR\(pThis->pDevice->playback\.id\.wasapi, pDeviceID\) == 0' -and
     $ownerStateBody -match 'ma_strcmp_WCHAR\(pThis->pDevice->capture\.id\.wasapi, pDeviceID\) == 0' -and
     $ownerStateBody -match 'ma_device__on_notification_rerouted\(pThis->pDevice\);\s*return S_OK;') `
    'inactive default endpoint must signal owner recovery and return'
Assert-SourceContract `
    ($ownerStateBody -notmatch 'ma_device_(?:stop|start|reroute__wasapi|reinit)\s*\(') `
    'owner-only inactive-device notification must not mutate the WASAPI device'

$cf7Notification = [regex]::Match(
    $bridgeSource,
    '(?s)static void cf7_device_notification\(.*?\)\s*\{(?<body>.*?)\r?\n\}\s*\r?\nstatic void cf7_bgm_uninit_sounds')
Assert-SourceContract $cf7Notification.Success `
    'CF7 device notification callback is missing'
$cf7NotificationBody = $cf7Notification.Groups['body'].Value
Assert-SourceContract `
    ($cf7NotificationBody -match 'notificationArmed' -and
     $cf7NotificationBody -match 'InterlockedExchange\(&g_control\.recoveryRequested, 1\);' -and
     $cf7NotificationBody -match 'SetEvent\(g_control\.queueEvent\);') `
    'CF7 callback must remain an armed atomic recovery signal'
Assert-SourceContract `
    ($cf7NotificationBody -notmatch 'ma_(?:engine|device|sound)_[A-Za-z0-9_]+\s*\(' -and
     $cf7NotificationBody -notmatch 'cf7_(?:graph_uninit|real_graph_initialize)') `
    'CF7 callback must not mutate the audio graph'

$ownerRecovery = [regex]::Match(
    $bridgeSource,
    '(?s)static void cf7_mark_device_recovery_requested\(void\)\s*\{(?<body>.*?)\r?\n\}\s*\r?\nstatic int cf7_probe_vfs_cancelled')
Assert-SourceContract $ownerRecovery.Success `
    'owner recovery marker is missing'
$ownerRecoveryBody = $ownerRecovery.Groups['body'].Value
Assert-SourceContract `
    ($ownerRecoveryBody -match 'audioStatus != CF7_AUDIO_BRIDGE_V2_AUDIO_READY' -and
     $ownerRecoveryBody -match 'InterlockedExchange\(&g_control\.notificationArmed, 0\);' -and
     $ownerRecoveryBody -match 'CF7_AUDIO_BRIDGE_V2_AUDIO_RECOVERING' -and
     $ownerRecoveryBody -match 'InterlockedExchange\(&g_control\.recoveryRequested, 0\);') `
    'owner recovery must remain idempotent and disarm before RECOVERING'

Write-Host '[PASS] Audio device recovery source contract.' -ForegroundColor Green

& $environmentCheck -ProjectRoot $projectRoot -Mode Validate

foreach ($requiredName in @(
    'CF7_VCVARS64',
    'CF7_MSVC_TOOLS_VERSION',
    'CF7_WINDOWS_SDK_VERSION',
    'CF7_CL_EXE'
)) {
    $requiredValue = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
    if ([string]::IsNullOrWhiteSpace($requiredValue)) {
        throw "Pinned compiler environment is unavailable: $requiredName"
    }
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$buildLeaf = 'cf7-audio-bridge-v2-contract-' + [Guid]::NewGuid().ToString('N')
$buildDirectory = [IO.Path]::GetFullPath((Join-Path $temporaryParent $buildLeaf)).TrimEnd('\')
if (-not $buildDirectory.StartsWith($temporaryParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($buildDirectory) -cne $buildLeaf) {
    throw "Refusing unsafe contract build directory: $buildDirectory"
}

New-Item -ItemType Directory -Path $buildDirectory | Out-Null
$objectPath = Join-Path $buildDirectory 'audio_bridge_v2_contract.obj'
$miniaudioObjectPath = Join-Path $buildDirectory 'miniaudio.obj'
$executablePath = Join-Path $buildDirectory 'audio_bridge_v2_contract.exe'

try {
    $compileParts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:CF7_VSWHERE_DIR)) {
        $compileParts += 'set "PATH=%CF7_VSWHERE_DIR%;%PATH%"'
    }
    $compileParts += @(
        ('call "{0}" {1} -vcvars_ver={2} >nul' -f
            $env:CF7_VCVARS64,
            $env:CF7_WINDOWS_SDK_VERSION,
            $env:CF7_MSVC_TOOLS_VERSION),
        ('call "{0}" >nul' -f $pinnedToolAssertion),
        ('"{0}" /nologo /c /TC /std:c17 /utf-8 /W2 /D_CRT_SECURE_NO_WARNINGS /I"{1}" /FI"{1}\audio_miniaudio_config.h" "{1}\miniaudio.c" /Fo"{2}"' -f
            $env:CF7_CL_EXE,
            $nativeDirectory,
            $miniaudioObjectPath),
        ('"{0}" /nologo /c /TC /std:c17 /utf-8 /W4 /WX /D_CRT_SECURE_NO_WARNINGS /I"{1}" /FI"{1}\audio_miniaudio_config.h" "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE,
            $nativeDirectory,
            $sourcePath,
            $objectPath),
        ('link.exe /nologo "{0}" "{1}" ole32.lib /OUT:"{2}"' -f
            $miniaudioObjectPath,
            $objectPath,
            $executablePath)
    )
    $compileCommand = $compileParts -join ' && '

    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $compileOutput = @(& $env:ComSpec /d /s /c $compileCommand 2>&1)
        $compileExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($compileExitCode -ne 0) {
        $compileOutput | ForEach-Object { Write-Host $_ }
        throw "Audio ABI contract compilation failed with exit code $compileExitCode"
    }
    $compileOutput | ForEach-Object { Write-Host $_ }

    $testOutput = @(& $executablePath 2>&1)
    $testExitCode = $LASTEXITCODE
    $testOutput | ForEach-Object { Write-Host $_ }
    if ($testExitCode -ne 0) {
        throw "Audio ABI contract failed with exit code $testExitCode"
    }

    Write-Host '[PASS] Repeatable local Audio ABI v2 contract runner completed.' -ForegroundColor Green
} finally {
    if ($KeepBuildDirectory) {
        Write-Host "[INFO] Contract build directory retained: $buildDirectory"
    } elseif (Test-Path -LiteralPath $buildDirectory -PathType Container) {
        $resolvedBuildDirectory = [IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $buildDirectory).Path).TrimEnd('\')
        if (-not $resolvedBuildDirectory.StartsWith($temporaryParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetFileName($resolvedBuildDirectory) -cne $buildLeaf) {
            throw "Refusing unsafe contract cleanup target: $resolvedBuildDirectory"
        }
        Remove-Item -LiteralPath $resolvedBuildDirectory -Recurse -Force
    }
}
