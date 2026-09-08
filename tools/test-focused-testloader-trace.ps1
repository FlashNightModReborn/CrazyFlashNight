$ErrorActionPreference = 'Stop'
$fixtureBase = Join-Path (Split-Path -Parent $PSScriptRoot) 'tmp/focused-testloader-trace'
$runnerSource = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/test-runners/run-focused-testloader.ps1'))
$startText = '        $trace = Get-Content -LiteralPath $tracePath -Raw -Encoding UTF8'
$endText = '        $errors = Get-Content -LiteralPath $errorsPath -Raw -Encoding UTF8'
$startAt = $runnerSource.IndexOf($startText)
$endAt = $runnerSource.IndexOf($endText, $startAt)
if ($startAt -lt 0 -or $endAt -le $startAt) { throw 'Trace processing block not found' }
$productionBlock = $runnerSource.Substring($startAt, $endAt - $startAt)
$productionBlock = $productionBlock.Replace('Join-Path $env:APPDATA', 'Join-Path $fixtureRoot')
$DomainId = 'blood-sword'
$runId = 'trace-fixture-current'
$TimeoutSeconds = 1
$ExpectedTracePatterns = @('(?m)^BloodSwordLifecycleTest Tests Passed: 56\r?$', '(?m)^BloodSwordLifecycleTest Tests Failed: 0\r?$')
$startLine = "FocusedTestRunId $DomainId Start: $runId"
$endLine = "FocusedTestRunId $DomainId Complete: $runId"
$good = "$startLine`nBloodSwordLifecycleTest Tests Passed: 56`nBloodSwordLifecycleTest Tests Failed: 0`n$endLine`n"
$foreign = $good.Replace($runId, 'trace-fixture-previous')
$results = @()
function Test-Case([string]$Name, [string]$Local, [string]$Raw, [bool]$Expected) {
    $fixtureRoot = Join-Path $fixtureBase $Name
    $rawFolder = Join-Path $fixtureRoot 'Macromedia/Flash Player/Logs'
    New-Item -ItemType Directory -Path $rawFolder -Force | Out-Null
    $tracePath = Join-Path $fixtureRoot 'local.txt'
    [IO.File]::WriteAllText($tracePath, $Local, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $rawFolder 'flashlog.txt'), $Raw, [Text.UTF8Encoding]::new($false))
    $behaviorTerminalObserved = $false
    $actual = $false
    try { Invoke-Expression $productionBlock; $actual = $true } catch { $reason = $_.Exception.Message }
    if ($actual -ne $Expected) { throw "Trace fixture $Name expected $Expected, got $actual : $reason" }
    return @{name=$Name; accepted=$actual; terminal=$behaviorTerminalObserved; passed=$true}
}
$results += Test-Case 'complete-local' $good '' $true
$results += Test-Case 'late-complete' "$startLine`n" $good $true
$results += Test-Case 'wrong-run' "$startLine`n" $foreign $false
$results += Test-Case 'duplicate-start' "$startLine`n" ("$startLine`n" + $good) $false
$results += Test-Case 'duplicate-complete' "$startLine`n" ($good + "$endLine`n") $false
$results += Test-Case 'complete-before-start' "$startLine`n" ("$endLine`n" + $good) $false
$results += Test-Case 'late-failure' "$startLine`n" ($good.Replace('Passed: 56','Passed: 55').Replace('Failed: 0','Failed: 1')) $false
$results += Test-Case 'foreign-history' "$startLine`n" ($foreign + $good) $true
$results += Test-Case 'duplicate-local' ("$startLine`n" + $good) '' $false
$results += Test-Case 'only-complete' "$startLine`n" "$endLine`n" $false
$report = @{passed=$true; cases=$results; count=$results.Count}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $fixtureBase 'trace-wait-check.json') -Encoding UTF8
Write-Host ('Focused trace wait: {0}/{0} fixtures passed' -f $results.Count)
