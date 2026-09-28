param(
    [ValidateSet('overview','low')][string]$CameraSet = 'overview',
    [ValidateSet('default','high-performance')][string]$Adapter = 'default'
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$probeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $probeRoot 'launcher\resolve-dotnet.ps1')
$probeDotnet = Resolve-Cf7Dotnet -ProjectRoot $probeRoot
$probeDll = Join-Path $PSScriptRoot 'bin\Release\net10.0-windows\Issue122.WebView2.dll'
if (-not (Test-Path -LiteralPath $probeDll)) { throw 'Build the probe before running.' }
$probeRunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$probeParent = Join-Path $probeRoot 'tmp\issue122-local'
New-Item -ItemType Directory -Path $probeParent -Force | Out-Null
$probeOutput = Join-Path $probeParent $probeRunId
$previousCamera = $env:CF7_ISSUE122_CAMERA_SET
$previousGpu = $env:CF7_ISSUE122_GPU_ARGS
try {
    $env:CF7_ISSUE122_CAMERA_SET = $CameraSet
    $env:CF7_ISSUE122_GPU_ARGS = if ($Adapter -eq 'high-performance') { '--force-high-performance-gpu' } else { '' }
    $probeArgs = @(('"'+$probeDll+'"'),('"'+$probeRoot+'"'),('"'+$probeOutput+'"'))
    $probeChild = Start-Process -FilePath $probeDotnet -ArgumentList $probeArgs -WorkingDirectory $probeRoot -WindowStyle Hidden -PassThru
    [pscustomobject]@{probePid=$probeChild.Id;runRoot=$probeOutput;cameraSet=$CameraSet;requestedAdapter=$Adapter} | ConvertTo-Json -Compress
    $probeTimer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $probeChild.HasExited -and $probeTimer.Elapsed.TotalSeconds -lt 240) {
        Start-Sleep -Milliseconds 500
        $probeChild.Refresh()
    }
    if (-not $probeChild.HasExited) { $probeChild.Kill(); throw 'Owned probe exceeded the 240 second deadline.' }
    $probeChild.WaitForExit()
    $probeSourceFiles = @('Program.cs','ProbeRules.cs','Issue122.WebView2.csproj') | ForEach-Object {
        [pscustomobject]@{path=$_;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $PSScriptRoot $_)).Hash}
    }
    $probeExecution = [pscustomobject]@{
        baseCommit=(& git -C $probeRoot rev-parse HEAD);sdk=(& $probeDotnet --version)
        dllSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $probeDll).Hash
        sourceFiles=@($probeSourceFiles);cameraSet=$CameraSet;requestedAdapter=$Adapter
        gpuArguments=$env:CF7_ISSUE122_GPU_ARGS;exitCode=$probeChild.ExitCode
        elapsedSeconds=$probeTimer.Elapsed.TotalSeconds
    }
    [IO.File]::WriteAllText((Join-Path $probeOutput 'execution.json'),($probeExecution | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    $probeResult=Get-Content -Raw -LiteralPath (Join-Path $probeOutput 'result.json') -Encoding UTF8 | ConvertFrom-Json
    [pscustomobject]@{runRoot=$probeOutput;status=$probeResult.status;classification=$probeResult.classification;backendVerified=$probeResult.backendVerified;observedGpu=$probeResult.cells[0].gl.unmaskedRenderer;cells=$probeResult.cells.Count;exitCode=$probeChild.ExitCode} | ConvertTo-Json -Compress
    exit $probeChild.ExitCode
} finally {
    $env:CF7_ISSUE122_CAMERA_SET = $previousCamera
    $env:CF7_ISSUE122_GPU_ARGS = $previousGpu
}
