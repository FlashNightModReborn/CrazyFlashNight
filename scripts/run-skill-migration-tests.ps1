[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $projectDir 'scripts\TestLoader.as'
$templatePath = Join-Path $projectDir 'scripts\test-runners\skill-migration\TestLoader.as.template'
$compilePath = Join-Path $projectDir 'scripts\compile_test.ps1'
$backupPath = $null
$hadRunner = Test-Path -LiteralPath $runnerPath

try {
    if ($hadRunner) {
        $backupPath = Join-Path ([IO.Path]::GetTempPath()) ('cf7-TestLoader-' + [Guid]::NewGuid().ToString('N') + '.as')
        Copy-Item -LiteralPath $runnerPath -Destination $backupPath
    }

    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $bytes = [IO.File]::ReadAllBytes($runnerPath)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        throw 'Skill TestLoader template is not UTF-8 with BOM.'
    }

    Write-Host '[INFO] Installed SkillMigrationTestSuite TestLoader runner.'
    if (-not $SkipCompile) {
        & powershell -ExecutionPolicy Bypass -File $compilePath -Target test -TimeoutSeconds $TimeoutSeconds
        if ($LASTEXITCODE -ne 0) { throw "Skill TestLoader failed with exit code $LASTEXITCODE" }
    }
}
finally {
    if ($hadRunner -and $backupPath -and (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $backupPath -Destination $runnerPath -Force
        Remove-Item -LiteralPath $backupPath -Force
        Write-Host '[INFO] Restored original TestLoader scratch runner.'
    } elseif (-not $hadRunner -and (Test-Path -LiteralPath $runnerPath)) {
        Remove-Item -LiteralPath $runnerPath -Force
        Write-Host '[INFO] Removed temporary TestLoader scratch runner.'
    }
}
