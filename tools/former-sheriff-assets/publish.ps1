param([int]$TimeoutSeconds = 240)
$ErrorActionPreference = 'Stop'
$sheriffRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$sheriffEvidence = Join-Path $sheriffRoot 'tmp/former-sheriff-integration'
Push-Location $sheriffRoot
try {
    if (Test-Path -LiteralPath 'scripts/compile_state_uncertain.marker') {
        throw 'Existing uncertain compile: resolve the CS6 dialog and review late terminal evidence under the recovery protocol before retrying.'
    }
    $targets = @(
        @('codex', 'flashswf/arts/new/Codex专用素材/Codex专用素材.xfl', 'flashswf/arts/new/Codex专用素材.swf'),
        @('things-new', 'flashswf/arts/things-new.fla', 'flashswf/arts/things-new.swf'),
        @('base', 'flashswf/levels/基地场景合集/基地场景合集.xfl', 'flashswf/levels/基地场景合集.swf'),
        @('frontline', 'flashswf/levels/地图-第一防线防区/地图-第一防线防区.xfl', 'flashswf/levels/地图-第一防线防区.swf')
    )
    $receipt = @()
    foreach ($row in $targets) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target $row[1] -PublishOnly -VerifySwf $row[2] -TimeoutSeconds $TimeoutSeconds
        if ($LASTEXITCODE -ne 0) { throw "Publication failed: $($row[0])" }
        Copy-Item -LiteralPath 'scripts/compiler_errors.txt' -Destination (Join-Path $sheriffEvidence ($row[0] + '-compiler-errors.txt'))
        Copy-Item -LiteralPath 'scripts/compile_output.txt' -Destination (Join-Path $sheriffEvidence ($row[0] + '-compile-output.txt'))
        $file = Get-Item -LiteralPath $row[2]
        $receipt += @{ target=$row[1]; swf=$row[2]; sha256=(Get-FileHash -LiteralPath $row[2] -Algorithm SHA256).Hash; bytes=$file.Length; publishedUtc=$file.LastWriteTimeUtc.ToString('o') }
        $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $sheriffEvidence 'publish-receipt.json') -Encoding UTF8
    }
} finally { Pop-Location }
