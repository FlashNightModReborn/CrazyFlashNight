[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$')]
    [string]$SourceCommitOid,
    [string]$ProjectRoot,
    [string]$OutputRoot,
    [string]$ConfigPath,
    [string]$GitHubCliPath = 'gh',
    [ValidateRange(0,9223372036854775807)][Int64]$ResumeRunId = 0,
    [string]$PreDownloadedArtifactArchive,
    [switch]$IncludeCandidateArchive,
    [ValidateRange(1,8)][int]$ArtifactDownloadAttempts = 4,
    [ValidateRange(30,7200)][int]$ArtifactDownloadTimeoutSeconds = 1800,
    [ValidateSet('','auto','proxy','direct')][string]$GitHubArtifactTransport = '',
    [ValidateRange(5,300)][int]$ArtifactConnectTimeoutSeconds = 15,
    [ValidateRange(5,600)][int]$ArtifactStallTimeoutSeconds = 30,
    [ValidateRange(1,600)][int]$DiscoveryTimeoutSeconds = 120,
    [ValidateRange(30,86400)][int]$RunTimeoutSeconds = 21600,
    [ValidateRange(1,300)][int]$PollSeconds = 10,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')
$SourceCommitOid = $SourceCommitOid.ToLowerInvariant()
if (-not $ConfigPath) { $ConfigPath = Join-Path $ProjectRoot 'config\build\runtime-github-builder.v2.json' }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

function Read-Cf7CloudBuilderConfig {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config -or [string]$config.schema -ne 'cf7-runtime-github-builder.v2') {
        throw 'Unsupported GitHub runtime builder config schema.'
    }
    if ($config.enabled -isnot [bool] -or -not [bool]$config.enabled) { throw 'GitHub runtime builder is disabled.' }
    if ([string]$config.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub runtime repository.' }
    if ([string]$config.signerWorkflow -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$') {
        throw 'Invalid GitHub runtime signer workflow.'
    }
    if ([string]$config.sourceRef -cnotmatch '^refs/tags/runtime-build-v2/[a-z0-9][a-z0-9._-]{1,80}$') {
        throw 'GitHub runtime sourceRef must be one canonical protected runtime-build-v2 tag.'
    }
    if ([string]$config.identityProvider -ne 'github-oidc-sigstore' -or
            $config.longLivedPrivateKey -isnot [bool] -or [bool]$config.longLivedPrivateKey) {
        throw 'GitHub runtime builder must use keyless OIDC/Sigstore identity.'
    }
    return $config
}

function Resolve-Cf7GitHubCli {
    if ([IO.Path]::IsPathRooted($GitHubCliPath) -or $GitHubCliPath.Contains('\') -or $GitHubCliPath.Contains('/')) {
        if (-not (Test-Path -LiteralPath $GitHubCliPath -PathType Leaf)) { throw "GitHub CLI is missing: $GitHubCliPath" }
        return (Resolve-Path -LiteralPath $GitHubCliPath).Path
    }
    $command = Get-Command $GitHubCliPath -ErrorAction SilentlyContinue
    if (-not $command -and $GitHubCliPath -eq 'gh') {
        $fallbacks = @(
            (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe')
        )
        $fallback = $fallbacks | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        if ($fallback) { return (Resolve-Path -LiteralPath $fallback).Path }
    }
    if (-not $command) { throw "GitHub CLI is unavailable: $GitHubCliPath" }
    return $command.Source
}

function Invoke-Cf7GitText([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $ProjectRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return ($output -join "`n").Trim()
}

function Invoke-Cf7Gh([string[]]$Arguments, [switch]$AllowEmpty) {
    Write-Host "[RuntimeGitHubBuild] gh $($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' ') ..." -ForegroundColor DarkGray
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:GitHubCli @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw "GitHub CLI failed (exit=$exitCode): gh $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) { throw 'GitHub CLI returned empty output.' }
    return $text
}

function Invoke-Cf7GhJson([string[]]$Arguments) {
    $text = Invoke-Cf7Gh -Arguments $Arguments
    try { return $text | ConvertFrom-Json }
    catch { throw "GitHub CLI returned invalid JSON: $($_.Exception.Message)" }
}

function Resolve-Cf7ConfiguredSourceTagCommit($Config) {
    $sourceRef = [string]$Config.sourceRef
    $relativeRef = $sourceRef.Substring('refs/'.Length)
    $repository = [string]$Config.repository
    $refResponse = Invoke-Cf7GhJson -Arguments @(
        'api','--method','GET','-H','X-GitHub-Api-Version: 2026-03-10',
        "repos/$repository/git/ref/$relativeRef"
    )
    if ($null -eq $refResponse -or [string]$refResponse.ref -cne $sourceRef -or
            $null -eq $refResponse.PSObject.Properties['object']) {
        throw "GitHub source tag response does not bind the configured ref: expected=$sourceRef actual=$($refResponse.ref)"
    }

    $objectType = [string]$refResponse.object.type
    $objectSha = ([string]$refResponse.object.sha).ToLowerInvariant()
    $seenTagObjects = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    for ($depth = 0; $depth -lt 8; $depth++) {
        if ($objectSha -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
            throw "GitHub source tag contains an invalid object ID: $objectSha"
        }
        if ($objectType -ceq 'commit') { return $objectSha }
        if ($objectType -cne 'tag') {
            throw "GitHub source tag must peel to a commit, not $objectType."
        }
        if (-not $seenTagObjects.Add($objectSha)) { throw 'GitHub source tag peel contains a cycle.' }

        $tagResponse = Invoke-Cf7GhJson -Arguments @(
            'api','--method','GET','-H','X-GitHub-Api-Version: 2026-03-10',
            "repos/$repository/git/tags/$objectSha"
        )
        if ($null -eq $tagResponse -or ([string]$tagResponse.sha).ToLowerInvariant() -cne $objectSha -or
                $null -eq $tagResponse.PSObject.Properties['object']) {
            throw "GitHub annotated tag response does not bind tag object $objectSha."
        }
        $objectType = [string]$tagResponse.object.type
        $objectSha = ([string]$tagResponse.object.sha).ToLowerInvariant()
    }
    throw 'GitHub source tag exceeds the maximum annotated-tag peel depth.'
}

function Get-Cf7CloudRuns([string]$Repository, [string]$WorkflowFile) {
    $runs = Invoke-Cf7GhJson -Arguments @(
        'run','list','--repo',$Repository,'--workflow',$WorkflowFile,'--event','workflow_dispatch',
        '--limit','100','--json','databaseId,displayTitle,headBranch,headSha,status,conclusion,createdAt,event,url'
    )
    return @($runs)
}

function Assert-Cf7RunIdentity(
    $Run,
    [Int64]$ExpectedId,
    [string]$ExpectedTitle,
    [string]$ExpectedBranch,
    [string]$ExpectedHeadSha
) {
    if ([Int64]$Run.databaseId -ne $ExpectedId) { throw 'GitHub run databaseId changed while waiting.' }
    if ([string]$Run.displayTitle -cne $ExpectedTitle) { throw 'GitHub run title no longer identifies the requested source commit.' }
    if ([string]$Run.headBranch -cne $ExpectedBranch) { throw 'GitHub runtime run came from an unexpected workflow source branch.' }
    if ([string]$Run.headSha -cne $ExpectedHeadSha) { throw 'GitHub runtime run head SHA does not match the requested source commit.' }
    if ([string]$Run.event -ne 'workflow_dispatch') { throw 'GitHub runtime run has an unexpected event kind.' }
}

function ConvertTo-Cf7UInt32Bits([int]$Value) {
    return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$Value), 0)
}

function Get-Cf7ArtifactMetadata(
    [string]$Repository,
    [Int64]$RunId,
    [string]$ArtifactName,
    [string]$ExpectedHeadSha
) {
    $encodedName = [Uri]::EscapeDataString($ArtifactName)
    $response = Invoke-Cf7GhJson -Arguments @(
        'api','--method','GET','-H','X-GitHub-Api-Version: 2026-03-10',
        "repos/$Repository/actions/runs/$RunId/artifacts?name=$encodedName"
    )
    if ($null -eq $response -or $null -eq $response.PSObject.Properties['total_count'] -or
            $null -eq $response.PSObject.Properties['artifacts']) {
        throw 'GitHub artifact metadata response is incomplete.'
    }
    $artifacts = @($response.artifacts)
    if ([Int64]$response.total_count -ne $artifacts.Count) {
        throw 'GitHub artifact metadata response is truncated or ambiguous.'
    }
    $matches = @($artifacts | Where-Object { [string]$_.name -ceq $ArtifactName })
    if ($matches.Count -ne 1) {
        throw "Selected GitHub run must contain exactly one artifact named $ArtifactName."
    }
    $artifact = $matches[0]
    if ([Int64]$artifact.id -le 0) { throw 'GitHub artifact metadata contains an invalid artifact ID.' }
    if ([Int64]$artifact.size_in_bytes -le 0 -or [Int64]$artifact.size_in_bytes -gt 603979776) {
        throw 'GitHub artifact metadata contains an unsafe archive size.'
    }
    if ($artifact.expired -isnot [bool] -or [bool]$artifact.expired) {
        throw 'Selected GitHub artifact is expired or has an invalid expiry field.'
    }
    if ($null -eq $artifact.PSObject.Properties['workflow_run'] -or $null -eq $artifact.workflow_run -or
            [Int64]$artifact.workflow_run.id -ne $RunId -or
            ([string]$artifact.workflow_run.head_sha).ToLowerInvariant() -cne $ExpectedHeadSha) {
        throw 'GitHub artifact metadata does not bind the selected workflow run.'
    }
    if ($null -eq $artifact.PSObject.Properties['digest'] -or
            [string]$artifact.digest -cnotmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'GitHub artifact metadata must contain one SHA-256 archive digest.'
    }
    $digestSha256 = $Matches[1].ToLowerInvariant()
    $downloadUri = $null
    if (-not [Uri]::TryCreate([string]$artifact.archive_download_url, [UriKind]::Absolute, [ref]$downloadUri) -or
            $downloadUri.Scheme -cne 'https' -or
            $downloadUri.Host -cne 'api.github.com' -or
            -not $downloadUri.AbsolutePath.EndsWith("/actions/artifacts/$([Int64]$artifact.id)/zip", [StringComparison]::Ordinal)) {
        throw 'GitHub artifact metadata contains an unsafe archive download endpoint.'
    }
    return [pscustomobject][ordered]@{
        Id = [Int64]$artifact.id
        Name = [string]$artifact.name
        Size = [Int64]$artifact.size_in_bytes
        DigestSha256 = $digestSha256
        DownloadUri = $downloadUri
    }
}

function Get-Cf7GitHubToken {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:GitHubCli 'auth' 'token' '--hostname' 'github.com' 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw 'GitHub CLI could not provide an authentication token for artifact download.' }
    $token = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token.Length -lt 20 -or $token -match '\s') {
        throw 'GitHub CLI returned an invalid authentication token.'
    }
    return $token
}

function New-Cf7HttpClient([bool]$UseProxy, [bool]$AllowRedirect, [int]$TimeoutSeconds) {
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $AllowRedirect
    $handler.UseProxy = $UseProxy
    $client = New-Object Net.Http.HttpClient($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('CF7-RuntimeArtifact/2')
    return $client
}

function Resolve-Cf7ArtifactTransportMode([AllowNull()][string]$ParameterValue, [AllowNull()][string]$EnvironmentValue) {
    # The explicit parameter wins over CF7_GITHUB_ARTIFACT_TRANSPORT; both default to auto.
    $candidate = $ParameterValue
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = $EnvironmentValue }
    if ([string]::IsNullOrWhiteSpace($candidate)) { return 'auto' }
    $normalized = ([string]$candidate).Trim().ToLowerInvariant()
    if (@('auto','proxy','direct') -notcontains $normalized) {
        throw "GitHub artifact transport must be auto, proxy, or direct: $candidate"
    }
    return $normalized
}

function Get-Cf7ArtifactRouteCandidates([string]$Mode, [AllowNull()][string]$PersistedRoute, [AllowNull()][string[]]$FailedRoutes) {
    # One download round's route order. Explicit proxy/direct pins a single route for both the
    # redirect probe and the data stream. Auto tries the persisted last-known-good route first,
    # then proxy, then direct; routes that already failed in this receive are demoted to the end.
    if ($Mode -eq 'proxy' -or $Mode -eq 'direct') { return @($Mode) }
    $failed = @($FailedRoutes)
    $ordered = New-Object 'System.Collections.Generic.List[string]'
    foreach ($route in @($PersistedRoute,'proxy','direct')) {
        if ($route -ne 'proxy' -and $route -ne 'direct') { continue }
        if ($failed -contains $route) { continue }
        if ($ordered.Contains($route)) { continue }
        $ordered.Add($route)
    }
    foreach ($route in $failed) {
        if (($route -eq 'proxy' -or $route -eq 'direct') -and -not $ordered.Contains($route)) { $ordered.Add($route) }
    }
    return @($ordered)
}

function Get-Cf7ArtifactRouteCachePath([string]$QueueRoot) {
    return (Join-Path $QueueRoot 'github-artifact-route.v1.json')
}

function Read-Cf7ArtifactRouteCache([string]$QueueRoot) {
    # The sticky route is a hint, never an authority: unreadable or malformed content degrades
    # to a fresh canary probe instead of failing the download.
    $path = Get-Cf7ArtifactRouteCachePath -QueueRoot $QueueRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $record = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$record.schema -ne 'cf7-github-artifact-route.v1') { return $null }
        $route = ([string]$record.route).ToLowerInvariant()
        if ($route -ne 'proxy' -and $route -ne 'direct') { return $null }
        return $route
    } catch { return $null }
}

function Save-Cf7ArtifactRouteCache([string]$QueueRoot, [string]$Route, [string]$Source) {
    if ($Route -ne 'proxy' -and $Route -ne 'direct') { throw "Invalid GitHub artifact route for persistence: $Route" }
    $record = [pscustomobject][ordered]@{
        schema = 'cf7-github-artifact-route.v1'
        route = $Route
        source = $Source
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    Write-Cf7QueueJsonAtomic -Path (Get-Cf7ArtifactRouteCachePath -QueueRoot $QueueRoot) -Value $record
}

function Clear-Cf7ArtifactRouteCache([string]$QueueRoot) {
    $path = Get-Cf7ArtifactRouteCachePath -QueueRoot $QueueRoot
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
}

function Get-Cf7ArtifactRedirect([Uri]$DownloadUri, [string]$Token, [string[]]$RouteCandidates, [int]$TimeoutSeconds) {
    $lastFailureType = 'none'
    foreach ($route in @($RouteCandidates)) {
        $useProxy = ($route -eq 'proxy')
        $client = $null
        $request = $null
        $response = $null
        try {
            $client = New-Cf7HttpClient -UseProxy $useProxy -AllowRedirect $false -TimeoutSeconds $TimeoutSeconds
            $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, $DownloadUri)
            $request.Headers.Authorization = New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token)
            [void]$request.Headers.TryAddWithoutValidation('Accept','application/vnd.github+json')
            [void]$request.Headers.TryAddWithoutValidation('X-GitHub-Api-Version','2026-03-10')
            $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            if ($status -ne 302 -and $status -ne 307) { throw "Artifact redirect endpoint returned status $status." }
            if ($null -eq $response.Headers.Location) { throw 'Artifact redirect endpoint omitted Location.' }
            $redirect = if ($response.Headers.Location.IsAbsoluteUri) {
                $response.Headers.Location
            } else {
                New-Object Uri($DownloadUri, $response.Headers.Location)
            }
            if ($redirect.Scheme -cne 'https') { throw 'Artifact redirect target is not HTTPS.' }
            return [pscustomobject][ordered]@{ Redirect = $redirect; Route = $route }
        } catch {
            $lastFailureType = $_.Exception.GetType().FullName
        } finally {
            if ($null -ne $response) { $response.Dispose() }
            if ($null -ne $request) { $request.Dispose() }
            if ($null -ne $client) { $client.Dispose() }
        }
    }
    throw "Unable to acquire the authenticated artifact redirect (failureType=$lastFailureType)."
}

function Invoke-Cf7ArtifactStreamAttempt(
    [Uri]$BlobUri,
    [string]$PartialPath,
    [Int64]$ExpectedSize,
    [bool]$UseProxy,
    [int]$TimeoutSeconds,
    [int]$ConnectTimeoutSeconds,
    [int]$StallTimeoutSeconds
) {
    $offset = if (Test-Path -LiteralPath $PartialPath -PathType Leaf) { (Get-Item -LiteralPath $PartialPath -Force).Length } else { [Int64]0 }
    if ($offset -lt 0 -or $offset -gt $ExpectedSize) { throw 'Artifact partial length exceeds the metadata size.' }
    if ($offset -eq $ExpectedSize) { return }

    $client = $null
    $request = $null
    $response = $null
    $input = $null
    $output = $null
    $cancellation = New-Object Threading.CancellationTokenSource
    try {
        $cancellation.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
        $client = New-Cf7HttpClient -UseProxy $UseProxy -AllowRedirect $false -TimeoutSeconds $TimeoutSeconds
        $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, $BlobUri)
        if ($offset -gt 0) { $request.Headers.Range = New-Object Net.Http.Headers.RangeHeaderValue($offset, $null) }
        # Connect/first-byte phase: a short dedicated watchdog bounds the wait until response
        # headers arrive. The long overall timeout must not apply to a dead connection.
        $connectWatchdog = New-Object Threading.CancellationTokenSource
        try {
            $connectWatchdog.CancelAfter([TimeSpan]::FromSeconds($ConnectTimeoutSeconds))
            $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $connectWatchdog.Token).GetAwaiter().GetResult()
        } finally {
            $connectWatchdog.Dispose()
        }
        $status = [int]$response.StatusCode
        $contentLength = $response.Content.Headers.ContentLength
        if ($offset -eq 0) {
            if ($status -ne 200) { throw "Fresh artifact transfer returned status $status instead of 200." }
            if ($null -eq $contentLength -or [Int64]$contentLength -ne $ExpectedSize) { throw 'Fresh artifact Content-Length does not match metadata.' }
            if ($null -ne $response.Content.Headers.ContentRange) { throw 'Fresh artifact transfer unexpectedly returned Content-Range.' }
        } else {
            $range = $response.Content.Headers.ContentRange
            if ($status -ne [int][Net.HttpStatusCode]::PartialContent -or $null -eq $range -or [string]$range.Unit -cne 'bytes' -or
                    $null -eq $range.From -or [Int64]$range.From -ne $offset -or
                    $null -eq $range.To -or [Int64]$range.To -ne ($ExpectedSize - 1) -or
                    $null -eq $range.Length -or [Int64]$range.Length -ne $ExpectedSize -or
                    $null -eq $contentLength -or [Int64]$contentLength -ne ($ExpectedSize - $offset)) {
                throw 'Resumed artifact response does not strictly cover the requested remaining byte range.'
            }
        }

        $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fileMode = if (Test-Path -LiteralPath $PartialPath -PathType Leaf) { [IO.FileMode]::Append } else { [IO.FileMode]::CreateNew }
        $output = New-Object IO.FileStream($PartialPath, $fileMode, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 1048576
        [Int64]$written = 0
        [Int64]$progressInterval = 5242880
        [Int64]$nextProgress = ([Int64]([Math]::Floor($offset / [double]$progressInterval)) + 1) * $progressInterval
        # Data phase: the stall watchdog aborts the attempt when no byte arrives for
        # StallTimeoutSeconds; the overall cancellation token remains the hard ceiling.
        $stallWatchdog = New-Object Threading.CancellationTokenSource
        $readWatchdog = [Threading.CancellationTokenSource]::CreateLinkedTokenSource($cancellation.Token, $stallWatchdog.Token)
        try {
            while ($true) {
                $stallWatchdog.CancelAfter([TimeSpan]::FromSeconds($StallTimeoutSeconds))
                $read = $input.ReadAsync($buffer, 0, $buffer.Length, $readWatchdog.Token).GetAwaiter().GetResult()
                if ($read -le 0) { break }
                if ($offset + $written + $read -gt $ExpectedSize) { throw 'Artifact response exceeds the metadata size.' }
                $output.Write($buffer, 0, $read)
                $written += $read
                $received = $offset + $written
                if ($received -ge $nextProgress) {
                    Write-Host "[RuntimeGitHubBuild] Artifact bytes received=$received expected=$ExpectedSize" -ForegroundColor DarkGray
                    while ($nextProgress -le $received) { $nextProgress += $progressInterval }
                }
            }
        } finally {
            $readWatchdog.Dispose()
            $stallWatchdog.Dispose()
        }
        $output.Flush($true)
    } finally {
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $request) { $request.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
        $cancellation.Dispose()
    }
    $actual = (Get-Item -LiteralPath $PartialPath -Force).Length
    if ($actual -ne $ExpectedSize) { throw "Artifact stream ended before the metadata size (received=$actual expected=$ExpectedSize)." }
    Write-Host "[RuntimeGitHubBuild] Artifact bytes received=$actual expected=$ExpectedSize" -ForegroundColor DarkGray
}

function Copy-Cf7PreDownloadedArtifact([string]$SourcePath, [string]$DestinationPath, [Int64]$ExpectedSize) {
    $source = (Resolve-Path -LiteralPath $SourcePath).Path
    $item = Get-Item -LiteralPath $source -Force
    if (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and $item.Length -eq $ExpectedSize) {
        $input = New-Object IO.FileStream($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $output = New-Object IO.FileStream($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
        } finally { $input.Dispose() }
        return
    }
    throw 'Pre-downloaded artifact must be a non-reparse file whose length exactly matches GitHub metadata.'
}

function Assert-Cf7ArtifactArchiveIdentity([string]$ArchivePath, $Metadata) {
    $item = Get-Item -LiteralPath $ArchivePath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne [Int64]$Metadata.Size) {
        throw 'Artifact archive does not match the exact GitHub metadata size.'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Metadata.DigestSha256)) {
        $actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -cne [string]$Metadata.DigestSha256) {
            throw 'Artifact archive SHA-256 does not match GitHub metadata.'
        }
    }
}

function Receive-Cf7ArtifactArchive(
    $Metadata,
    [string]$TransportRoot,
    [string]$PreDownloadedPath,
    [int]$Attempts,
    [int]$TimeoutSeconds,
    [string]$TransportMode,
    [int]$ConnectTimeoutSeconds,
    [int]$StallTimeoutSeconds,
    [string]$QueueRoot
) {
    if (-not (Test-Path -LiteralPath $TransportRoot -PathType Container)) { New-Item -ItemType Directory -Path $TransportRoot -Force | Out-Null }
    $transportItem = Get-Item -LiteralPath $TransportRoot -Force
    if (($transportItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Artifact transport directory cannot be a reparse point.' }
    $archiveName = "artifact-$([Int64]$Metadata.Id).zip"
    $partialName = $archiveName + '.partial'
    $archivePath = Join-Path $TransportRoot $archiveName
    $partialPath = Join-Path $TransportRoot $partialName
    $unexpected = @(Get-ChildItem -LiteralPath $TransportRoot -Force | Where-Object { $_.Name -cne $archiveName -and $_.Name -cne $partialName })
    if ($unexpected.Count -gt 0) { throw 'Artifact transport directory contains unexpected state.' }
    if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
        if (Test-Path -LiteralPath $partialPath) { throw 'Artifact transport contains both complete and partial archives.' }
        $complete = Get-Item -LiteralPath $archivePath -Force
        if (($complete.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $complete.Length -ne [Int64]$Metadata.Size) {
            throw 'Cached artifact archive does not match GitHub metadata.'
        }
        Assert-Cf7ArtifactArchiveIdentity -ArchivePath $archivePath -Metadata $Metadata
        return [pscustomobject][ordered]@{ ArchivePath = $archivePath; Route = $null }
    }
    if (Test-Path -LiteralPath $partialPath -PathType Leaf) {
        $partial = Get-Item -LiteralPath $partialPath -Force
        if (($partial.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $partial.Length -gt [Int64]$Metadata.Size) {
            throw 'Artifact partial is unsafe or larger than GitHub metadata.'
        }
    }

    if ($PreDownloadedPath) {
        if (Test-Path -LiteralPath $partialPath) { throw 'Cannot combine a pre-downloaded archive with an existing partial transfer.' }
        Copy-Cf7PreDownloadedArtifact -SourcePath $PreDownloadedPath -DestinationPath $partialPath -ExpectedSize ([Int64]$Metadata.Size)
        Assert-Cf7ArtifactArchiveIdentity -ArchivePath $partialPath -Metadata $Metadata
        [IO.File]::Move($partialPath, $archivePath)
        return [pscustomobject][ordered]@{ ArchivePath = $archivePath; Route = $null }
    }

    $token = Get-Cf7GitHubToken
    $effectiveRoute = $null
    try {
        $failedRoutes = @()
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            $route = $null
            try {
                $offset = if (Test-Path -LiteralPath $partialPath -PathType Leaf) { (Get-Item -LiteralPath $partialPath -Force).Length } else { [Int64]0 }
                # The redirect probe and the data stream always share one route. In auto mode
                # the small redirect request doubles as the canary: the persisted
                # last-known-good route goes first, and the winning route is pinned for the
                # data stream and persisted again.
                if ($TransportMode -eq 'auto') {
                    $persistedRoute = Read-Cf7ArtifactRouteCache -QueueRoot $QueueRoot
                    $candidates = Get-Cf7ArtifactRouteCandidates -Mode 'auto' -PersistedRoute $persistedRoute -FailedRoutes $failedRoutes
                    $probe = Get-Cf7ArtifactRedirect -DownloadUri $Metadata.DownloadUri -Token $token -RouteCandidates $candidates -TimeoutSeconds $ConnectTimeoutSeconds
                    $route = [string]$probe.Route
                    $redirect = $probe.Redirect
                    $routeSource = 'canary'
                    if ($persistedRoute -eq $route) { $routeSource = 'sticky' }
                    try { Save-Cf7ArtifactRouteCache -QueueRoot $QueueRoot -Route $route -Source $routeSource }
                    catch { Write-Warning "Could not persist the GitHub artifact route cache: $($_.Exception.Message)" }
                } else {
                    $route = $TransportMode
                    $probe = Get-Cf7ArtifactRedirect -DownloadUri $Metadata.DownloadUri -Token $token -RouteCandidates @($route) -TimeoutSeconds $ConnectTimeoutSeconds
                    $redirect = $probe.Redirect
                }
                Write-Host "[RuntimeGitHubBuild] Artifact transfer attempt=$attempt/$Attempts offset=$offset route=$route mode=$TransportMode" -ForegroundColor DarkGray
                Invoke-Cf7ArtifactStreamAttempt -BlobUri $redirect -PartialPath $partialPath `
                    -ExpectedSize ([Int64]$Metadata.Size) -UseProxy ($route -eq 'proxy') -TimeoutSeconds $TimeoutSeconds `
                    -ConnectTimeoutSeconds $ConnectTimeoutSeconds -StallTimeoutSeconds $StallTimeoutSeconds
                $effectiveRoute = $route
                break
            } catch {
                $failureType = $_.Exception.GetType().FullName
                if ($TransportMode -eq 'auto') {
                    # A failed data route loses its last-known-good status; the next attempt
                    # re-probes with the failed route demoted.
                    if ($route) { $failedRoutes += $route }
                    try { Clear-Cf7ArtifactRouteCache -QueueRoot $QueueRoot }
                    catch { Write-Warning "Could not invalidate the GitHub artifact route cache: $($_.Exception.Message)" }
                }
                if ($attempt -ge $Attempts) {
                    throw "Artifact HTTPS transfer exhausted $Attempts attempts; partial retained (failureType=$failureType)."
                }
                Write-Host "[RuntimeGitHubBuild] Artifact transfer interrupted; partial retained, retrying (failureType=$failureType)" -ForegroundColor Yellow
                Start-Sleep -Seconds ([Math]::Min(5, $attempt))
            }
        }
    } finally { $token = $null }

    if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf) -or
            (Get-Item -LiteralPath $partialPath -Force).Length -ne [Int64]$Metadata.Size) {
        throw 'Artifact download did not reach the exact metadata size.'
    }
    Assert-Cf7ArtifactArchiveIdentity -ArchivePath $partialPath -Metadata $Metadata
    [IO.File]::Move($partialPath, $archivePath)
    return [pscustomobject][ordered]@{ ArchivePath = $archivePath; Route = $effectiveRoute }
}

function Test-Cf7ArtifactFile([string]$Root, [string]$Name, [Int64]$MaximumBytes) {
    $path = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Signed cloud artifact lacks file: $Name" }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Cloud artifact file is a reparse point: $Name" }
    if ($item.Length -le 0 -or $item.Length -gt $MaximumBytes) { throw "Cloud artifact file has an unsafe size: $Name ($($item.Length))" }
    return $item.FullName
}

function Expand-Cf7OuterArtifactSafely([string]$ArchivePath, [string]$DestinationRoot) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $DestinationRoot) { throw "Outer artifact extraction destination already exists: $DestinationRoot" }
    $expected = [ordered]@{
        'runtime-candidate.v2.zip' = [Int64]536870912
        'runtime-build-envelope.v2.json' = [Int64]16777216
        'runtime-build-envelope.v2.sigstore.json' = [Int64]16777216
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -ne $expected.Count) { throw 'Outer artifact archive must contain exactly three files.' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        [Int64]$totalLength = 0
        foreach ($entry in $archive.Entries) {
            $raw = ([string]$entry.FullName).Replace('\','/')
            if (-not $expected.Contains($raw) -or $raw.Contains('/') -or -not $seen.Add($raw)) {
                throw "Outer artifact archive contains a path outside the exact file allowlist: $raw"
            }
            [uint32]$attributes = ConvertTo-Cf7UInt32Bits -Value ([int]$entry.ExternalAttributes)
            $unixType = (($attributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000 -or ($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Outer artifact archive contains a link/reparse entry: $raw"
            }
            $maximum = [Int64]$expected[$raw]
            if ($entry.Length -le 0 -or $entry.Length -gt $maximum -or $entry.CompressedLength -lt 0) {
                throw "Outer artifact archive entry has an unsafe size: $raw"
            }
            $totalLength += [Int64]$entry.Length
            if ($totalLength -gt 570425344) { throw 'Outer artifact expands beyond the safety limit.' }
        }

        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
        foreach ($entry in $archive.Entries) {
            $destination = Join-Path $DestinationRoot ([string]$entry.FullName)
            $input = $entry.Open()
            try {
                $output = New-Object IO.FileStream($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $input.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
        }
    } finally { $archive.Dispose() }
    return (Resolve-Path -LiteralPath $DestinationRoot).Path.TrimEnd('\')
}

function Expand-Cf7AttestationArtifactSafely([string]$ArchivePath, [string]$DestinationRoot) {
    # Attestation-only artifact: exactly the deterministic envelope plus its offline Sigstore
    # bundle. The candidate bytes stay in the separate large artifact (or the local producer
    # CAS); this small artifact is the default download for proof verification.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $DestinationRoot) { throw "Attestation extraction destination already exists: $DestinationRoot" }
    $expected = [ordered]@{
        'runtime-build-envelope.v2.json' = [Int64]16777216
        'runtime-build-envelope.v2.sigstore.json' = [Int64]16777216
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -ne $expected.Count) { throw 'Attestation artifact archive must contain exactly two files.' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        [Int64]$totalLength = 0
        foreach ($entry in $archive.Entries) {
            $raw = ([string]$entry.FullName).Replace('\','/')
            if (-not $expected.Contains($raw) -or $raw.Contains('/') -or -not $seen.Add($raw)) {
                throw "Attestation artifact archive contains a path outside the exact file allowlist: $raw"
            }
            [uint32]$attributes = ConvertTo-Cf7UInt32Bits -Value ([int]$entry.ExternalAttributes)
            $unixType = (($attributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000 -or ($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Attestation artifact archive contains a link/reparse entry: $raw"
            }
            $maximum = [Int64]$expected[$raw]
            if ($entry.Length -le 0 -or $entry.Length -gt $maximum -or $entry.CompressedLength -lt 0) {
                throw "Attestation artifact archive entry has an unsafe size: $raw"
            }
            $totalLength += [Int64]$entry.Length
            if ($totalLength -gt 33554432) { throw 'Attestation artifact expands beyond the safety limit.' }
        }

        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
        foreach ($entry in $archive.Entries) {
            $destination = Join-Path $DestinationRoot ([string]$entry.FullName)
            $input = $entry.Open()
            try {
                $output = New-Object IO.FileStream($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $input.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
        }
    } finally { $archive.Dispose() }
    return (Resolve-Path -LiteralPath $DestinationRoot).Path.TrimEnd('\')
}

function Expand-Cf7CandidateArchiveSafely([string]$ArchivePath, [string]$DestinationRoot) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $DestinationRoot) { throw "Candidate extraction destination already exists: $DestinationRoot" }
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    $root = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -lt 2 -or $archive.Entries.Count -gt 512) { throw 'Candidate archive has an unsafe entry count.' }
        [Int64]$totalLength = 0
        foreach ($entry in $archive.Entries) {
            $raw = ([string]$entry.FullName).Replace('\','/')
            if ([string]::IsNullOrWhiteSpace($raw) -or $raw.StartsWith('/') -or $raw.StartsWith('//') -or
                    $raw -match '^[A-Za-z]:' -or $raw.Contains('//') -or $raw.IndexOf([char]0) -ge 0) {
                throw "Unsafe candidate archive path: $raw"
            }
            $isDirectory = $raw.EndsWith('/')
            $normalized = $raw.TrimEnd('/')
            $segments = @($normalized.Split('/'))
            if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw "Unsafe candidate archive path segments: $raw"
            }
            foreach ($segment in $segments) {
                if ($segment -notmatch '^[A-Za-z0-9_.() -]+$') { throw "Unsupported candidate archive path segment: $segment" }
            }
            if ($normalized -ne 'CRAZYFLASHER7MercenaryEmpire.exe' -and
                    $normalized -ne 'runtime-build-metadata.v2.json' -and
                    $normalized -ne 'runtime' -and
                    -not $normalized.StartsWith('runtime/', [StringComparison]::Ordinal)) {
                throw "Candidate archive path is outside the payload allowlist: $normalized"
            }
            if (-not $seen.Add($normalized)) { throw "Duplicate/case-colliding candidate archive path: $normalized" }

            [uint32]$attributes = ConvertTo-Cf7UInt32Bits -Value ([int]$entry.ExternalAttributes)
            $unixType = (($attributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000 -or ($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Candidate archive contains a link/reparse entry: $normalized"
            }

            if (-not $isDirectory) {
                if ($entry.Length -lt 0 -or $entry.Length -gt 268435456) { throw "Candidate archive entry is too large: $normalized" }
                $totalLength += [Int64]$entry.Length
                if ($totalLength -gt 536870912) { throw 'Candidate archive expands beyond the 512 MiB safety limit.' }
            }

            $destination = [IO.Path]::GetFullPath((Join-Path $root ($normalized -replace '/','\')))
            if (-not $destination.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Candidate archive path escapes extraction root: $normalized"
            }
            if ($isDirectory) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                continue
            }
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $input = $entry.Open()
            try {
                $output = New-Object IO.FileStream($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
        }
    } finally { $archive.Dispose() }

    foreach ($required in @('CRAZYFLASHER7MercenaryEmpire.exe','runtime\cf7-runtime-manifest.tsv')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            throw "Extracted candidate lacks required file: $required"
        }
    }
    return $root
}

function Invoke-Cf7ProofVerifier(
    [string]$CandidateRoot,
    [string]$EnvelopePath,
    [string]$BundlePath,
    [string]$ProofPath,
    [switch]$WithoutCandidateArchive
) {
    $verifier = Join-Path $ProjectRoot 'tools\verify-runtime-github-attestation.ps1'
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw "GitHub runtime verifier is missing: $verifier" }
    $powerShell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$verifier,
        '-ProjectRoot',$ProjectRoot,
        '-EnvelopePath',$EnvelopePath,'-BundlePath',$BundlePath,
        '-ExpectedSourceCommitOid',$SourceCommitOid,'-GitHubCliPath',$script:GitHubCli,
        '-OutputPath',$ProofPath
    )
    if ($WithoutCandidateArchive) {
        $arguments += '-WithoutCandidateArchive'
    } else {
        $arguments += @('-CandidateRoot',$CandidateRoot)
    }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    foreach ($line in $output) { Write-Host ([string]$line) }
    if ($exitCode -ne 0) { throw "GitHub runtime attestation verification failed with exit code $exitCode." }
    if (-not (Test-Path -LiteralPath $ProofPath -PathType Leaf)) { throw 'GitHub runtime verifier did not write the normalized proof.' }
    $proof = Get-Content -LiteralPath $ProofPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$proof.schema -ne 'cf7-runtime-github-build-attestation.v2' -or
            [string]$proof.payload.sourceCommitOid -cne $SourceCommitOid) {
        throw 'Normalized GitHub runtime proof does not bind the requested source commit.'
    }
    return $proof
}

$config = Read-Cf7CloudBuilderConfig
$script:GitHubCli = Resolve-Cf7GitHubCli
$workflowFile = [IO.Path]::GetFileName([string]$config.signerWorkflow)
$sourceRefName = ([string]$config.sourceRef) -replace '^refs/(?:heads|tags)/', ''
$expectedRunTitle = "Runtime cloud builder $SourceCommitOid"
# Default scope downloads only the small attestation artifact (deterministic envelope plus
# its Sigstore bundle); the multi-megabyte candidate archive is fetched only on explicit
# request. The workflow itself pins zip==envelope before signing, and promotion re-verifies
# the proof against the local candidate bytes, so the proof path needs no candidate payload.
$artifactScope = if ($IncludeCandidateArchive) { 'candidate-archive' } else { 'attestation-only' }
$artifactName = if ($IncludeCandidateArchive) {
    "runtime-cloud-builder-$SourceCommitOid"
} else {
    "runtime-cloud-attestation-$SourceCommitOid"
}
$artifactTransportMode = Resolve-Cf7ArtifactTransportMode -ParameterValue $GitHubArtifactTransport -EnvironmentValue $env:CF7_GITHUB_ARTIFACT_TRANSPORT
$artifactQueueRoot = Get-Cf7RuntimeQueueRoot -ProjectRoot $ProjectRoot

$head = Invoke-Cf7GitText @('rev-parse','HEAD^{commit}')
if ($head.ToLowerInvariant() -cne $SourceCommitOid) {
    throw "Current checkout must equal SourceCommitOid for proof verification: expected=$SourceCommitOid actual=$head"
}
Invoke-Cf7GitText @('diff','--quiet','--exit-code') | Out-Null
Invoke-Cf7GitText @('diff','--cached','--quiet','--exit-code') | Out-Null
$sourceTagCommit = Resolve-Cf7ConfiguredSourceTagCommit -Config $config
if ($sourceTagCommit -cne $SourceCommitOid) {
    throw "Configured GitHub source tag does not resolve to SourceCommitOid: ref=$($config.sourceRef) expected=$SourceCommitOid actual=$sourceTagCommit"
}

if (-not $OutputRoot) { $OutputRoot = Join-Path $ProjectRoot ("tmp\runtime-cloud-results\$SourceCommitOid") }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ([IO.Path]::GetPathRoot($OutputRoot) -eq $OutputRoot) { throw 'OutputRoot must be a dedicated directory, not a filesystem root.' }
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null }
$outputRootItem = Get-Item -LiteralPath $OutputRoot -Force
if (($outputRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OutputRoot cannot be a reparse point.' }

$run = $null
if ($ResumeRunId -gt 0) {
    $runId = $ResumeRunId
    Write-Host "[RuntimeGitHubBuild] Resume selected run=$runId" -ForegroundColor Cyan
    $run = Invoke-Cf7GhJson -Arguments @(
        'run','view',[string]$runId,'--repo',[string]$config.repository,
        '--json','databaseId,displayTitle,headBranch,headSha,status,conclusion,createdAt,event,url'
    )
} else {
    $beforeRuns = @(Get-Cf7CloudRuns -Repository ([string]$config.repository) -WorkflowFile $workflowFile)
    $beforeIds = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($knownRun in $beforeRuns) { [void]$beforeIds.Add([Int64]$knownRun.databaseId) }

    Write-Host "[RuntimeGitHubBuild] Dispatch source=$SourceCommitOid workflow=$workflowFile ref=$sourceRefName" -ForegroundColor Cyan
    Invoke-Cf7Gh -Arguments @(
        'workflow','run',$workflowFile,'--repo',[string]$config.repository,
        '--ref',$sourceRefName,'-f',"source_commit=$SourceCommitOid"
    ) -AllowEmpty | Out-Null

    $discoveryDeadline = [DateTime]::UtcNow.AddSeconds($DiscoveryTimeoutSeconds)
    do {
        $candidates = @(Get-Cf7CloudRuns -Repository ([string]$config.repository) -WorkflowFile $workflowFile | Where-Object {
            [string]$_.displayTitle -ceq $expectedRunTitle -and
            [string]$_.headBranch -ceq $sourceRefName -and
            [string]$_.headSha -ceq $SourceCommitOid -and
            [string]$_.event -eq 'workflow_dispatch' -and
            -not $beforeIds.Contains([Int64]$_.databaseId)
        })
        if ($candidates.Count -gt 0) {
            $run = @($candidates | Sort-Object {[Int64]$_.databaseId} | Select-Object -First 1)[0]
            break
        }
        if ([DateTime]::UtcNow -ge $discoveryDeadline) { break }
        Start-Sleep -Seconds $PollSeconds
    } while ($true)
    if ($null -eq $run) { throw "Timed out locating dispatched GitHub run with title: $expectedRunTitle" }
    $runId = [Int64]$run.databaseId
}

Assert-Cf7RunIdentity -Run $run -ExpectedId $runId -ExpectedTitle $expectedRunTitle `
    -ExpectedBranch $sourceRefName -ExpectedHeadSha $SourceCommitOid
Write-Host "[RuntimeGitHubBuild] Located run=$runId url=$($run.url)" -ForegroundColor Cyan

$runDeadline = [DateTime]::UtcNow.AddSeconds($RunTimeoutSeconds)
do {
    $run = Invoke-Cf7GhJson -Arguments @(
        'run','view',[string]$runId,'--repo',[string]$config.repository,
        '--json','databaseId,displayTitle,headBranch,headSha,status,conclusion,createdAt,event,url'
    )
    Assert-Cf7RunIdentity -Run $run -ExpectedId $runId -ExpectedTitle $expectedRunTitle `
        -ExpectedBranch $sourceRefName -ExpectedHeadSha $SourceCommitOid
    if ([string]$run.status -eq 'completed') { break }
    if ([DateTime]::UtcNow -ge $runDeadline) { throw "Timed out waiting for GitHub runtime run: $runId" }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
if ([string]$run.conclusion -ne 'success') {
    throw "GitHub runtime run failed: run=$runId conclusion=$($run.conclusion) url=$($run.url)"
}

$artifactMetadata = Get-Cf7ArtifactMetadata -Repository ([string]$config.repository) -RunId $runId `
    -ArtifactName $artifactName -ExpectedHeadSha $SourceCommitOid
$resultRoot = Join-Path $OutputRoot ("run-$runId")
if (Test-Path -LiteralPath $resultRoot -PathType Container) {
    $resultRootItem = Get-Item -LiteralPath $resultRoot -Force
    if (($resultRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Cloud result directory cannot be a reparse point.' }
    $unexpectedResultState = @(Get-ChildItem -LiteralPath $resultRoot -Force | Where-Object { $_.Name -cne 'artifact-download' })
    if ($unexpectedResultState.Count -gt 0) { throw "Cloud result directory already contains non-resumable state: $resultRoot" }
} elseif (Test-Path -LiteralPath $resultRoot) {
    throw "Cloud result path is not a directory: $resultRoot"
} else {
    New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
}
$transportRoot = Join-Path $resultRoot 'artifact-download'
$downloadRoot = Join-Path $resultRoot 'signed-artifact'
Write-Host "[RuntimeGitHubBuild] Receive signed artifact=$artifactName id=$($artifactMetadata.Id) bytes=$($artifactMetadata.Size) scope=$artifactScope" -ForegroundColor Cyan
$download = Receive-Cf7ArtifactArchive -Metadata $artifactMetadata -TransportRoot $transportRoot `
    -PreDownloadedPath $PreDownloadedArtifactArchive -Attempts $ArtifactDownloadAttempts `
    -TimeoutSeconds $ArtifactDownloadTimeoutSeconds -TransportMode $artifactTransportMode `
    -ConnectTimeoutSeconds $ArtifactConnectTimeoutSeconds -StallTimeoutSeconds $ArtifactStallTimeoutSeconds `
    -QueueRoot $artifactQueueRoot
$outerArchivePath = [string]$download.ArchivePath
$artifactRoute = $download.Route

$proofPath = Join-Path $resultRoot 'verified-github-proof.v2.json'
if ($IncludeCandidateArchive) {
    $downloadRoot = Expand-Cf7OuterArtifactSafely -ArchivePath $outerArchivePath -DestinationRoot $downloadRoot
    $archivePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-candidate.v2.zip' -MaximumBytes 536870912
    $envelopePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-build-envelope.v2.json' -MaximumBytes 16777216
    $bundlePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-build-envelope.v2.sigstore.json' -MaximumBytes 16777216
    $candidateRoot = Expand-Cf7CandidateArchiveSafely -ArchivePath $archivePath -DestinationRoot (Join-Path $resultRoot 'candidate')
    $proof = Invoke-Cf7ProofVerifier -CandidateRoot $candidateRoot -EnvelopePath $envelopePath -BundlePath $bundlePath -ProofPath $proofPath
} else {
    $downloadRoot = Expand-Cf7AttestationArtifactSafely -ArchivePath $outerArchivePath -DestinationRoot $downloadRoot
    $envelopePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-build-envelope.v2.json' -MaximumBytes 16777216
    $bundlePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-build-envelope.v2.sigstore.json' -MaximumBytes 16777216
    $candidateRoot = $null
    $proof = Invoke-Cf7ProofVerifier -EnvelopePath $envelopePath -BundlePath $bundlePath -ProofPath $proofPath -WithoutCandidateArchive
}

$result = [pscustomobject][ordered]@{
    schema = 'cf7-runtime-github-build-invocation.v2'
    sourceCommitOid = $SourceCommitOid
    repository = [string]$config.repository
    workflow = $workflowFile
    runId = $runId
    runUrl = [string]$run.url
    artifactName = $artifactName
    artifactScope = $artifactScope
    artifactId = [Int64]$artifactMetadata.Id
    artifactArchiveBytes = [Int64]$artifactMetadata.Size
    artifactArchiveSha256 = [string]$artifactMetadata.DigestSha256
    artifactTransport = $(if ($PreDownloadedArtifactArchive) { 'pre-downloaded-outer-archive' } else { 'github-rest-https-resumable' })
    artifactTransportMode = $artifactTransportMode
    artifactRoute = $artifactRoute
    outerArchivePath = $outerArchivePath
    resultRoot = $resultRoot
    candidateRoot = $candidateRoot
    envelopePath = $envelopePath
    bundlePath = $bundlePath
    proofPath = $proofPath
    buildIdentityHash = [string]$proof.payload.buildIdentityHash
    payloadClosureHash = [string]$proof.payload.payloadClosureHash
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$resultPath = Join-Path $resultRoot 'runtime-github-build-result.v2.json'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($resultPath, (($result | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)
Write-Host "[RuntimeGitHubBuild] OK run=$runId scope=$artifactScope proof=$proofPath candidate=$candidateRoot" -ForegroundColor Green
if ($Json) { $result | ConvertTo-Json -Depth 8 } else { $result }
