[CmdletBinding()]
param(
    [string]$ProfilePath = $env:H3_PIPELINE_PROFILE,
    [string]$SshHost,
    [string]$RemoteRoot,
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [int]$PollSeconds = 45,
    [int]$TimeoutMinutes = 720
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

function Resolve-InputFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
}

if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
    $resolvedProfilePath = Resolve-InputFile -Path $ProfilePath
    $profile = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedProfilePath | ConvertFrom-Json
    if ($profile.schemaVersion -ne 1 -or $profile.profileKind -ne 'workspace-private-no-credentials') {
        throw "Unsupported local profile contract: $resolvedProfilePath"
    }
    if ($profile.containsCredentials -ne $false) {
        throw 'Local profile must explicitly declare containsCredentials=false.'
    }
    if ([string]::IsNullOrWhiteSpace($SshHost)) { $SshHost = [string]$profile.sshHost }
    if ([string]::IsNullOrWhiteSpace($RemoteRoot)) { $RemoteRoot = [string]$profile.remoteRoot }
}

if ($SshHost -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') {
    throw 'SshHost must be a configured alias or safe host token.'
}
if ($RemoteRoot -notmatch '^/[A-Za-z0-9._/-]+$') {
    throw 'RemoteRoot must be an absolute remote path without spaces or shell metacharacters.'
}
if ($PollSeconds -lt 10) { throw 'PollSeconds must be at least 10.' }
if ($TimeoutMinutes -lt 1) { throw 'TimeoutMinutes must be at least 1.' }

$sourceManifestPath = Resolve-InputFile -Path $ManifestPath
$sourceManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceManifestPath | ConvertFrom-Json
$tokenPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$'
foreach ($field in @('runId', 'remoteLeaf', 'controllerLogPrefix', 'reviewStem')) {
    if ([string]$sourceManifest.$field -notmatch $tokenPattern) {
        throw "Manifest field $field is not a safe token."
    }
}

$jobs = @($sourceManifest.jobs | Sort-Object order)
if ($jobs.Count -lt 1 -or $jobs.Count -gt 6) {
    throw 'Manifest must contain 1 to 6 jobs.'
}
for ($index = 0; $index -lt $jobs.Count; $index++) {
    $job = $jobs[$index]
    if ([int]$job.order -ne ($index + 1) -or [string]$job.slug -notmatch $tokenPattern) {
        throw "Invalid job order or slug at index $index."
    }
    if ([string]$job.reviewLabel -match "[:'\\%\[\];,\t\r\n]") {
        throw "Unsafe reviewLabel characters for $($job.slug)."
    }
}

$rawProfile = $sourceManifest.rawProfile
$expectedWidth = [int]$rawProfile.width
$expectedHeight = [int]$rawProfile.height
$expectedFrames = [int]$rawProfile.frames
$expectedFpsRate = [string]$rawProfile.fpsRate
if ($expectedWidth -lt 1 -or $expectedHeight -lt 1 -or $expectedFrames -lt 1 -or $expectedFpsRate -notmatch '^\d+/\d+$') {
    throw 'Invalid rawProfile contract.'
}

$targetEnabled = [bool]$sourceManifest.targetProfile.enabled
if ($targetEnabled) {
    if ([string]$sourceManifest.targetProfile.kind -ne 'center-crop-1280x736-to-1024x576') {
        throw 'Unsupported targetProfile.kind.'
    }
    if ($expectedWidth -ne 1280 -or $expectedHeight -ne 736 -or $expectedFpsRate -ne '24/1') {
        throw 'The built-in target profile requires 1280x736 at 24/1 fps.'
    }
}

if ([IO.Path]::IsPathRooted($OutputRoot)) {
    $outputRootPath = [IO.Path]::GetFullPath($OutputRoot)
} else {
    $outputRootPath = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputRoot))
}

$runId = [string]$sourceManifest.runId
$remoteLeaf = [string]$sourceManifest.remoteLeaf
$remoteStateRoot = "$RemoteRoot/state/$runId"
$remoteLogRoot = "$RemoteRoot/logs/$remoteLeaf"
$remoteOutputRoot = "$RemoteRoot/output/$remoteLeaf"
$remotePipelineRoot = "$RemoteRoot/pipelines/$remoteLeaf"

$rawRoot = Join-Path $outputRootPath 'raw'
$targetRoot = Join-Path $outputRootPath 'target-1024x576'
$reviewRoot = Join-Path $outputRootPath 'reviews'
$contactRoot = Join-Path $reviewRoot 'contacts'
$stillRoot = Join-Path $reviewRoot 'stills'
$logRoot = Join-Path $outputRootPath 'logs'
$localStatus = Join-Path $outputRootPath 'collector-status.txt'

$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$scp = (Get-Command scp.exe -ErrorAction Stop).Source
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
$script:deadline = (Get-Date).AddMinutes($TimeoutMinutes)

function Set-CollectorStatus {
    param([Parameter(Mandatory = $true)][string]$Status)
    "$(Get-Date -Format o)`t$Status" | Set-Content -LiteralPath $localStatus -Encoding UTF8
}

function Invoke-RemoteUntilSuccess {
    param([Parameter(Mandatory = $true)][string]$Command)

    $attempt = 0
    while ((Get-Date) -lt $script:deadline) {
        $attempt++
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $result = @(& $ssh -o BatchMode=yes -o ConnectTimeout=12 $SshHost $Command 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($exitCode -eq 0) { return $result }
        $detail = ($result | ForEach-Object { [string]$_ }) -join ' | '
        Write-Host "$(Get-Date -Format o) ssh_retry attempt=$attempt exit_code=$exitCode detail=$detail"
        Set-CollectorStatus -Status "ssh_retry:$attempt"
        Start-Sleep -Seconds ([Math]::Max(10, [Math]::Min($PollSeconds, 60)))
    }
    throw 'SSH remained unavailable until the collector deadline.'
}

function Copy-RemoteUntilSuccess {
    param(
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $attempt = 0
    while ((Get-Date) -lt $script:deadline) {
        $attempt++
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $result = @(& $scp -q -o BatchMode=yes -o ConnectTimeout=12 "${SshHost}:$RemotePath" $LocalPath 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($exitCode -eq 0) { return }
        $detail = ($result | ForEach-Object { [string]$_ }) -join ' | '
        Write-Host "$(Get-Date -Format o) scp_retry attempt=$attempt exit_code=$exitCode path=$RemotePath detail=$detail"
        Set-CollectorStatus -Status "scp_retry:$attempt"
        Start-Sleep -Seconds ([Math]::Max(10, [Math]::Min($PollSeconds, 60)))
    }
    throw "SCP remained unavailable until the collector deadline: $RemotePath"
}

function Test-RemoteFile {
    param([Parameter(Mandatory = $true)][string]$RemotePath)
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $null = & $ssh -o BatchMode=yes -o ConnectTimeout=12 $SshHost "test -f '$RemotePath'" 2>&1
        return $LASTEXITCODE -eq 0
    } finally {
        $ErrorActionPreference = $savedPreference
    }
}

function Copy-OptionalRemoteFile {
    param(
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )
    if (Test-RemoteFile -RemotePath $RemotePath) {
        Copy-RemoteUntilSuccess -RemotePath $RemotePath -LocalPath $LocalPath
    }
}

function Get-RemoteSha256 {
    param([Parameter(Mandatory = $true)][string]$RemotePath)
    $lines = @(Invoke-RemoteUntilSuccess -Command "shasum -a 256 '$RemotePath'")
    $line = [string]$lines[-1]
    $digest = (($line -split '\s+')[0]).ToUpperInvariant()
    if ($digest -notmatch '^[0-9A-F]{64}$') {
        throw "Could not parse remote SHA-256 for ${RemotePath}: $line"
    }
    return $digest
}

function Get-VideoInfo {
    param([Parameter(Mandatory = $true)][string]$Path)
    $probe = & $ffprobe -v error -select_streams v:0 -count_frames `
        -show_entries stream=width,height,r_frame_rate,nb_frames,nb_read_frames `
        -show_entries format=duration,bit_rate -of json $Path | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $probe.streams) { throw "ffprobe failed: $Path" }
    $stream = $probe.streams[0]
    $frameText = if ($stream.nb_frames -and $stream.nb_frames -ne 'N/A') {
        [string]$stream.nb_frames
    } else {
        [string]$stream.nb_read_frames
    }
    return [ordered]@{
        width = [int]$stream.width
        height = [int]$stream.height
        fps = [string]$stream.r_frame_rate
        frames = [int]$frameText
        durationSeconds = [double]$probe.format.duration
        bitRate = [long]$probe.format.bit_rate
    }
}

function Assert-FullDecode {
    param([Parameter(Mandatory = $true)][string]$Path)
    & $ffmpeg -v error -i $Path -f null -
    if ($LASTEXITCODE -ne 0) { throw "Full decode failed: $Path" }
}

$directories = @($outputRootPath, $rawRoot, $reviewRoot, $contactRoot, $stillRoot, $logRoot)
if ($targetEnabled) { $directories += $targetRoot }
New-Item -ItemType Directory -Force -Path $directories | Out-Null
Set-CollectorStatus -Status 'waiting_for_remote'

while ((Get-Date) -lt $script:deadline) {
    $statusLines = @(Invoke-RemoteUntilSuccess -Command "cat '$remoteStateRoot/status.txt' 2>/dev/null || printf 'missing\n'")
    $status = ([string]$statusLines[-1]).Trim()
    Write-Host "$(Get-Date -Format o) remote_status=$status"
    Set-CollectorStatus -Status "remote:$status"
    if ($status -eq 'complete') { break }
    if ($status -eq 'failed') {
        $tail = Invoke-RemoteUntilSuccess -Command "tail -n 80 '$remoteStateRoot/progress.tsv' 2>/dev/null || true"
        $tail | ForEach-Object { Write-Host ([string]$_) }
        throw 'Remote H3 batch failed.'
    }
    Start-Sleep -Seconds $PollSeconds
}
if ((Get-Date) -ge $script:deadline) { throw 'Timed out waiting for the remote H3 batch.' }

Set-CollectorStatus -Status 'downloading'
Copy-RemoteUntilSuccess -RemotePath "$remoteStateRoot/progress.tsv" -LocalPath (Join-Path $outputRootPath 'progress.tsv')
Copy-OptionalRemoteFile -RemotePath "$remoteStateRoot/preflight-checksums.log" -LocalPath (Join-Path $logRoot 'preflight-checksums.log')
$controllerPrefix = [string]$sourceManifest.controllerLogPrefix
Copy-OptionalRemoteFile -RemotePath "$remoteLogRoot/$controllerPrefix.stdout.log" -LocalPath (Join-Path $logRoot "$controllerPrefix.stdout.log")
Copy-OptionalRemoteFile -RemotePath "$remoteLogRoot/$controllerPrefix.stderr.log" -LocalPath (Join-Path $logRoot "$controllerPrefix.stderr.log")
Copy-OptionalRemoteFile -RemotePath "$remotePipelineRoot/manifest.json" -LocalPath (Join-Path $outputRootPath 'remote-source-manifest.json')

$rawResults = @()
$targetResults = @()
$reviewItems = @()
$stillResults = @()
foreach ($job in $jobs) {
    $slug = [string]$job.slug
    $remoteVideo = "$remoteOutputRoot/$slug.mp4"
    $localVideo = Join-Path $rawRoot "$slug.mp4"
    $remoteDigest = Get-RemoteSha256 -RemotePath $remoteVideo
    $needsDownload = $true
    if (Test-Path -LiteralPath $localVideo -PathType Leaf) {
        $needsDownload = (Get-FileHash -Algorithm SHA256 -LiteralPath $localVideo).Hash -ne $remoteDigest
    }
    if ($needsDownload) { Copy-RemoteUntilSuccess -RemotePath $remoteVideo -LocalPath $localVideo }
    Copy-OptionalRemoteFile -RemotePath "$remoteLogRoot/$slug.log" -LocalPath (Join-Path $logRoot "$slug.log")
    Copy-OptionalRemoteFile -RemotePath "$remoteLogRoot/$slug.memory.tsv" -LocalPath (Join-Path $logRoot "$slug.memory.tsv")

    $localDigest = (Get-FileHash -Algorithm SHA256 -LiteralPath $localVideo).Hash
    if ($localDigest -ne $remoteDigest) { throw "Downloaded hash mismatch for $slug" }
    $info = Get-VideoInfo -Path $localVideo
    if ($info.width -ne $expectedWidth -or $info.height -ne $expectedHeight -or
        $info.frames -ne $expectedFrames -or $info.fps -ne $expectedFpsRate) {
        throw "Unexpected raw video contract for $slug"
    }
    Assert-FullDecode -Path $localVideo
    $rawResults += [ordered]@{
        order = [int]$job.order
        slug = $slug
        seed = [int]$job.seed
        path = $localVideo
        sha256 = $localDigest
        video = $info
    }

    $reviewPath = $localVideo
    if ($targetEnabled) {
        $target = Join-Path $targetRoot "$slug-center-crop720-single-bicubic-downsample.mp4"
        & $ffmpeg -hide_banner -loglevel error -y -i $localVideo `
            -map 0:v:0 -map '0:a?' `
            -vf 'crop=1280:720:0:8,scale=1024:576:flags=bicubic+accurate_rnd+full_chroma_int,setsar=1' `
            -r 24 -frames:v $expectedFrames -t ($expectedFrames / 24.0) `
            -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p `
            -c:a aac -b:a 192k -movflags +faststart $target
        if ($LASTEXITCODE -ne 0) { throw "Target derivative failed for $slug" }
        $targetInfo = Get-VideoInfo -Path $target
        if ($targetInfo.width -ne 1024 -or $targetInfo.height -ne 576 -or
            $targetInfo.frames -ne $expectedFrames -or $targetInfo.fps -ne '24/1') {
            throw "Unexpected target derivative for $slug"
        }
        Assert-FullDecode -Path $target
        $targetResults += [ordered]@{
            order = [int]$job.order
            slug = $slug
            seed = [int]$job.seed
            path = $target
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
            video = $targetInfo
        }
        $reviewPath = $target
    }

    $reviewItems += [ordered]@{
        order = [int]$job.order
        seed = [int]$job.seed
        slug = $slug
        label = [string]$job.reviewLabel
        path = $reviewPath
    }

    $stableFrame = [Math]::Max(0, $expectedFrames - 6)
    $still = Join-Path $stillRoot "$slug-frame-$stableFrame.png"
    & $ffmpeg -hide_banner -loglevel error -y -i $reviewPath `
        -vf "select='eq(n,$stableFrame)'" -vsync 0 -frames:v 1 $still
    if ($LASTEXITCODE -ne 0) { throw "Stable-frame extraction failed for $slug" }
    $stillResults += [ordered]@{
        order = [int]$job.order
        seed = [int]$job.seed
        frame = $stableFrame
        path = $still
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $still).Hash
    }
}

$fontPath = Join-Path $env:WINDIR 'Fonts/msyh.ttc'
if (-not (Test-Path -LiteralPath $fontPath -PathType Leaf)) {
    $fontPath = Join-Path $env:WINDIR 'Fonts/arial.ttf'
}
if (-not (Test-Path -LiteralPath $fontPath -PathType Leaf)) {
    $fontPath = Join-Path $env:WINDIR 'Fonts/consola.ttf'
}
$filterFont = $fontPath.Replace('\', '/').Replace(':', '\:')

$comparisonArgs = @('-hide_banner', '-loglevel', 'error', '-y')
$comparisonFilters = @()
foreach ($item in $reviewItems) { $comparisonArgs += @('-i', [string]$item.path) }
if ($reviewItems.Count -le 2) {
    $comparisonWidth = 1024 * $reviewItems.Count
    $comparison = Join-Path $reviewRoot "$($sourceManifest.reviewStem)-comparison-${comparisonWidth}x576.mp4"
    for ($index = 0; $index -lt $reviewItems.Count; $index++) {
        $label = [string]$reviewItems[$index].label
        $comparisonFilters += "[$($index):v:0]setpts=PTS-STARTPTS,scale=1024:576:force_original_aspect_ratio=decrease:flags=bicubic,pad=1024:576:(ow-iw)/2:(oh-ih)/2:black,drawtext=fontfile='$filterFont':text='$label':x=18:y=18:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=9[c$index]"
    }
    $comparisonInputs = (0..($reviewItems.Count - 1) | ForEach-Object { "[c$_]" }) -join ''
    if ($reviewItems.Count -eq 1) {
        $comparisonFilters += '[c0]null[outv]'
    } else {
        $comparisonFilters += "${comparisonInputs}hstack=inputs=$($reviewItems.Count)[outv]"
    }
} else {
    $comparison = Join-Path $reviewRoot "$($sourceManifest.reviewStem)-comparison-grid-1536x576.mp4"
    for ($index = 0; $index -lt $reviewItems.Count; $index++) {
        $label = [string]$reviewItems[$index].label
        $comparisonFilters += "[$($index):v:0]setpts=PTS-STARTPTS,scale=512:288:force_original_aspect_ratio=decrease:flags=bicubic,pad=512:288:(ow-iw)/2:(oh-ih)/2:black,drawtext=fontfile='$filterFont':text='$label':x=12:y=12:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=6[c$index]"
    }
    $positions = @('0_0', '512_0', '1024_0', '0_288', '512_288', '1024_288')
    $comparisonInputs = (0..($reviewItems.Count - 1) | ForEach-Object { "[c$_]" }) -join ''
    $layout = ($positions[0..($reviewItems.Count - 1)]) -join '|'
    $comparisonFilters += "${comparisonInputs}xstack=inputs=$($reviewItems.Count):layout=${layout}:fill=black[outv]"
}
$comparisonArgs += @(
    '-filter_complex', ($comparisonFilters -join ';'), '-map', '[outv]', '-an',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '12', '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart', $comparison
)
& $ffmpeg @comparisonArgs
if ($LASTEXITCODE -ne 0) { throw 'Comparison review failed.' }
Assert-FullDecode -Path $comparison

$sequential = Join-Path $reviewRoot "$($sourceManifest.reviewStem)-sequential-1024x576.mp4"
$sequenceArgs = @('-hide_banner', '-loglevel', 'error', '-y')
$sequenceFilters = @()
for ($index = 0; $index -lt $reviewItems.Count; $index++) {
    $sequenceArgs += @('-i', [string]$reviewItems[$index].path)
    $label = [string]$reviewItems[$index].label
    $sequenceFilters += "[$($index):v:0]setpts=PTS-STARTPTS,scale=1024:576:force_original_aspect_ratio=decrease:flags=bicubic,pad=1024:576:(ow-iw)/2:(oh-ih)/2:black,drawtext=fontfile='$filterFont':text='$label':x=18:y=18:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=9[v$index]"
}
$sequenceInputs = (0..($reviewItems.Count - 1) | ForEach-Object { "[v$_]" }) -join ''
$sequenceFilters += "${sequenceInputs}concat=n=$($reviewItems.Count):v=1:a=0[outv]"
$sequenceArgs += @(
    '-filter_complex', ($sequenceFilters -join ';'), '-map', '[outv]', '-an',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '12', '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart', $sequential
)
& $ffmpeg @sequenceArgs
if ($LASTEXITCODE -ne 0) { throw 'Sequential review failed.' }
Assert-FullDecode -Path $sequential

$contactFrames = @(0, [Math]::Floor($expectedFrames * 0.25), [Math]::Floor($expectedFrames * 0.55), $expectedFrames - 1)
$contactSelector = ($contactFrames | ForEach-Object { "eq(n,$_)" }) -join '+'
$contactResults = @()
foreach ($item in $reviewItems) {
    $contact = Join-Path $contactRoot "$($item.slug)-four-moments.png"
    $label = [string]$item.label
    $filter = "select='$contactSelector',scale=384:216:force_original_aspect_ratio=decrease:flags=bicubic,pad=384:216:(ow-iw)/2:(oh-ih)/2:black,drawtext=fontfile='$filterFont':text='$label':x=12:y=12:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=6,tile=4x1:padding=4:color=black"
    & $ffmpeg -hide_banner -loglevel error -y -i $item.path -vf $filter -frames:v 1 $contact
    if ($LASTEXITCODE -ne 0) { throw "Contact sheet failed for $($item.slug)" }
    $contactResults += [ordered]@{
        order = [int]$item.order
        seed = [int]$item.seed
        frames = $contactFrames
        path = $contact
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $contact).Hash
    }
}

$resultManifest = [ordered]@{
    schemaVersion = 1
    runId = $runId
    completedAt = (Get-Date).ToString('o')
    sourceManifest = [ordered]@{
        path = $sourceManifestPath
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash
    }
    rawOutputs = $rawResults
    targetSizeOutputs = $targetResults
    derivationPolicy = if ($targetEnabled) {
        [ordered]@{
            target = '1024x576'
            operation = 'Center crop 1280x736 to 1280x720, then one bicubic downsample.'
            sharpening = $false
            generativeRestoration = $false
        }
    } else {
        [ordered]@{ enabled = $false }
    }
    reviews = [ordered]@{
        comparison = [ordered]@{
            path = $comparison
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $comparison).Hash
        }
        sequential = [ordered]@{
            path = $sequential
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sequential).Hash
        }
        stableFrames = $stillResults
        contacts = $contactResults
    }
}
$resultManifestPath = Join-Path $outputRootPath 'manifest.json'
$resultManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultManifestPath -Encoding UTF8

Set-CollectorStatus -Status 'complete'
Write-Output "MANIFEST=$resultManifestPath"
Write-Output "COMPARISON=$comparison"
Write-Output "SEQUENTIAL=$sequential"
